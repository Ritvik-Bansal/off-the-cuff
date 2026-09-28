import AVFoundation
import CoreMedia

/// Decodes a recording's audio track into mono Float32 samples for the transcription pipeline.
enum AudioExtractor {
    /// Sample rate of the returned samples (what Whisper expects).
    static let sampleRate: Double = 16_000

    /// Decodes the audio track of a movie/audio file into mono Float32 samples at `sampleRate`.
    static func loadSamples(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)

        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw TranscriptionError.failed("Couldn't read the recording: \(error.localizedDescription)")
        }
        guard let track = tracks.first else {
            throw TranscriptionError.failed("The recording doesn't contain any audio.")
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        do {
            reader = try AVAssetReader(asset: asset)
            output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        } catch {
            throw TranscriptionError.failed("Couldn't set up audio decoding: \(error.localizedDescription)")
        }
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw TranscriptionError.failed("Couldn't configure audio decoding for this recording.")
        }
        reader.add(output)

        guard reader.startReading() else {
            let message = reader.error?.localizedDescription ?? "unknown error"
            throw TranscriptionError.failed("Couldn't start decoding the recording's audio: \(message)")
        }

        var samples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let floatCount = length / MemoryLayout<Float>.size
            guard floatCount > 0 else { continue }

            var chunk = [Float](repeating: 0, count: floatCount)
            let status = chunk.withUnsafeMutableBytes { destination -> OSStatus in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: destination.baseAddress!)
            }
            if status == noErr {
                samples.append(contentsOf: chunk)
            }
        }

        if reader.status == .failed {
            let message = reader.error?.localizedDescription ?? "unknown error"
            throw TranscriptionError.failed("Decoding the recording's audio failed: \(message)")
        }

        guard !samples.isEmpty else {
            throw TranscriptionError.failed("No audio samples were found in the recording.")
        }

        return samples
    }
}
