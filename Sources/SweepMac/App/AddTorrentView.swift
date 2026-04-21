import SwiftUI
import SweepCore

struct AddTorrentView: View {
    @EnvironmentObject private var store: TorrentStore
    @Environment(\.dismiss) private var dismiss
    @State private var magnet = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Magnet Link")
                .font(.headline)

            TextField("magnet:?xt=urn:btih:...", text: $magnet, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4, reservesSpace: true)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add") {
                    store.addMagnet(magnet)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!magnet.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("magnet:"))
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
