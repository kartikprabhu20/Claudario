import Foundation

enum TranscriptReader {
    static let contextWindow: Int = 200_000

    /// Scans the JSONL from the end and returns the most recent assistant
    /// message's `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.
    /// That's the size of the prompt Claude was holding on its last turn —
    /// the same figure shown by Claude Code's /context command.
    /// Returns 0 when the file is missing, unreadable, or has no assistant
    /// turn yet (e.g. the user has only typed their first prompt).
    static func contextTokens(path: String) -> Int {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return 0 }
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let msg = obj["message"] as? [String: Any],
                  (msg["role"] as? String) == "assistant",
                  let usage = msg["usage"] as? [String: Any] else { continue }
            let input = (usage["input_tokens"] as? Int) ?? 0
            let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
            return input + cacheCreate + cacheRead
        }
        return 0
    }
}
