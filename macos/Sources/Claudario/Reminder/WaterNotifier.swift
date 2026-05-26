import Foundation
import UserNotifications

/// Posts macOS notification banners for the water reminder and routes
/// the "Mark as drunk" action back into the reminder pipeline.
///
/// Notifications are best-effort: if the user has denied notification
/// permission, `fire(...)` silently no-ops and the mascot-only visual
/// reminder is enough on its own.
final class WaterNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let categoryId = "claudario.water.reminder"
    private static let actionAcknowledge = "claudario.water.acknowledge"

    /// Called on the main queue when the user taps "Mark as drunk" on a
    /// delivered notification (or just clicks the banner body).
    var onAcknowledged: (() -> Void)?

    private var authorized = false
    private var didRegisterCategory = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategory()
    }

    /// Request authorization. Safe to call multiple times — the system
    /// caches the answer after the first prompt.
    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                self?.authorized = granted
            }
    }

    func fire(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        // Check current authorization on every fire — the user may have
        // toggled it in System Settings since launch.
        center.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = Self.categoryId
            let req = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil)
            center.add(req) { _ in }
            self?.authorized = true
        }
    }

    private func registerCategory() {
        guard !didRegisterCategory else { return }
        didRegisterCategory = true
        let action = UNNotificationAction(
            identifier: Self.actionAcknowledge,
            title: "Mark as drunk",
            options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [action],
            intentIdentifiers: [],
            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show the banner even if the app is frontmost — the mascot is in
        // the Dock strip, not really "frontmost" in the user's mental model.
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        // Treat both the action button AND a default tap on the banner
        // body as "I drank". Easier-to-dismiss is better than two-step.
        let id = response.actionIdentifier
        if id == Self.actionAcknowledge
            || id == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async { [weak self] in
                self?.onAcknowledged?()
            }
        }
    }
}
