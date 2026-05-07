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
    case preCompact        = "PreCompact"
}

final class EventRouter {
    private let onWalk: () -> Void
    private let onIdle: () -> Void
    private let onCelebrate: () -> Void
    private let onNotify: () -> Void
    private let onActivity: (MascotActivity) -> Void

    private struct SessionState {
        var isWalking: Bool
        var activity: MascotActivity
        var lastSeen: Date
    }
    private var sessions: [String: SessionState] = [:]
    private var lastActiveSessionId: String?
    private var lastEmittedActivity: MascotActivity = .idle
    private let lock = NSLock()
    private let staleAfter: TimeInterval = 5 * 60

    init(onWalk: @escaping () -> Void,
         onIdle: @escaping () -> Void,
         onCelebrate: @escaping () -> Void,
         onNotify: @escaping () -> Void,
         onActivity: @escaping (MascotActivity) -> Void) {
        self.onWalk = onWalk
        self.onIdle = onIdle
        self.onCelebrate = onCelebrate
        self.onNotify = onNotify
        self.onActivity = onActivity
    }

    func handle(_ json: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return }
        let eventName = (obj["hook_event_name"] as? String) ?? ""
        let sessionId = (obj["session_id"] as? String) ?? "default"
        let toolName = obj["tool_name"] as? String

        if let event = HookEvent(rawValue: eventName) {
            process(event: event, sessionId: sessionId, toolName: toolName)
        } else if eventName == "PermissionRequest" {
            DispatchQueue.main.async { self.onNotify() }
        }
    }

    private func process(event: HookEvent, sessionId: String, toolName: String?) {
        lock.lock()
        evictStaleLocked()
        defer { lock.unlock() }

        let now = Date()
        var sess = sessions[sessionId] ?? SessionState(isWalking: false, activity: .idle, lastSeen: now)
        sess.lastSeen = now
        lastActiveSessionId = sessionId

        switch event {
        case .sessionStart:
            sess.isWalking = false
            sess.activity = .idle

        case .userPromptSubmit:
            let wasWalking = anyWalkingLocked
            sess.isWalking = true
            sess.activity = .thinking
            sessions[sessionId] = sess
            if !wasWalking {
                DispatchQueue.main.async { self.onWalk() }
            }
            emitActivityLocked()
            return

        case .preToolUse:
            let wasWalking = anyWalkingLocked
            sess.isWalking = true
            sess.activity = MascotActivity.category(forTool: toolName ?? "")
            sessions[sessionId] = sess
            if !wasWalking {
                DispatchQueue.main.async { self.onWalk() }
            }
            emitActivityLocked()
            return

        case .postToolUse:
            sess.activity = .thinking
            sessions[sessionId] = sess
            emitActivityLocked()
            return

        case .preCompact:
            sess.isWalking = true
            sess.activity = .compacting
            sessions[sessionId] = sess
            DispatchQueue.main.async { self.onWalk() }
            emitActivityLocked()
            return

        case .notification:
            DispatchQueue.main.async { self.onNotify() }

        case .stop, .subagentStop:
            sess.isWalking = false
            sess.activity = .idle
            sessions[sessionId] = sess
            if !anyWalkingLocked {
                DispatchQueue.main.async {
                    self.onIdle()
                    self.onCelebrate()
                }
                emitIdleActivityLocked()
            } else {
                emitActivityLocked()
            }
            return

        case .sessionEnd:
            sessions[sessionId] = nil
            if !anyWalkingLocked {
                DispatchQueue.main.async { self.onIdle() }
                emitIdleActivityLocked()
            } else {
                emitActivityLocked()
            }
            return
        }

        sessions[sessionId] = sess
    }

    private func emitActivityLocked() {
        let activity: MascotActivity
        if let id = lastActiveSessionId, let s = sessions[id], s.isWalking {
            activity = s.activity
        } else if let walking = sessions.values.first(where: { $0.isWalking }) {
            activity = walking.activity
        } else {
            activity = .idle
        }
        guard activity != lastEmittedActivity else { return }
        lastEmittedActivity = activity
        DispatchQueue.main.async { self.onActivity(activity) }
    }

    private func emitIdleActivityLocked() {
        guard lastEmittedActivity != .idle else { return }
        lastEmittedActivity = .idle
        DispatchQueue.main.async { self.onActivity(.idle) }
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
        lastActiveSessionId = nil
        let needsIdleEmit = lastEmittedActivity != .idle
        lastEmittedActivity = .idle
        lock.unlock()
        DispatchQueue.main.async {
            self.onIdle()
            if needsIdleEmit { self.onActivity(.idle) }
        }
    }
}
