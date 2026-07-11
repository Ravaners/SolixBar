import AppKit
import UserNotifications

/// Dünne Hülle um UNUserNotificationCenter für Update-Hinweise und Warnungen.
///
/// UserNotifications setzt ein (mindestens ad-hoc-)signiertes App-Bundle
/// voraus; aus einem nackten Executable (`swift run`, Tests) crasht schon der
/// Zugriff auf `UNUserNotificationCenter.current()`. Deshalb kapselt diese
/// Klasse jeden Zugriff hinter `isAvailable` und degradiert still — die
/// Menü-Einträge der Aufrufer bleiben der immer funktionierende Rückfallweg.
@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private let openURLActionIdentifier = "solixbar.open-url"
    private let categoryIdentifier = "solixbar.general"
    private var didConfigure = false

    var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Zeigt eine Benachrichtigung; gleiche `id` ersetzt eine noch sichtbare.
    /// `url` wird beim Klick auf Benachrichtigung oder Aktion geöffnet.
    func post(id: String, title: String, body: String, url: URL? = nil) {
        guard isAvailable else {
            AppLogger.info("Notification suppressed (unbundled): \(title)")
            return
        }
        configureIfNeeded()
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.error("Notification authorization failed: \(error.localizedDescription)")
                return
            }
            guard granted else {
                AppLogger.info("Notifications not granted; relying on menu fallback.")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = "solixbar.general"
            if let url {
                content.userInfo = ["url": url.absoluteString]
            }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                if let error {
                    AppLogger.error("Notification delivery failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Entfernt eine zugestellte Benachrichtigung wieder (z. B. wenn sich eine
    /// Warnbedingung von selbst erledigt hat).
    func withdraw(id: String) {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    private func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(
            identifier: openURLActionIdentifier,
            title: LocalizedText.text("Öffnen", "Open"),
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(identifier: categoryIdentifier, actions: [open], intentIdentifiers: [])
        ])
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Auch anzeigen, wenn die App "im Vordergrund" ist (Menüleisten-App).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }
}
