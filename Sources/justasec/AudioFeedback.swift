@preconcurrency import AVFoundation
import Foundation

@MainActor
public final class AudioFeedback: NSObject {
    private var player: AVAudioPlayer?
    private var playerID: ObjectIdentifier?
    private var continuation: CheckedContinuation<Void, Never>?

    public static let shared = AudioFeedback()
    private override init() { super.init() }

    public func playReadyChime() async {
        stop()

        guard let url = Bundle.main.url(forResource: "ready-chime", withExtension: "mp3") else {
            fputs("justasec: ready-chime 'ready-chime.mp3' not found in bundle\n", stderr)
            return
        }
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: url)
        } catch {
            fputs("justasec: ready-chime player init failed — \(error)\n", stderr)
            return
        }
        player.volume = 0.3
        player.delegate = self
        self.player = player
        player.prepareToPlay()
        guard player.play() else {
            fputs("justasec: ready-chime playback failed to start\n", stderr)
            finishPlayback()
            return
        }
        let pid = ObjectIdentifier(player)
        playerID = pid

        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if Task.isCancelled {
                    self.finishPlayback()
                    cont.resume()
                } else if self.playerID != pid {
                    cont.resume()
                } else {
                    self.continuation = cont
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.stop()
            }
        }
    }

    private func finishPlayback() {
        player = nil
        playerID = nil
        if let cont = continuation {
            continuation = nil
            cont.resume()
        }
    }

    public func stop() {
        player?.stop()
        finishPlayback()
    }
}

extension AudioFeedback: AVAudioPlayerDelegate {
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let pid = ObjectIdentifier(player)
        Task { @MainActor in
            guard self.playerID == pid else { return }
            self.finishPlayback()
            if !flag {
                fputs("justasec: ready-chime playback finished with error\n", stderr)
            }
        }
    }
}
