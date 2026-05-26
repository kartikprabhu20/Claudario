import Foundation

/// Probes for Touch Bar hardware. There is no public AppKit API that
/// reports "does this Mac have a Touch Bar," so we match the model
/// identifier (`hw.model` via sysctl) against the published list of
/// Touch Bar MacBook Pro models. The Touch Bar was retired with the
/// 2021 M1 Pro/Max 14"/16" MacBook Pros — `MacBookPro18,1`+ and the
/// `Mac14,*` / `Mac15,*` / later families don't have one.
///
/// False negatives (a new Touch Bar Mac we don't know about) just
/// silently disable the feature; the keypress no-ops harmlessly. False
/// positives would draw a Touch Bar item that never appears visibly.
/// Both modes are recoverable; the allow-list approach favors silent
/// degrade.
enum TouchBarSupport {
    static let isAvailable: Bool = {
        guard let model = hardwareModel() else { return false }
        return touchBarModels.contains(model)
    }()

    private static let touchBarModels: Set<String> = [
        "MacBookPro13,2", "MacBookPro13,3",
        "MacBookPro14,2", "MacBookPro14,3",
        "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4",
        "MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
        "MacBookPro17,1",
        // M2 13" (2022) — last MacBook Pro to ship with Touch Bar.
        "Mac14,7",
    ]

    private static func hardwareModel() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }
}
