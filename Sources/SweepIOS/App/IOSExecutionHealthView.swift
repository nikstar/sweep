import SwiftUI

struct IOSExecutionHealthView: View {
    @Environment(IOSBackgroundDownloadService.self) private var background
    @Environment(IOSLiveActivityService.self) private var activity

    var body: some View {
        @Bindable var background = background
        @Bindable var activity = activity
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Background Execution").font(.headline)
            Toggle("Continue Downloads in Background", isOn: $background.isEnabled)
            LabeledContent("Mode", value: background.modeName)
            LabeledContent("State", value: background.status)
            if let checked = background.lastCheckAt {
                LabeledContent("Last check") { Text(checked, style: .relative) }
            }
            if let error = background.lastError {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
                Button("Retry Background Session") { background.retry() }
            }

            Divider()
            Text("Live Activity").font(.headline)
            Toggle("Show Download Activity", isOn: $activity.isEnabled)
            LabeledContent("State", value: activity.status)
            if let updated = activity.lastUpdateAt {
                LabeledContent("Last update") { Text(updated, style: .relative) }
            }
            if let error = activity.lastError {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            if activity.isEnabled {
                Button("Show Live Activity Again") { activity.showAgain() }
            }
        }
        .font(.callout)
    }
}
