import Foundation

struct SessionUsage: Equatable {
    var sessionPercent: Double
    var contextPercent: Double
    static let zero = SessionUsage(sessionPercent: 0, contextPercent: 0)
}
