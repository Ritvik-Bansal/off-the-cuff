@preconcurrency import AVFoundation
import Observation

/// Front-camera + microphone recorder built on AVCaptureSession / AVCaptureMovieFileOutput.
@MainActor
@Observable
final class CameraRecorder {
    enum Status: Equatable {
        case idle
        case configuring
        case ready
        case recording
        case unauthorized
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// Normalized 0...1 microphone level, updated ~20x/s while the session runs.
    private(set) var audioLevel: Float = 0
    /// Whether the current configuration includes the camera.
    private(set) var videoEnabled: Bool = true

    /// The capture session, for `CameraPreviewView`.
    @ObservationIgnored nonisolated let session = AVCaptureSession()

    // All of these are only ever touched from `sessionQueue`, so they're marked `nonisolated`
    // to allow the session-configuration code below to run off the main actor without hopping.
    @ObservationIgnored private nonisolated(unsafe) var videoDeviceInput: AVCaptureDeviceInput?
    @ObservationIgnored private nonisolated(unsafe) var audioDeviceInput: AVCaptureDeviceInput?
    @ObservationIgnored private nonisolated(unsafe) var movieOutput: AVCaptureMovieFileOutput?

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.speak.camerarecorder.session")
    @ObservationIgnored private var levelTimer: Timer?
    @ObservationIgnored private var smoothedLevel: Float = 0
    @ObservationIgnored private var recordingDelegate: RecordingDelegate?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var runtimeErrorObserver: NSObjectProtocol?

    init() {}

    /// Requests permissions (camera only when `videoEnabled`), configures inputs/outputs
    /// and starts the session running. Sets `status` to `.ready`, `.unauthorized` or `.failed`.
    func configure(videoEnabled: Bool) async {
        status = .configuring

        guard await Self.requestAccess(for: .audio) else {
            status = .unauthorized
            return
        }
        if videoEnabled {
            guard await Self.requestAccess(for: .video) else {
                status = .unauthorized
                return
            }
        }

        self.videoEnabled = videoEnabled

        let outcome: Result<Void, CameraConfigurationError> = await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .failure(CameraConfigurationError(message: "Recorder was released.")))
                    return
                }
                continuation.resume(returning: self.configureSession(videoEnabled: videoEnabled))
            }
        }

        switch outcome {
        case .success:
            addObservers()
            startLevelMonitoring()
            status = .ready
        case .failure(let error):
            status = .failed(error.message)
        }
    }

    /// Begins recording to a new temporary .mov file. Status becomes `.recording`.
    func startRecording() {
        guard status == .ready, let movieOutput else { return }
        let url = MediaStore.newTemporaryRecordingURL()
        let delegate = RecordingDelegate()
        recordingDelegate = delegate
        status = .recording
        sessionQueue.async {
            movieOutput.startRecording(to: url, recordingDelegate: delegate)
        }
    }

    /// Stops recording and waits for the file to finish writing.
    /// Returns the temp file URL, or nil on failure. Status returns to `.ready`.
    func stopRecording() async -> URL? {
        guard let movieOutput, let delegate = recordingDelegate else { return nil }

        let url: URL? = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            delegate.completion = { result in
                switch result {
                case .success(let url): continuation.resume(returning: url)
                case .failure: continuation.resume(returning: nil)
                }
            }
            sessionQueue.async {
                movieOutput.stopRecording()
            }
        }

        recordingDelegate = nil
        if status == .recording { status = .ready }
        return url
    }

    /// Stops the session and releases devices. Safe to call multiple times.
    func teardown() {
        removeObservers()
        stopLevelMonitoring()
        recordingDelegate = nil

        let session = self.session
        sessionQueue.async { [weak self] in
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            if session.isRunning {
                session.stopRunning()
            }
            self?.videoDeviceInput = nil
            self?.audioDeviceInput = nil
            self?.movieOutput = nil
        }
        status = .idle
    }

    // MARK: - Session configuration (runs on `sessionQueue`)

    /// Tears down any existing inputs/outputs and rebuilds the session for the given mode.
    /// Must only be called on `sessionQueue`.
    private nonisolated func configureSession(videoEnabled: Bool) -> Result<Void, CameraConfigurationError> {
        session.beginConfiguration()

        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        videoDeviceInput = nil
        audioDeviceInput = nil
        movieOutput = nil

        session.sessionPreset = videoEnabled ? .hd1280x720 : .high

        if videoEnabled {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                session.commitConfiguration()
                return .failure(CameraConfigurationError(message: "Camera unavailable on this device"))
            }
            guard let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
                session.commitConfiguration()
                return .failure(CameraConfigurationError(message: "Camera unavailable on this device"))
            }
            session.addInput(input)
            videoDeviceInput = input
        }

        guard let microphone = AVCaptureDevice.default(for: .audio),
              let micInput = try? AVCaptureDeviceInput(device: microphone),
              session.canAddInput(micInput) else {
            session.commitConfiguration()
            return .failure(CameraConfigurationError(message: "Microphone unavailable on this device"))
        }
        session.addInput(micInput)
        audioDeviceInput = micInput

        let output = AVCaptureMovieFileOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return .failure(CameraConfigurationError(message: "Couldn't configure the recording output."))
        }
        session.addOutput(output)
        movieOutput = output

        if videoEnabled, let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
            if output.availableVideoCodecTypes.contains(.hevc) {
                output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
            }
        }

        session.commitConfiguration()

        if !session.isRunning {
            session.startRunning()
        }

        return .success(())
    }

    // MARK: - Permissions

    private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        default:
            return false
        }
    }

    // MARK: - Audio level monitoring

    private func startLevelMonitoring() {
        levelTimer?.invalidate()
        smoothedLevel = 0
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateAudioLevel() }
        }
    }

    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
        smoothedLevel = 0
    }

    private func updateAudioLevel() {
        guard session.isRunning,
              let connection = movieOutput?.connection(with: .audio),
              let channel = connection.audioChannels.first else {
            return
        }
        let normalized = Self.normalizedLevel(fromDecibels: channel.averagePowerLevel)
        smoothedLevel = smoothedLevel * 0.7 + normalized * 0.3
        audioLevel = smoothedLevel
    }

    private static func normalizedLevel(fromDecibels db: Float) -> Float {
        guard db.isFinite else { return 0 }
        let minDb: Float = -50
        if db <= minDb { return 0 }
        if db >= 0 { return 1 }
        return (db - minDb) / -minDb
    }

    // MARK: - Interruptions

    private func addObservers() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleInterruption(notification) }
        }
        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleRuntimeError(notification) }
        }
    }

    private func removeObservers() {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let runtimeErrorObserver { NotificationCenter.default.removeObserver(runtimeErrorObserver) }
        interruptionObserver = nil
        runtimeErrorObserver = nil
    }

    private func handleInterruption(_ notification: Notification) {
        guard status == .recording else { return }
        finishInterruptedRecording(message: "Recording was interrupted.")
    }

    private func handleRuntimeError(_ notification: Notification) {
        let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
            ?? "The camera session stopped unexpectedly."

        if status == .recording {
            finishInterruptedRecording(message: message)
        } else {
            status = .failed(message)
        }

        let session = self.session
        sessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    private func finishInterruptedRecording(message: String) {
        let output = movieOutput
        sessionQueue.async {
            output?.stopRecording()
        }
        recordingDelegate = nil
        status = .failed(message)
    }
}

/// Lightweight error carrying a user-facing message from session configuration on `sessionQueue`.
private struct CameraConfigurationError: Error {
    let message: String
}

/// Bridges the delegate-based `AVCaptureFileOutputRecordingDelegate` callback to a single completion,
/// invoked exactly once.
private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    var completion: ((Result<URL, Error>) -> Void)?

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        lock.lock()
        guard !didFinish else { lock.unlock(); return }
        didFinish = true
        lock.unlock()

        if let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
            completion?(.failure(error))
        } else {
            completion?(.success(outputFileURL))
        }
        completion = nil
    }
}
