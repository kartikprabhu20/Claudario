import Foundation

/// Implemented by the Touch Bar controller. Lets `MascotScene` forward
/// palette/variant/activity changes so the strip mascot tracks the
/// screen mascot.
protocol TouchBarMascotMirror: AnyObject {
    func touchBarApplyActivity(_ activity: MascotActivity)
    func touchBarApplyColor(index: Int)
    func touchBarApplyVariant(index: Int)
}
