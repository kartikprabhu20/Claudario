import Foundation

enum HookEvent: String {
    case sessionStart      = "SessionStart"
    case userPromptSubmit  = "UserPromptSubmit"
    case preToolUse        = "PreToolUse"
    case postToolUse       = "PostToolUse"
    case notification      = "Notification"
    case stop              = "Stop"
    case subagentStop      = "SubagentStop"
    case sessionEnd        = "SessionEnd"
}

final class EventRouter {
    private let onWalk: () -> Void
    private let onIdle: () -> Void
    private let onCelebrate: () -> Void
    private let onNotify: () -> Void

    private struct SessionState {
        var isWalking: Bool
        var lastSeen: Date
    }
    private var sessions: [String: SessionState] = [:]
    private let lock = NSLock()
    private let staleAfter: TimeInterval = 5 * 60

    init(onWalk: @escaping () -> Void,
         onIdle: @escaping () -> Void,
         onCelebrate: @escaping () -> Void,
         onNotify: @escaping () -> Void) {
        self.onWalk = onWalk
        self.onIdle = onIdle
        self.onCelebrate = onCelebrate
        self.onNotify = onNotify
    }

    func handle(_ json: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return }
        let eventName = (obj["hook_event_name"] as? String) ?? ""
        let sessionId = (obj["session_id"] as? String) ?? "default"
        if let event = HookEvent(rawValue: eventName) {
            process(event: event, sessionId: sessionId)
        } else if eventName == "PermissionRequest" {
            DispatchQueue.main.async { self.onNotify() }
        }
    }

    private func process(event: HookEvent, sessionId: String) {
        lock.lock()
        evictStaleLocked()
        defer { lock.unlock() }

        let now = Date()
        switch event {
        case .sessionStart:
            sessions[sessionId] = SessionState(isWalking: false, lastSeen: now)

        case .userPromptSubmit, .preToolUse:
            let wasWalking = anyWalkingLocked
            sessions[sessionId] = SessionState(isWalking: true, lastSeen: now)
            if !wasWalking {
                DispatchQueue.main.async { self.onWalk() }
            }

        case .postToolUse:
            sessions[sessionId]?.lastSeen = now

        case .notification:
            sessions[sessionId]?.lastSeen = now
            DispatchQueue.main.async { self.onNotify() }

        case .stop, .subagentStop:
            sessions[sessionId]?.isWalking = false
            sessions[sessionId]?.lastSeen = now
            if !anyWalkingLocked {
                DispatchQueue.main.async {
                    self.onIdle()
                    self.onCelebrate()
                }
            }

        case .sessionEnd:
            sessions[sessionId] = nil
            if !anyWalkingLocked {
                DispatchQueue.main.async { self.onIdle() }
            }
        }
    }

    private var anyWalkingLocked: Bool {
        sessions.values.contains { $0.isWalking }
    }

    private func evictStaleLocked() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        sessions = sessions.filter { $0.value.lastSeen >= cutoff }
    }

    func reset() {
        lock.lock()
        sessions.removeAll()
        lock.unlock()
        DispatchQueue.main.async { self.onIdle() }
    }
}
