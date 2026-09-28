import Foundation
import Observation
import WhisperKit

enum WhisperModelOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard = "openai_whisper-base.en"
    case accurate = "openai_whisper-small.en_217MB"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .accurate: "High Accuracy"
        }
    }

    var detail: String {
        switch self {
        case .standard: "Fast. Catches most filler words."
        case .accurate: "Slower, better at catching every um and stutter."
        }
    }

    var approximateSizeMB: Int {
        switch self {
        case .standard: 147
        case .accurate: 218
        }
    }
}

/// Owns download, on-disk storage and in-memory loading of the Whisper model.
@MainActor
@Observable
final class WhisperModelManager {
    static let shared = WhisperModelManager()

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        /// Loading into memory / specializing for the Neural Engine (first load can take a minute).
        case loading
        case ready
        case failed(String)
    }

    /// State of the currently selected model.
    private(set) var state: State = .notDownloaded

    /// The model the user picked (persisted under `AppSettings.Keys.whisperModel`).
    var selectedModel: WhisperModelOption = .standard

    @ObservationIgnored private var pipelines: [WhisperModelOption: WhisperKit] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTasks: [WhisperModelOption: Task<Void, Never>] = [:]

    init() {
        if let raw = UserDefaults.standard.string(forKey: AppSettings.Keys.whisperModel),
           let option = WhisperModelOption(rawValue: raw) {
            selectedModel = option
        }
        state = isDownloaded(selectedModel) ? .downloaded : .notDownloaded
    }

    func isDownloaded(_ option: WhisperModelOption) -> Bool {
        let folder = Self.modelFolderURL(for: option)
        return ["AudioEncoder", "TextDecoder", "MelSpectrogram"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("\($0).mlmodelc").path)
        }
    }

    /// Downloads the given model (progress reflected in `state` when it's the selected model).
    func download(_ option: WhisperModelOption) async {
        if downloadTasks[option] != nil { return }

        if option == selectedModel { state = .downloading(progress: 0) }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await WhisperKit.download(
                    variant: option.rawValue,
                    downloadBase: MediaStore.modelsDirectory,
                    progressCallback: { progress in
                        Task { @MainActor in
                            guard option == self.selectedModel else { return }
                            self.state = .downloading(progress: progress.fractionCompleted)
                        }
                    }
                )
                if option == self.selectedModel {
                    self.state = .downloaded
                    await self.prepare()
                }
            } catch {
                if option == self.selectedModel {
                    self.state = .failed(error.localizedDescription)
                }
            }
            self.downloadTasks[option] = nil
        }
        downloadTasks[option] = task
        await task.value
    }

    /// Loads the selected model into memory if it is downloaded. No-op if already ready.
    func prepare() async {
        let option = selectedModel

        guard isDownloaded(option) else {
            state = .notDownloaded
            return
        }
        if pipelines[option] != nil, case .ready = state {
            return
        }
        if let loadTask {
            await loadTask.value
            return
        }

        state = .loading
        let folder = Self.modelFolderURL(for: option)
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let pipeline = try await WhisperKit(WhisperKitConfig(
                    model: option.rawValue,
                    downloadBase: MediaStore.modelsDirectory,
                    modelFolder: folder.path,
                    tokenizerFolder: MediaStore.modelsDirectory,
                    verbose: false,
                    logLevel: .error,
                    prewarm: true,
                    load: true,
                    download: false
                ))
                self.pipelines[option] = pipeline
                if option == self.selectedModel {
                    self.state = .ready
                }
            } catch {
                if option == self.selectedModel {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Switches the selected model, persisting the choice. Unloads the previous pipeline.
    func select(_ option: WhisperModelOption) {
        guard option != selectedModel else { return }
        let previous = selectedModel
        selectedModel = option
        UserDefaults.standard.set(option.rawValue, forKey: AppSettings.Keys.whisperModel)
        pipelines[previous] = nil

        if isDownloaded(option) {
            state = pipelines[option] != nil ? .ready : .downloaded
            if pipelines[option] == nil {
                Task { await prepare() }
            }
        } else {
            state = .notDownloaded
        }
    }

    /// Deletes a downloaded model from disk.
    func delete(_ option: WhisperModelOption) {
        try? FileManager.default.removeItem(at: Self.modelFolderURL(for: option))
        pipelines[option] = nil
        if option == selectedModel {
            state = .notDownloaded
        }
    }

    /// Returns a loaded WhisperKit pipeline for the selected model, loading it if needed.
    /// Throws if the model isn't downloaded.
    func pipeline() async throws -> WhisperKit {
        let option = selectedModel
        if let pipeline = pipelines[option], case .ready = state {
            return pipeline
        }
        guard isDownloaded(option) else {
            throw TranscriptionError.modelUnavailable
        }
        await prepare()
        guard let pipeline = pipelines[option], case .ready = state else {
            throw TranscriptionError.modelUnavailable
        }
        return pipeline
    }

    /// Downloading or loading the selected model.
    var isBusy: Bool {
        switch state {
        case .downloading, .loading: true
        default: false
        }
    }

    /// Human-readable status for the selected model, for settings UI.
    var statusText: String {
        switch state {
        case .notDownloaded: "Not downloaded"
        case .downloading(let progress): "Downloading… \(Int((progress * 100).rounded()))%"
        case .downloaded: "Downloaded"
        case .loading: "Preparing…"
        case .ready: "Ready"
        case .failed(let message): message
        }
    }

    /// On-disk location for a model variant, mirroring WhisperKit's Hugging Face Hub cache layout
    /// (`<downloadBase>/models/argmaxinc/whisperkit-coreml/<variant>`). Never persist this path;
    /// always recompute it from `MediaStore.modelsDirectory`, since app container paths change
    /// across installs/updates.
    private static func modelFolderURL(for option: WhisperModelOption) -> URL {
        MediaStore.modelsDirectory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(option.rawValue, isDirectory: true)
    }
}
