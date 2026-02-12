import Foundation

public enum RecordingGuardNotification {
    public static let categoryIdentifier = "minute.recording-guard"
    public static let stopActionIdentifier = "minute.recording-guard.stop"
    public static let notificationIdentifier = "minute.recording-guard.notification"
}

public extension Notification.Name {
    static let minuteRecordingGuardStopRecording = Notification.Name("minute.recording-guard.stop-recording")
}
