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
    private let onUsageUpdate: (SessionUsage) -> Void

    private struct SessionState {
        var isWalking: Bool
        var activity: MascotActivity
        var lastSeen: Date
        var startedAt: Date
        var transcriptPath: String?
        var lastContextTokens: Int
        var lastTranscriptRead: Date
    }
    private var sessions: [String: SessionState] = [:]
    private var lastActiveSessionId: String?
    private var lastEmittedActivity: MascotActivity = .idle
    private let lock = NSLock()
    private let staleAfter: TimeInterval = 5 * 60
    private let sessionWindow: TimeInterval = 5 * 3600
    private let transcriptReadThrottle: TimeInterval = 0.5

    init(onWalk: @escaping () -> Void,
         onIdle: @escaping () -> Void,
         onCelebrate: @escaping () -> Void,
         onNotify: @escaping () -> Void,
         onActivity: @escaping (MascotActivity) -> Void,
         onUsageUpdate: @escaping (SessionUsage) -> Void) {
        self.onWalk = onWalk
        self.onIdle = onIdle
        self.onCelebrate = onCelebrate
        self.onNotify = onNotify
        self.onActivity = onActivity
        self.onUsageUpdate = onUsageUpdate
    }

    func handle(_ json: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return }
        let eventName = (obj["hook_event_name"] as? String) ?? ""
        let sessionId = (obj["session_id"] as? String) ?? "default"
        let toolName = obj["tool_name"] as? String
        let transcriptPath = obj["transcript_path"] as? String

        if let event = HookEvent(rawValue: eventName) {
            process(event: event, sessionId: sessionId, toolName: toolName, transcriptPath: transcriptPath)
        } else if eventName == "PermissionRequest" {
            DispatchQueue.main.async { self.onNotify() }
        }
    }

    private func process(event: HookEvent, sessionId: String, toolName: String?, transcriptPath: String?) {
        lock.lock()
        evictStaleLocked()
        // Usage emit runs while the lock is still held — defers fire in
        // reverse order, so this executes before the unlock below.
        defer { lock.unlock() }
        defer { emitUsageLocked() }

        let now = Date()
        var sess = sessions[sessionId] ?? SessionState(
            isWalking: false,
            activity: .idle,
            lastSeen: now,
            startedAt: now,
            transcriptPath: nil,
            lastContextTokens: 0,
            lastTranscriptRead: .distantPast
        )
        sess.lastSeen = now
        if let path = transcriptPath, !path.isEmpty { sess.transcriptPath = path }
        lastActiveSessionId = sessionId
        maybeRefreshTranscriptLocked(&sess, event: event)

        switch event {
        case .sessionStart:
            sess.isWalking = false
            sess.activity = .idle
            sess.startedAt = now
            sess.lastContextTokens = 0
            sess.lastTranscriptRead = .distantPast

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
            if lastActiveSessionId == sessionId { lastActiveSessionId = nil }
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

    private func emitUsageLocked() {
        let usage: SessionUsage
        if let id = lastActiveSessionId, let sess = sessions[id] {
            let elapsed = Date().timeIntervalSince(sess.startedAt)
            let session = min(1.0, max(0.0, elapsed / sessionWindow))
            let context = min(1.0, Double(sess.lastContextTokens) / Double(TranscriptReader.contextWindow))
            usage = SessionUsage(sessionPercent: session, contextPercent: context)
        } else {
            usage = .zero
        }
        DispatchQueue.main.async { self.onUsageUpdate(usage) }
    }

    /// Reads the transcript JSONL only on events that follow an assistant
    /// turn, and only when enough time has elapsed since the last read so
    /// back-to-back PreToolUse/PostToolUse pairs don't thrash the disk.
    private func maybeRefreshTranscriptLocked(_ sess: inout SessionState, event: HookEvent) {
        let shouldRead: Bool
        switch event {
        case .preToolUse, .postToolUse, .stop, .subagentStop, .preCompact:
            shouldRead = true
        default:
            shouldRead = false
        }
        guard shouldRead, let path = sess.transcriptPath else { return }
        let now = Date()
        guard now.timeIntervalSince(sess.lastTranscriptRead) > transcriptReadThrottle else { return }
        sess.lastContextTokens = TranscriptReader.contextTokens(path: path)
        sess.lastTranscriptRead = now
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
            self.onUsageUpdate(.zero)
        }
    }
}
