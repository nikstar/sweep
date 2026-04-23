import SwiftUI
import SweepCore

struct IOSAddTorrentSheet: View {
    @Environment(TorrentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var source: TorrentAddSource
    @State private var magnet: String
    @State private var downloadDirectory: String
    @State private var startPaused = false
    @State private var isAdding = false

    init(source: TorrentAddSource?, downloadDirectory: String) {
        let source = source ?? .magnet("")
        self._source = State(initialValue: source)
        self._magnet = State(initialValue: source.magnet ?? "")
        self._downloadDirectory = State(initialValue: downloadDirectory)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    sourceInput
                    LabeledContent("Save To") {
                        Text(IOSDisplayFormat.abbreviatedPath(downloadDirectory))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Toggle("Start Paused", isOn: $startPaused)
                }
            }
            .navigationTitle("Add Torrent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Adding..." : "Add") {
                        add()
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var sourceInput: some View {
        switch source {
        case .magnet:
            TextField("magnet:?xt=urn:btih:...", text: $magnet, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(4, reservesSpace: true)

        case .torrentFile(let file):
            LabeledContent("Torrent File") {
                Label(file.fileName ?? "Torrent File", systemImage: "doc")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var resolvedSource: TorrentAddSource? {
        switch source {
        case .magnet:
            let magnet = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard magnet.lowercased().hasPrefix("magnet:") else { return nil }
            return .magnet(magnet)

        case .torrentFile:
            return source
        }
    }

    private var canAdd: Bool {
        resolvedSource != nil
            && !downloadDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isAdding
    }

    private func add() {
        guard let source = resolvedSource else { return }
        let directory = downloadDirectory
        let startPaused = startPaused
        isAdding = true

        Task {
            let torrent = await store.addTorrent(
                source,
                downloadDirectory: directory,
                startPaused: startPaused
            )
            isAdding = false
            if torrent != nil {
                dismiss()
            }
        }
    }
}
