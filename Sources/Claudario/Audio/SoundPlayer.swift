import AppKit

enum AppSound {
    case coin    // played when Claude finishes a turn
    case notify  // played for permission/question notifications
}

final class SoundPlayer {
    func play(_ sound: AppSound) {
        let name: String
        switch sound {
        case .coin:   name = "Glass"
        case .notify: name = "Funk"
        }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
