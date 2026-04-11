import Foundation
import UserNotifications

/// Manages local follow-up notifications for scanned beers
class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    /// The scan UUID that was tapped via a notification; set by the UNUserNotificationCenterDelegate
    @Published var pendingFollowUpScanID: UUID?

    private let center = UNUserNotificationCenter.current()

    /// Follow-up delay: 3 hours after scan
    private let followUpDelay: TimeInterval = 3 * 60 * 60

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Authorization

    /// Request authorization to show notifications (call on first use)
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("NotificationService: authorization error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Schedule / Cancel

    /// Schedule a follow-up notification ~3 hours after a scan
    func scheduleFollowUp(for scan: Scan) {
        requestAuthorization()

        let content = UNMutableNotificationContent()
        content.title = "Did you try \(scan.beerName)?"
        content.body = "Tap to log your thoughts on this beer."
        content.sound = .default
        content.userInfo = ["scanID": scan.id.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: followUpDelay,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: scan.id.uuidString,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error = error {
                print("NotificationService: failed to schedule follow-up for \(scan.beerName): \(error.localizedDescription)")
            }
        }
    }

    /// Cancel any pending follow-up notification for a scan
    func cancelFollowUp(for scan: Scan) {
        center.removePendingNotificationRequests(withIdentifiers: [scan.id.uuidString])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Allow notifications to appear while the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handle the user tapping a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let scanIDString = userInfo["scanID"] as? String,
           let scanID = UUID(uuidString: scanIDString) {
            DispatchQueue.main.async {
                self.pendingFollowUpScanID = scanID
            }
        }
        completionHandler()
    }
}
