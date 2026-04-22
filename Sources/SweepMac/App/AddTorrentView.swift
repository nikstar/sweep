import SwiftUI
import SweepCore

struct AddTorrentView: View {
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Torrent")
                .font(.headline)

            Form {
                Section {
                    sourceInput

                    LabeledContent("Save To") {
                        HStack(spacing: 8) {
                            Text(abbreviatedPath(downloadDirectory))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button("Choose...") {
                                chooseDirectory()
                            }
                        }
                    }

                    Toggle("Start Paused", isOn: $startPaused)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(isAdding ? "Adding..." : "Add") {
                    add()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    @ViewBuilder
    private var sourceInput: some View {
        switch source {
        case .magnet:
            LabeledContent("Magnet Link") {
                TextField("magnet:?xt=urn:btih:...", text: $magnet, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)
            }

        case .torrentFile(let file):
            LabeledContent("Torrent File") {
                HStack(spacing: 8) {
                    Label(file.fileName ?? "Torrent File", systemImage: "doc")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button("Change...") {
                        chooseFile()
                    }
                }
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

    private func chooseFile() {
        guard let file = chooseTorrentFile() else { return }
        source = .torrentFile(file)
    }

    private func chooseDirectory() {
        guard let directory = chooseDownloadDirectory(initialPath: downloadDirectory) else { return }
        downloadDirectory = directory
    }

    private func add() {
        guard let source = resolvedSource else { return }
        let directory = downloadDirectory
        let startPaused = startPaused
        isAdding = true

        Task {
            _ = await store.addTorrent(
                source,
                downloadDirectory: directory,
                startPaused: startPaused
            )
            dismiss()
        }
    }
}
