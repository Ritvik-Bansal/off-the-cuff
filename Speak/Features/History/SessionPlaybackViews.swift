import AVFoundation
import AVKit
import SwiftUI

/// Portrait video playback for sessions recorded with camera.
struct VideoPlayerCard: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .frame(maxHeight: 440)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .padding(.horizontal)
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
            }
            .accessibilityLabel("Recording video player")
    }
}

/// Drives playback state for `AudioPlayerCard` outside the view's value-type lifecycle.
@MainActor
@Observable
private final class AudioPlayerModel {
    let player: AVPlayer
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var isScrubbing = false

    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.player.seek(to: .zero)
                self?.isPlaying = false
                self?.currentTime = 0
            }
        }

        Task { [weak self] in
            guard let self, let loaded = try? await item.asset.load(.duration) else { return }
            self.duration = loaded.seconds.isFinite ? loaded.seconds : 0
        }
    }

    func toggle() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func stop() {
        player.pause()
        if let timeObserverToken { player.removeTimeObserver(timeObserverToken) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}

/// Compact play/pause + scrubber card for audio-only sessions.
struct AudioPlayerCard: View {
    let url: URL

    @State private var model: AudioPlayerModel?

    var body: some View {
        HStack(spacing: 16) {
            Button {
                model?.toggle()
            } label: {
                Image(systemName: (model?.isPlaying ?? false) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
            }
            .disabled(model == nil)
            .accessibilityLabel((model?.isPlaying ?? false) ? "Pause recording" : "Play recording")

            VStack(alignment: .leading, spacing: 4) {
                Slider(
                    value: Binding(
                        get: { model?.currentTime ?? 0 },
                        set: { model?.seek(to: $0) }
                    ),
                    in: 0...max(model?.duration ?? 0.1, 0.1),
                    onEditingChanged: { editing in model?.isScrubbing = editing }
                )
                .tint(Theme.accent)
                HStack {
                    Text((model?.currentTime ?? 0).mmss)
                    Spacer()
                    Text((model?.duration ?? 0).mmss)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .card()
        .padding(.horizontal)
        .onAppear {
            if model == nil { model = AudioPlayerModel(url: url) }
        }
        .onDisappear {
            model?.stop()
        }
        .accessibilityElement(children: .combine)
    }
}
