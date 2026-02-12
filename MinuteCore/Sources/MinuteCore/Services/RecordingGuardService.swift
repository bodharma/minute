import OSLog
import UserNotifications

@MainActor
public final class RecordingGuardService {
    private let notificationCenter: UNUserNotificationCenter
    private let logger = Logger(subsystem: "roblibob.Minute", category: "recording-guard")
    private var guardTask: Task<Void, Never>?
    private var autoStopTask: Task<Void, Never>?

    private var recordingStartedAt: Date?
    private var autoStopEnabled = false
    private var maxDurationMinutes = 120
    private var remindersEnabled = false
    private var lastReminderMinute = 0
    private var limitReached = false

    private let autoStopGraceSeconds: UInt64 = 5 * 60

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
        limitReached = false

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
        autoStopTask?.cancel()
        autoStopTask = nil
        recordingStartedAt = nil
        lastReminderMinute = 0
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [RecordingGuardNotification.notificationIdentifier]
        )
        notificationCenter.removeDeliveredNotifications(
            withIdentifiers: [RecordingGuardNotification.notificationIdentifier]
        )
    }

    public func continueRecording() {
        autoStopTask?.cancel()
        autoStopTask = nil
        limitReached = true
        autoStopEnabled = false
        logger.info("User chose to continue recording past the limit")
    }

    private func tick() async {
        guard let startedAt = recordingStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let elapsedMinutes = Int(elapsed / 60)

        if autoStopEnabled, !limitReached, elapsedMinutes >= maxDurationMinutes {
            limitReached = true
            lastReminderMinute = elapsedMinutes
            logger.info("Recording reached \(self.maxDurationMinutes)-minute limit, starting grace period")
            await scheduleLimitReachedNotification()
            startAutoStopGracePeriod()
            return
        }

        if remindersEnabled, elapsedMinutes > 0, elapsedMinutes % 30 == 0, elapsedMinutes != lastReminderMinute {
            lastReminderMinute = elapsedMinutes
            let remaining = autoStopEnabled && !limitReached ? maxDurationMinutes - elapsedMinutes : nil
            await scheduleReminderNotification(elapsedMinutes: elapsedMinutes, remainingMinutes: remaining)
        }
    }

    private func startAutoStopGracePeriod() {
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.autoStopGraceSeconds ?? 300 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.logger.info("Grace period expired, auto-stopping recording")
            self?.onAutoStop?()
        }
    }

    private func scheduleReminderNotification(elapsedMinutes: Int, remainingMinutes: Int?) async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Recording in progress"
        if let remaining = remainingMinutes, remaining > 0 {
            content.body = "Your meeting has been recording for \(elapsedMinutes) minutes. Time limit in \(remaining) minutes."
        } else {
            content.body = "Your meeting has been recording for \(elapsedMinutes) minutes."
        }
        content.categoryIdentifier = RecordingGuardNotification.categoryIdentifier
        content.threadIdentifier = RecordingGuardNotification.categoryIdentifier
        content.sound = .default

        await deliver(content)
    }

    private func scheduleLimitReachedNotification() async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Recording time limit reached"
        content.body = "Your meeting hit the \(maxDurationMinutes)-minute limit. It will auto-stop in 5 minutes unless you continue."
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
