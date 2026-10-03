import SwiftUI
import SweepCore
import SweepUI

struct IOSSessionStatusBar: View {
    @Environment(TorrentStore.self) private var store
    @State private var showingHealth = false

    var body: some View {
        HStack(spacing: 14) {
            Label(ByteFormatter.rate(store.sessionStats.downloadBps), systemImage: "arrow.down")
            Label(ByteFormatter.rate(store.sessionStats.uploadBps), systemImage: "arrow.up")
            Label("\(store.sessionStats.livePeers)", systemImage: "person.2")

            Spacer(minLength: 8)

            Button {
                showingHealth = true
            } label: {
                Label("Health", systemImage: store.healthError == nil ? "info.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(store.healthError == nil ? Color.secondary : .red)
            }
            .accessibilityLabel(store.healthError == nil ? "Session Health" : "Session Health, error")
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(.bar)
        .sheet(isPresented: $showingHealth) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SessionHealthView(showsTitle: false)
                        IOSExecutionHealthView()
                    }
                    .padding()
                }
                .navigationTitle("Session Health")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingHealth = false }
                    }
                }
            }
        }
    }
}
