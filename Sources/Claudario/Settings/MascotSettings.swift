import Foundation

final class MascotSettings {
    static let sizeRange: [Int] = Array(stride(from: 24, through: 88, by: 8))
    static let defaultSize: Int = 44
    static let defaultColorIndex: Int = 0

    private let defaults: UserDefaults
    private enum Key {
        static let colorIndex = "claudario.colorIndex"
        static let size       = "claudario.size"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var colorIndex: Int {
        get {
            let raw = defaults.object(forKey: Key.colorIndex) as? Int ?? Self.defaultColorIndex
            return clampColorIndex(raw)
        }
        set { defaults.set(clampColorIndex(newValue), forKey: Key.colorIndex) }
    }

    var size: Int {
        get {
            let raw = defaults.object(forKey: Key.size) as? Int ?? Self.defaultSize
            return clampSize(raw)
        }
        set { defaults.set(clampSize(newValue), forKey: Key.size) }
    }

    /// Move to the next palette index (wraps). Persists, returns new index.
    @discardableResult
    func cycleColor() -> Int {
        let next = (colorIndex + 1) % MascotPalette.colors.count
        colorIndex = next
        return next
    }

    /// Step size by `delta` points (typically ±8). Clamped to sizeRange.
    /// Persists, returns new size.
    @discardableResult
    func nudgeSize(by delta: Int) -> Int {
        let next = clampSize(size + delta)
        size = next
        return next
    }

    private func clampColorIndex(_ i: Int) -> Int {
        let count = MascotPalette.colors.count
        if count == 0 { return 0 }
        return ((i % count) + count) % count
    }

    private func clampSize(_ s: Int) -> Int {
        max(Self.sizeRange.first!, min(Self.sizeRange.last!, s))
    }
}
