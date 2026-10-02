import SwiftUI
import AVFoundation
import Observation

/// Plays a reflection's recording.
///
/// The object lives in the private `reflection-media` bucket, so the URL is
/// signed on demand — the storage policy applies the same unlock rule as the
/// reflection row, which means a member who hasn't posted simply can't get one.
@MainActor
@Observable
final class RecordingPlayer {
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var failed = false

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    /// Plays a file already on disk — the just-recorded m4a on the review
    /// screen, before it has been uploaded and has any remote path.
    func toggle(fileURL: URL) async {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        if player == nil { attach(url: fileURL) }
        startPlayback()
    }

    func toggle(path: String, api: DwellAPI) async {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }

        if player == nil {
            isLoading = true
            failed = false
            defer { isLoading = false }
            guard let url = try? await api.mediaURL(path: path) else {
                failed = true
                return
            }
            attach(url: url)
        }
        startPlayback()
    }

    private func attach(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.player?.seek(to: .zero)
            }
        }
    }

    private func startPlayback() {
        // Recording leaves the session in `.record`, which is silent on
        // playback — and it has to be audible with the ringer switch off.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        isPlaying = true
    }

    func stop() {
        player?.pause()
        isPlaying = false
    }

    /// Called from `onDisappear` rather than `deinit` — `deinit` is
    /// nonisolated and can't touch main-actor state.
    func tearDown() {
        stop()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
    }
}
