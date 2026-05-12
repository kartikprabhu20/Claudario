import AppKit

enum AppSound {
    case coin    // played when Claude finishes a turn
    case notify  // played for permission/question notifications
}

final class SoundPlayer: NSObject, NSSoundDelegate {
    private static let soundDir = "/System/Library/Sounds"

    // NSSound's play() is asynchronous, and the instance must be retained for
    // the full duration of playback — otherwise ARC drops it the moment this
    // method returns and the chime is cut off (or never starts). Hold each
    // in-flight sound here and release it from the delegate callback, which
    // also lets multiple instances play simultaneously when triggers fire
    // faster than a single chime's runtime (e.g. spamming the jump key).
    private var inFlight: [NSSound] = []

    func play(_ sound: AppSound) {
        let file: String
        switch sound {
        case .coin:   file = "Glass.aiff"
        case .notify: file = "Funk.aiff"
        }
        let path = "\(Self.soundDir)/\(file)"
        guard let s = NSSound(contentsOfFile: path, byReference: true) else { return }
        s.delegate = self
        inFlight.append(s)
        s.play()
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        inFlight.removeAll { $0 === sound }
    }
}
