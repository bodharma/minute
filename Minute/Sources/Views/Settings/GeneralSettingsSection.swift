import MinuteCore
import SwiftUI

struct GeneralSettingsSection: View {
    @AppStorage(AppDefaultsKey.saveAudio) private var saveAudio: Bool = AppConfiguration.Defaults.defaultSaveAudio
    @AppStorage(AppDefaultsKey.saveTranscript) private var saveTranscript: Bool = AppConfiguration.Defaults.defaultSaveTranscript
    @AppStorage(AppDefaultsKey.normalizeAnalysisAudio)
    private var normalizeAnalysisAudio: Bool = AppConfiguration.Defaults.defaultNormalizeAnalysisAudio
    @AppStorage(AppDefaultsKey.micActivityNotificationsEnabled)
    private var micActivityNotificationsEnabled: Bool = AppConfiguration.Defaults.defaultMicActivityNotificationsEnabled
    @AppStorage(AppDefaultsKey.autoStopRecordingEnabled)
    private var autoStopRecordingEnabled: Bool = AppConfiguration.Defaults.defaultAutoStopRecordingEnabled
    @AppStorage(AppDefaultsKey.maxRecordingDurationMinutes)
    private var maxRecordingDurationMinutes: Int = AppConfiguration.Defaults.defaultMaxRecordingDurationMinutes
    @AppStorage(AppDefaultsKey.recordingRemindersEnabled)
    private var recordingRemindersEnabled: Bool = AppConfiguration.Defaults.defaultRecordingRemindersEnabled

    @AppStorage(AppDefaultsKey.outputLanguage)
    private var outputLanguageRaw: String = AppConfiguration.Defaults.defaultOutputLanguage.rawValue

    private var outputLanguageBinding: Binding<OutputLanguage> {
        Binding(
            get: { OutputLanguage.resolved(from: outputLanguageRaw) },
            set: { outputLanguageRaw = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            Section("Options") {
                SettingsToggleRow(
                    "Save audio",
                    detail: "When off, audio is not saved to the vault or linked in the note.",
                    isOn: $saveAudio
                )

                SettingsToggleRow(
                    "Save transcript",
                    detail: "When off, the transcript file and link are omitted from the note.",
                    isOn: $saveTranscript
                )

                SettingsToggleRow(
                    "Normalize audio for analysis",
                    detail: "Improves quiet/far speakers in transcription and diarization. Does not change the saved vault audio.",
                    isOn: $normalizeAnalysisAudio
                )

                SettingsToggleRow(
                    "Mic activity reminders",
                    detail: "Show a notification when the microphone becomes active.",
                    isOn: $micActivityNotificationsEnabled
                )
            }

            Section("Recording Safety") {
                SettingsToggleRow(
                    "Auto-stop recording",
                    detail: "Automatically stop recording after the time limit to prevent runaway sessions.",
                    isOn: $autoStopRecordingEnabled
                )

                if autoStopRecordingEnabled {
                    Picker("Maximum duration", selection: $maxRecordingDurationMinutes) {
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("3 hours").tag(180)
                        Text("4 hours").tag(240)
                    }
                    .pickerStyle(.menu)
                }

                SettingsToggleRow(
                    "Recording reminders",
                    detail: "Show a notification every 30 minutes while recording.",
                    isOn: $recordingRemindersEnabled
                )
            }

            Section("Language") {
                Picker("Output language", selection: outputLanguageBinding) {
                    ForEach(OutputLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)

                Text("Used when session language processing is set to Auto -> Picked language.")
                    .minuteCaption()
            }

            KnownSpeakersSettingsSection(mode: .toggleOnly)
        }
    }
}

#Preview {
    Form {
        GeneralSettingsSection()
    }
    .frame(width: 420)
}
