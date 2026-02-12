import OSLog
import UserNotifications

@MainActor
public final class RecordingGuardService {
    private let notificationCenter: UNUserNotificationCenter
    private let logger = Logger(subsystem: "roblibob.Minute", category: "recording-guard")
    private var guardTask: Task<Void, Never>?

    private var recordingStartedAt: Date?
    private var autoStopEnabled = false
    private var maxDurationMinutes = 120
    private var remindersEnabled = false
    private var lastReminderMinute = 0

    public var onAutoStop: (() -> Void)?

    public init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    public func startGuard(recordingStartedAt: Date, configuration: AppConfiguration) {
        stopGuard()

        self.recordingStartedAt = recordingStartedAt
        autoStopEnabled = configuration.autoStopRecordingEnabled
        maxDurationMinutes = configuration.maxRecordingDurationMinutes
        remindersEnabled = configuration.recordingRemindersEnabled
        lastReminderMinute = 0

        guard autoStopEnabled || remindersEnabled else { return }

        guardTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.tick()
            }
        }

        Task { _ = await ensureAuthorized() }
    }

    public func stopGuard() {
        guardTask?.cancel()
        guardTask = nil
        recordingStartedAt = nil
        lastReminderMinute = 0
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [RecordingGuardNotification.notificationIdentifier]
        )
        notificationCenter.removeDeliveredNotifications(
            withIdentifiers: [RecordingGuardNotification.notificationIdentifier]
        )
    }

    private func tick() async {
        guard let startedAt = recordingStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let elapsedMinutes = Int(elapsed / 60)

        if autoStopEnabled, elapsedMinutes >= maxDurationMinutes {
            logger.info("Auto-stop triggered after \(elapsedMinutes) minutes")
            await scheduleAutoStopNotification()
            onAutoStop?()
            stopGuard()
            return
        }

        if remindersEnabled, elapsedMinutes > 0, elapsedMinutes % 30 == 0, elapsedMinutes != lastReminderMinute {
            lastReminderMinute = elapsedMinutes
            let remaining = autoStopEnabled ? maxDurationMinutes - elapsedMinutes : nil
            await scheduleReminderNotification(elapsedMinutes: elapsedMinutes, remainingMinutes: remaining)
        }
    }

    private func scheduleReminderNotification(elapsedMinutes: Int, remainingMinutes: Int?) async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Recording in progress"
        if let remaining = remainingMinutes, remaining > 0 {
            content.body = "Your meeting has been recording for \(elapsedMinutes) minutes. Auto-stop in \(remaining) minutes."
        } else {
            content.body = "Your meeting has been recording for \(elapsedMinutes) minutes."
        }
        content.categoryIdentifier = RecordingGuardNotification.categoryIdentifier
        content.threadIdentifier = RecordingGuardNotification.categoryIdentifier
        content.sound = .default

        await deliver(content)
    }

    private func scheduleAutoStopNotification() async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Recording auto-stopped"
        content.body = "Your meeting reached the \(maxDurationMinutes)-minute limit and is now being processed."
        content.categoryIdentifier = RecordingGuardNotification.categoryIdentifier
        content.threadIdentifier = RecordingGuardNotification.categoryIdentifier
        content.sound = .default

        await deliver(content)
    }

    private func deliver(_ content: UNMutableNotificationContent) async {
        let request = UNNotificationRequest(
            identifier: RecordingGuardNotification.notificationIdentifier,
            content: content,
            trigger: nil
        )

        notificationCenter.removeDeliveredNotifications(
            withIdentifiers: [RecordingGuardNotification.notificationIdentifier]
        )
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [RecordingGuardNotification.notificationIdentifier]
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            logger.error("Failed to schedule recording guard notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensureAuthorized() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            } catch {
                logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
