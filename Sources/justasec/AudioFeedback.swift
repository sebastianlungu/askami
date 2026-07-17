import AudioToolbox

public enum ChimeType: Sendable {
    case trigger
    case busy
}

public struct AudioFeedback: Sendable {
    private static let triggerSound: SystemSoundID = {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")
        var soundID = SystemSoundID(0)
        AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        return soundID
    }()

    private static let busySound: SystemSoundID = {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Basso.aiff")
        var soundID = SystemSoundID(0)
        AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        return soundID
    }()

    public static func play(_ chime: ChimeType) {
        let soundID: SystemSoundID
        switch chime {
        case .trigger: soundID = triggerSound
        case .busy: soundID = busySound
        }
        if soundID != 0 {
            AudioServicesPlaySystemSound(soundID)
        }
    }

    public static func dispose() {
        if triggerSound != 0 {
            AudioServicesDisposeSystemSoundID(triggerSound)
        }
        if busySound != 0 {
            AudioServicesDisposeSystemSoundID(busySound)
        }
    }
}
