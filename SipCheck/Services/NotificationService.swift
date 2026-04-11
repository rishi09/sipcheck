import Foundation
import UserNotifications

/// Manages local follow-up notifications for scanned beers
class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    /// The scan UUID that was tapped via a notification; set by the UNUserNotificationCenterDelegate
    @Published var pendingFollowUpScanID: UUID?

    /// Action response from a notification button tap
    @Published var pendingFollowUpAction: FollowUpAction?

    struct FollowUpAction {
        let scanID: UUID
        let response: Response

        enum Response {
            case lovedIt, meh, skippedIt, tapped
        }
    }

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self

        let lovedIt = UNNotificationAction(identifier: "LOVED_IT", title: "Loved it", options: .foreground)
        let meh = UNNotificationAction(identifier: "MEH", title: "Meh", options: .foreground)
        let skipped = UNNotificationAction(identifier: "SKIPPED_IT", title: "Skipped it", options: [])
        let category = UNNotificationCategory(
            identifier: "BEER_FOLLOWUP",
            actions: [lovedIt, meh, skipped],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
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

    /// Schedule a follow-up notification after a scan.
    /// Skips SKIP IT verdicts. Uses 48h for TRY IT, 72h for YOUR CALL.
    func scheduleFollowUp(for scan: Scan) {
        guard scan.verdict != .skipIt else { return }

        requestAuthorization()

        let delay: TimeInterval = scan.verdict == .tryIt ? 48 * 3600 : 72 * 3600

        let content = UNMutableNotificationContent()
        if scan.verdict == .tryIt {
            content.title = "Did you try \(scan.beerName)? 🍺"
            content.body = "We said go for it. Tap to log how it actually went."
        } else {
            content.title = "Ever get around to \(scan.beerName)?"
            content.body = "You were on the fence — curious what you thought."
        }
        content.sound = .default
        content.userInfo = ["scanID": scan.id.uuidString]
        content.categoryIdentifier = "BEER_FOLLOWUP"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: delay,
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

    /// Handle the user tapping a notification or selecting an action
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let scanIDString = userInfo["scanID"] as? String,
           let scanID = UUID(uuidString: scanIDString) {

            let actionID = response.actionIdentifier
            let followUpResponse: FollowUpAction.Response
            switch actionID {
            case "LOVED_IT":
                followUpResponse = .lovedIt
            case "MEH":
                followUpResponse = .meh
            case "SKIPPED_IT":
                followUpResponse = .skippedIt
            default:
                // UNNotificationDefaultActionIdentifier — plain tap
                followUpResponse = .tapped
            }

            DispatchQueue.main.async {
                self.pendingFollowUpScanID = scanID
                self.pendingFollowUpAction = FollowUpAction(scanID: scanID, response: followUpResponse)
            }
        }
        completionHandler()
    }
}
