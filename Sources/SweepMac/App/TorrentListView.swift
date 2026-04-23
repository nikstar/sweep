import AppKit
import SwiftUI
import SweepCore

struct TorrentListView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(TorrentInspectorPanelPresenter.self) private var inspectorPanelPresenter
    @Binding var confirmingRemoveData: Bool
    @SceneStorage("Sweep.TorrentList.progressColumnMode")
    private var progressColumnModeRaw = ProgressColumnMode.detailed.rawValue

    init(confirmingRemoveData: Binding<Bool> = .constant(false)) {
        self._confirmingRemoveData = confirmingRemoveData
    }

    var body: some View {
        let snapshot = TorrentListSnapshot(
            torrents: store.torrents,
            selection: store.selection,
            visibleColumns: store.visibleColumns
        )

        VStack(spacing: 0) {
            NativeTorrentTableView(
                store: store,
                snapshot: snapshot,
                progressColumnMode: progressColumnMode,
                setProgressColumnMode: { progressColumnModeRaw = $0.rawValue },
                requestRemoveDataConfirmation: { confirmingRemoveData = true },
                showInspector: { inspectorPanelPresenter.show(store: store) }
            )

            TransferStatusBar()
        }
    }

    private var progressColumnMode: ProgressColumnMode {
        ProgressColumnMode(rawValue: progressColumnModeRaw) ?? .detailed
    }
}

private struct TorrentListSnapshot: Equatable {
    let torrents: [Torrent]
    let selection: Torrent.ID?
    let visibleColumns: Set<TorrentListColumn>
}

private struct NativeTorrentTableView: NSViewControllerRepresentable {
    let store: TorrentStore
    let snapshot: TorrentListSnapshot
    let progressColumnMode: ProgressColumnMode
    let setProgressColumnMode: (ProgressColumnMode) -> Void
    let requestRemoveDataConfirmation: () -> Void
    let showInspector: () -> Void

    func makeNSViewController(context: Context) -> TorrentTableViewController {
        TorrentTableViewController(
            store: store,
            snapshot: snapshot,
            progressColumnMode: progressColumnMode,
            setProgressColumnMode: setProgressColumnMode,
            requestRemoveDataConfirmation: requestRemoveDataConfirmation,
            showInspector: showInspector
        )
    }

    func updateNSViewController(_ controller: TorrentTableViewController, context: Context) {
        controller.update(
            store: store,
            snapshot: snapshot,
            progressColumnMode: progressColumnMode,
            setProgressColumnMode: setProgressColumnMode,
            requestRemoveDataConfirmation: requestRemoveDataConfirmation,
            showInspector: showInspector
        )
    }
}

private enum ProgressColumnMode: String {
    case detailed
    case barOnly
}

private final class TorrentTableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private struct ColumnDefinition {
        let id: ColumnID
        let title: String
        let minWidth: CGFloat
        let preferredWidth: CGFloat
        let alignment: NSTextAlignment
        let visibleColumn: TorrentListColumn?
    }

    private enum ColumnID: String, CaseIterable {
        case name
        case progress
        case size
        case eta
        case percent
        case remaining
        case speed
        case peers

        var identifier: NSUserInterfaceItemIdentifier {
            NSUserInterfaceItemIdentifier(rawValue)
        }
    }

    private static let autosaveName = "Sweep.TorrentList"
    private static let columnDefinitions: [ColumnDefinition] = [
        ColumnDefinition(
            id: .name,
            title: "Name",
            minWidth: 320,
            preferredWidth: 420,
            alignment: .left,
            visibleColumn: nil
        ),
        ColumnDefinition(
            id: .progress,
            title: "Progress",
            minWidth: 140,
            preferredWidth: 170,
            alignment: .left,
            visibleColumn: .progress
        ),
        ColumnDefinition(
            id: .size,
            title: "Size",
            minWidth: 80,
            preferredWidth: 100,
            alignment: .right,
            visibleColumn: .size
        ),
        ColumnDefinition(
            id: .eta,
            title: "ETA",
            minWidth: 70,
            preferredWidth: 90,
            alignment: .right,
            visibleColumn: .eta
        ),
        ColumnDefinition(
            id: .percent,
            title: "%",
            minWidth: 54,
            preferredWidth: 64,
            alignment: .right,
            visibleColumn: .percent
        ),
        ColumnDefinition(
            id: .remaining,
            title: "Remaining",
            minWidth: 92,
            preferredWidth: 112,
            alignment: .right,
            visibleColumn: .remaining
        ),
        ColumnDefinition(
            id: .speed,
            title: "Speed",
            minWidth: 92,
            preferredWidth: 112,
            alignment: .left,
            visibleColumn: .speed
        ),
        ColumnDefinition(
            id: .peers,
            title: "Peers",
            minWidth: 86,
            preferredWidth: 104,
            alignment: .left,
            visibleColumn: .peers
        )
    ]

    private let scrollView = NSScrollView()
    private let tableView = TorrentTableView()
    private var columnsByID: [ColumnID: NSTableColumn] = [:]

    private var store: TorrentStore
    private var snapshot: TorrentListSnapshot
    private var progressColumnMode: ProgressColumnMode
    private var setProgressColumnMode: (ProgressColumnMode) -> Void
    private var requestRemoveDataConfirmation: () -> Void
    private var showInspector: () -> Void
    private var isApplyingSelectionToTable = false

    init(
        store: TorrentStore,
        snapshot: TorrentListSnapshot,
        progressColumnMode: ProgressColumnMode,
        setProgressColumnMode: @escaping (ProgressColumnMode) -> Void,
        requestRemoveDataConfirmation: @escaping () -> Void,
        showInspector: @escaping () -> Void
    ) {
        self.store = store
        self.snapshot = snapshot
        self.progressColumnMode = progressColumnMode
        self.setProgressColumnMode = setProgressColumnMode
        self.requestRemoveDataConfirmation = requestRemoveDataConfirmation
        self.showInspector = showInspector
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        configureScrollView()
        configureTableView()
        apply(snapshot: snapshot, progressColumnMode: progressColumnMode, shouldReloadData: true)
        syncSelection(from: nil, to: snapshot.selection)
        view = scrollView
    }

    func update(
        store: TorrentStore,
        snapshot: TorrentListSnapshot,
        progressColumnMode: ProgressColumnMode,
        setProgressColumnMode: @escaping (ProgressColumnMode) -> Void,
        requestRemoveDataConfirmation: @escaping () -> Void,
        showInspector: @escaping () -> Void
    ) {
        let previousSnapshot = self.snapshot
        let previousProgressMode = self.progressColumnMode

        self.store = store
        self.snapshot = snapshot
        self.progressColumnMode = progressColumnMode
        self.setProgressColumnMode = setProgressColumnMode
        self.requestRemoveDataConfirmation = requestRemoveDataConfirmation
        self.showInspector = showInspector

        let shouldReloadData = previousSnapshot.torrents.map(\.id) != snapshot.torrents.map(\.id)
            || previousProgressMode != progressColumnMode
            || previousSnapshot.visibleColumns != snapshot.visibleColumns

        apply(snapshot: snapshot, progressColumnMode: progressColumnMode, shouldReloadData: shouldReloadData)
        syncSelection(from: previousSnapshot.selection, to: snapshot.selection)
    }

    private func configureScrollView() {
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
    }

    private func configureTableView() {
        tableView.frame = NSRect(x: 0, y: 0, width: 920, height: 520)
        tableView.style = .fullWidth
        tableView.headerView = TorrentTableHeaderView(frame: .zero)
        (tableView.headerView as? TorrentTableHeaderView)?.menuProvider = { [weak self] in
            self?.makeHeaderMenu()
        }
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        tableView.allowsMultipleSelection = false
        tableView.allowsTypeSelect = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.selectionHighlightStyle = .regular
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 8, height: 0)
        tableView.rowHeight = 44
        tableView.usesAutomaticRowHeights = false
        tableView.autosaveName = Self.autosaveName
        tableView.autosaveTableColumns = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowMenuProvider = { [weak self] in
            self?.makeRowMenu()
        }
        tableView.optionClickProgressHandler = { [weak self] in
            self?.toggleProgressColumnMode()
        }
        tableView.deleteHandler = { [weak self] in
            self?.store.removeSelectedTorrent()
        }

        for definition in Self.columnDefinitions {
            let column = NSTableColumn(identifier: definition.id.identifier)
            column.title = definition.title
            column.minWidth = definition.minWidth
            column.width = definition.preferredWidth
            column.resizingMask = .userResizingMask
            column.headerCell.alignment = definition.alignment
            columnsByID[definition.id] = column
            tableView.addTableColumn(column)
        }

        scrollView.documentView = tableView
    }

    private func apply(
        snapshot: TorrentListSnapshot,
        progressColumnMode: ProgressColumnMode,
        shouldReloadData: Bool
    ) {
        applyVisibleColumns(snapshot.visibleColumns)

        if shouldReloadData {
            tableView.reloadData()
        } else {
            reloadRows(IndexSet(snapshot.torrents.indices))
        }
    }

    private func applyVisibleColumns(_ visibleColumns: Set<TorrentListColumn>) {
        for definition in Self.columnDefinitions {
            guard let column = columnsByID[definition.id] else { continue }
            let isVisible = definition.visibleColumn.map { visibleColumns.contains($0) } ?? true
            column.isHidden = !isVisible
        }
    }

    private func syncSelection(from previousSelection: Torrent.ID?, to selection: Torrent.ID?) {
        let selectedRow = rowIndex(for: selection)
        guard tableView.selectedRow != selectedRow else { return }

        let previousRow = tableView.selectedRow
        isApplyingSelectionToTable = true
        if selectedRow >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        isApplyingSelectionToTable = false

        reloadRows(IndexSet([previousRow, selectedRow].filter { $0 >= 0 }))

    }

    private func reloadRows(_ rows: IndexSet) {
        guard !rows.isEmpty, tableView.numberOfColumns > 0 else { return }
        tableView.reloadData(
            forRowIndexes: rows,
            columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
        )
    }

    private func rowIndex(for id: Torrent.ID?) -> Int {
        guard let id else { return -1 }
        return snapshot.torrents.firstIndex { $0.id == id } ?? -1
    }

    private func torrent(at row: Int) -> Torrent? {
        guard snapshot.torrents.indices.contains(row) else { return nil }
        return snapshot.torrents[row]
    }

    private func makeHeaderMenu() -> NSMenu {
        let menu = NSMenu(title: "Columns")

        for definition in Self.columnDefinitions {
            guard let visibleColumn = definition.visibleColumn else { continue }
            let item = NSMenuItem(
                title: definition.title,
                action: #selector(toggleColumnVisibility(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = visibleColumn.rawValue
            item.state = snapshot.visibleColumns.contains(visibleColumn) ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    private func makeRowMenu() -> NSMenu? {
        guard store.selectedTorrent != nil else { return nil }

        let menu = NSMenu(title: "Torrent")
        menu.addItem(menuItem("Resume", action: #selector(resumeSelectedTorrent(_:)), enabled: store.canResumeSelectedTorrent))
        menu.addItem(menuItem("Pause", action: #selector(pauseSelectedTorrent(_:)), enabled: store.canPauseSelectedTorrent))
        menu.addItem(.separator())
        menu.addItem(menuItem("Reveal in Finder", action: #selector(revealSelectedTorrent(_:))))
        menu.addItem(menuItem("Show Inspector", action: #selector(showInspectorPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Remove", action: #selector(removeSelectedTorrent(_:))))
        menu.addItem(menuItem("Remove and Delete Data", action: #selector(requestDeleteData(_:))))
        return menu
    }

    private func menuItem(_ title: String, action: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func toggleProgressColumnMode() {
        let nextMode: ProgressColumnMode = progressColumnMode == .detailed ? .barOnly : .detailed
        setProgressColumnMode(nextMode)
    }

    @objc private func toggleColumnVisibility(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let column = TorrentListColumn(rawValue: rawValue)
        else {
            return
        }

        store.setColumn(column, visible: !snapshot.visibleColumns.contains(column))
    }

    @objc private func resumeSelectedTorrent(_ sender: Any?) {
        store.resumeSelectedTorrent()
    }

    @objc private func pauseSelectedTorrent(_ sender: Any?) {
        store.pauseSelectedTorrent()
    }

    @objc private func revealSelectedTorrent(_ sender: Any?) {
        TorrentActions.revealSelectedTorrent(in: store)
    }

    @objc private func showInspectorPanel(_ sender: Any?) {
        showInspector()
    }

    @objc private func removeSelectedTorrent(_ sender: Any?) {
        store.removeSelectedTorrent()
    }

    @objc private func requestDeleteData(_ sender: Any?) {
        requestRemoveDataConfirmation()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        snapshot.torrents.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard
            let tableColumn,
            let torrent = torrent(at: row),
            let columnID = ColumnID(rawValue: tableColumn.identifier.rawValue)
        else {
            return nil
        }

        let isSelected = snapshot.selection == torrent.id

        switch columnID {
        case .name:
            let view = makeView(TorrentNameCellView.self, identifier: columnID.identifier)
            view.configure(
                torrent: torrent,
                isSelected: isSelected,
                pauseHandler: { [weak self] in
                    guard let self else { return }
                    TorrentActions.togglePause(torrent, in: self.store)
                },
                revealHandler: { [weak self] in
                    guard let self else { return }
                    TorrentActions.reveal(torrent, in: self.store)
                }
            )
            return view

        case .progress:
            let view = makeView(TorrentProgressCellView.self, identifier: columnID.identifier)
            view.configure(torrent: torrent, isSelected: isSelected, mode: progressColumnMode)
            return view

        case .size:
            let view = makeView(TorrentTextCellView.self, identifier: columnID.identifier)
            view.configure(text: ByteFormatter.bytes(torrent.totalBytes), isSelected: isSelected, alignment: .right)
            return view

        case .eta:
            let view = makeView(TorrentTextCellView.self, identifier: columnID.identifier)
            view.configure(text: TorrentDisplayFormat.eta(torrent), isSelected: isSelected, alignment: .right)
            return view

        case .percent:
            let view = makeView(TorrentTextCellView.self, identifier: columnID.identifier)
            view.configure(text: TorrentDisplayFormat.percent(torrent.progress), isSelected: isSelected, alignment: .right)
            return view

        case .remaining:
            let view = makeView(TorrentTextCellView.self, identifier: columnID.identifier)
            view.configure(text: ByteFormatter.bytes(torrent.remainingBytes), isSelected: isSelected, alignment: .right)
            return view

        case .speed:
            let view = makeView(TwoLineSymbolCellView.self, identifier: columnID.identifier)
            view.configure(
                first: transferRateLine(symbolName: "arrow.down", value: torrent.downloadBps, isSelected: isSelected),
                second: transferRateLine(symbolName: "arrow.up", value: torrent.uploadBps, isSelected: isSelected)
            )
            return view

        case .peers:
            let summary = PeerColumnSummary(torrent: torrent)
            let view = makeView(TwoLineSymbolCellView.self, identifier: columnID.identifier)
            view.configure(
                first: peersLine(
                    symbolName: "arrow.down",
                    active: summary.activeDownloading,
                    total: summary.totalDownloadPeers,
                    isSelected: isSelected,
                    help: "Downloading from \(summary.activeDownloading) of \(summary.totalDownloadPeers) peers"
                ),
                second: peersLine(
                    symbolName: "arrow.up",
                    active: summary.activeUploading,
                    total: summary.totalUploadPeers,
                    isSelected: isSelected,
                    help: "Uploading to \(summary.activeUploading) of \(summary.totalUploadPeers) peers"
                )
            )
            return view
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelectionToTable else { return }

        let previousSelection = snapshot.selection
        let nextSelection = torrent(at: tableView.selectedRow)?.id
        guard previousSelection != nextSelection else { return }

        store.selection = nextSelection
        reloadRows(
            IndexSet(
                [rowIndex(for: previousSelection), rowIndex(for: nextSelection)]
                    .filter { $0 >= 0 }
            )
        )
    }

    private func makeView<View: NSView>(_ type: View.Type, identifier: NSUserInterfaceItemIdentifier) -> View {
        if let view = tableView.makeView(withIdentifier: identifier, owner: self) as? View {
            return view
        }

        let view = type.init(frame: .zero)
        view.identifier = identifier
        return view
    }

    private func transferRateLine(symbolName: String, value: Double, isSelected: Bool) -> LineConfiguration {
        let color = value > 1 ? rowPrimaryColor(selected: isSelected) : rowSecondaryColor(selected: isSelected)
        return LineConfiguration(
            symbolName: symbolName,
            text: ByteFormatter.rate(value),
            color: color,
            help: nil
        )
    }

    private func peersLine(
        symbolName: String,
        active: Int,
        total: Int,
        isSelected: Bool,
        help: String
    ) -> LineConfiguration {
        LineConfiguration(
            symbolName: symbolName,
            text: "\(active) of \(total)",
            color: rowSecondaryColor(selected: isSelected),
            help: help
        )
    }
}

private final class TorrentTableView: NSTableView {
    var rowMenuProvider: (() -> NSMenu?)?
    var optionClickProgressHandler: (() -> Void)?
    var deleteHandler: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        let column = self.column(at: point)

        if
            row >= 0,
            column >= 0,
            event.modifierFlags.contains(.option),
            tableColumns[column].identifier.rawValue == "progress"
        {
            if !selectedRowIndexes.contains(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            optionClickProgressHandler?()
            return
        }

        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return nil }

        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        return rowMenuProvider?()
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty, (event.keyCode == 51 || event.keyCode == 117) {
            deleteHandler?()
            return
        }

        super.keyDown(with: event)
    }
}

private final class TorrentTableHeaderView: NSTableHeaderView {
    var menuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?() ?? super.menu(for: event)
    }
}

private final class TorrentNameCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleField = makeLabel(font: .systemFont(ofSize: 13))
    private let statusField = makeLabel(font: .systemFont(ofSize: 11))
    private let pauseButton = makeIconButton()
    private let revealButton = makeIconButton()
    private let buttonsStack = NSStackView()
    private let titleRowStack = NSStackView()
    private let textStack = NSStackView()

    private var trackingAreaRef: NSTrackingArea?
    private var torrent: Torrent?
    private var rowSelected = false
    private var isHovered = false {
        didSet {
            updateButtonVisibility()
        }
    }

    private var pauseHandler: (() -> Void)?
    private var revealHandler: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    func configure(
        torrent: Torrent,
        isSelected: Bool,
        pauseHandler: @escaping () -> Void,
        revealHandler: @escaping () -> Void
    ) {
        self.torrent = torrent
        self.rowSelected = isSelected
        self.pauseHandler = pauseHandler
        self.revealHandler = revealHandler

        titleField.stringValue = torrent.name
        titleField.toolTip = torrent.name

        let statusText = torrentListStatusText(for: torrent)
        statusField.stringValue = statusText
        statusField.toolTip = statusText

        pauseButton.image = symbolImage(
            torrent.desiredState == .paused ? "play.fill" : "pause.fill",
            pointSize: 11,
            weight: .semibold
        )
        pauseButton.toolTip = torrent.desiredState == .paused ? "Resume" : "Pause"
        revealButton.image = symbolImage("magnifyingglass", pointSize: 11, weight: .regular)
        revealButton.toolTip = "Reveal in Finder"

        updateAppearance()
    }

    @objc private func pauseClicked(_ sender: Any?) {
        pauseHandler?()
    }

    @objc private func revealClicked(_ sender: Any?) {
        revealHandler?()
    }

    private func buildView() {
        wantsLayer = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown

        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.usesSingleLineMode = true

        statusField.lineBreakMode = .byTruncatingTail
        statusField.usesSingleLineMode = true

        buttonsStack.orientation = .horizontal
        buttonsStack.alignment = .centerY
        buttonsStack.spacing = 8
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.addArrangedSubview(pauseButton)
        buttonsStack.addArrangedSubview(revealButton)
        buttonsStack.setHuggingPriority(.required, for: .horizontal)

        pauseButton.target = self
        pauseButton.action = #selector(pauseClicked(_:))
        revealButton.target = self
        revealButton.action = #selector(revealClicked(_:))

        titleRowStack.orientation = .horizontal
        titleRowStack.alignment = .centerY
        titleRowStack.spacing = 8
        titleRowStack.translatesAutoresizingMaskIntoConstraints = false
        titleRowStack.addArrangedSubview(titleField)
        titleRowStack.addArrangedSubview(buttonsStack)

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleRowStack)
        textStack.addArrangedSubview(statusField)

        addSubview(iconView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    private func updateAppearance() {
        guard let torrent else { return }

        let primaryColor = rowPrimaryColor(selected: rowSelected)
        let secondaryColor = rowSecondaryColor(selected: rowSelected)
        let statusDisplay = torrentStatusDisplay(for: torrent)

        titleField.textColor = primaryColor
        statusField.textColor = torrent.error == nil || torrent.error?.isEmpty == true
            ? secondaryColor
            : (rowSelected ? primaryColor : .systemRed)

        iconView.image = symbolImage(statusDisplay.symbolName, pointSize: 11, weight: .semibold)
        iconView.contentTintColor = rowSelected && statusDisplay.usesSelectionColor
            ? primaryColor
            : statusDisplay.color
        iconView.toolTip = statusDisplay.help

        pauseButton.contentTintColor = rowSelected ? primaryColor : secondaryColor
        revealButton.contentTintColor = rowSelected ? primaryColor : secondaryColor

        updateButtonVisibility()
    }

    private func updateButtonVisibility() {
        buttonsStack.alphaValue = isHovered || rowSelected ? 1 : 0.72
    }
}

private final class TorrentProgressCellView: NSTableCellView {
    private let stackView = NSStackView()
    private let barView = SegmentedProgressBarAppKitView()
    private let detailField = NSTextField(labelWithAttributedString: NSAttributedString(string: ""))
    private var barHeightConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(torrent: Torrent, isSelected: Bool, mode: ProgressColumnMode) {
        barView.configure(
            runs: torrent.pieceRuns,
            fallbackProgress: torrent.progress,
            state: torrent.statusLabel,
            isSelected: isSelected
        )
        barView.toolTip = TorrentDisplayFormat.percent(torrent.progress)
        barHeightConstraint?.constant = mode == .barOnly ? 16 : 8

        if mode == .barOnly {
            detailField.isHidden = true
        } else {
            detailField.isHidden = false
            detailField.attributedStringValue = progressDetailText(for: torrent, isSelected: isSelected)
        }
    }

    private func buildView() {
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false

        barView.translatesAutoresizingMaskIntoConstraints = false
        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.lineBreakMode = .byTruncatingTail
        detailField.usesSingleLineMode = true

        stackView.addArrangedSubview(barView)
        stackView.addArrangedSubview(detailField)
        addSubview(stackView)

        barHeightConstraint = barView.heightAnchor.constraint(equalToConstant: 8)
        barHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            barView.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }
}

private final class SegmentedProgressBarAppKitView: NSView {
    private var runs: [TorrentPieceRun] = []
    private var fallbackProgress = 0.0
    private var state = "Waiting"
    private var isSelected = false

    func configure(
        runs: [TorrentPieceRun],
        fallbackProgress: Double,
        state: String,
        isSelected: Bool
    ) {
        self.runs = runs
        self.fallbackProgress = fallbackProgress
        self.state = state
        self.isSelected = isSelected
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        guard rect.width > 0, rect.height > 0 else { return }

        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        trackColor.setFill()
        path.fill()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        let runs = displayRuns
        let totalBytes = runs.reduce(UInt64(0)) { $0 + $1.byteCount }
        var xOffset = rect.minX

        for (index, run) in runs.enumerated() {
            guard totalBytes > 0 else { continue }

            let width: CGFloat
            if index == runs.count - 1 {
                width = rect.maxX - xOffset
            } else {
                width = rect.width * CGFloat(Double(run.byteCount) / Double(totalBytes))
            }

            if width > 0 {
                color(for: run.state).setFill()
                NSBezierPath(rect: NSRect(x: xOffset, y: rect.minY, width: width, height: rect.height)).fill()
            }

            xOffset += width
        }

        NSGraphicsContext.restoreGraphicsState()

        NSColor.secondaryLabelColor.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private var displayRuns: [TorrentPieceRun] {
        if !runs.isEmpty {
            return runs
        }

        let downloaded = UInt64((fallbackProgress.clamped(to: 0...1) * 10_000).rounded())
        let remaining = 10_000 - downloaded
        return [
            TorrentPieceRun(id: 0, state: .downloaded, pieceCount: 1, byteCount: downloaded),
            TorrentPieceRun(id: 1, state: .needed, pieceCount: 1, byteCount: remaining)
        ].filter { $0.byteCount > 0 }
    }

    private func color(for state: TorrentPieceState) -> NSColor {
        switch state {
        case .downloaded:
            return statusFillColor
        case .downloading:
            return isSelected ? rowSecondaryColor(selected: true) : .systemCyan
        case .needed:
            return NSColor.secondaryLabelColor.withAlphaComponent(0.24)
        case .skipped:
            return NSColor.secondaryLabelColor.withAlphaComponent(0.10)
        case .unknown:
            return NSColor.secondaryLabelColor.withAlphaComponent(0.14)
        }
    }

    private var statusFillColor: NSColor {
        if isSelected, state != "Paused", state != "Pausing", state != "Error" {
            return rowPrimaryColor(selected: true)
        }
        if state == "Complete" {
            return .systemGreen
        }
        if state == "Paused" || state == "Pausing" {
            return .secondaryLabelColor
        }
        if state == "Error" {
            return .systemRed
        }
        return .systemBlue
    }

    private var trackColor: NSColor {
        if state == "Error" {
            return NSColor.systemRed.withAlphaComponent(0.10)
        }
        return NSColor.secondaryLabelColor.withAlphaComponent(0.14)
    }
}

private final class TorrentTextCellView: NSTableCellView {
    private let valueField = makeLabel(font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        valueField.lineBreakMode = .byClipping
        addSubview(valueField)

        NSLayoutConstraint.activate([
            valueField.leadingAnchor.constraint(equalTo: leadingAnchor),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, isSelected: Bool, alignment: NSTextAlignment) {
        valueField.stringValue = text
        valueField.alignment = alignment
        valueField.textColor = rowSecondaryColor(selected: isSelected)
        valueField.toolTip = text
    }
}

private struct LineConfiguration {
    let symbolName: String
    let text: String
    let color: NSColor
    let help: String?
}

private final class TwoLineSymbolCellView: NSTableCellView {
    private let stackView = NSStackView()
    private let firstLine = SymbolTextLineView()
    private let secondLine = SymbolTextLineView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(firstLine)
        stackView.addArrangedSubview(secondLine)

        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(first: LineConfiguration, second: LineConfiguration) {
        firstLine.configure(line: first)
        secondLine.configure(line: second)
    }
}

private final class SymbolTextLineView: NSView {
    private let imageView = NSImageView()
    private let textField = makeLabel(font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown

        textField.lineBreakMode = .byClipping
        textField.usesSingleLineMode = true

        addSubview(imageView)
        addSubview(textField)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 10),
            imageView.heightAnchor.constraint(equalToConstant: 10),

            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(line: LineConfiguration) {
        imageView.image = symbolImage(line.symbolName, pointSize: 9, weight: .regular)
        imageView.contentTintColor = line.color
        textField.stringValue = line.text
        textField.textColor = line.color
        toolTip = line.help
    }
}

private struct PeerColumnSummary {
    let activeDownloading: Int
    let activeUploading: Int
    let totalDownloadPeers: Int
    let totalUploadPeers: Int

    init(torrent: Torrent) {
        let livePeers = torrent.peers.filter(\.isLiveConnection)
        self.activeDownloading = livePeers.filter { ($0.downloadBps ?? 0) > 1 }.count
        self.activeUploading = livePeers.filter { ($0.uploadBps ?? 0) > 1 }.count
        self.totalDownloadPeers = livePeers.count
        self.totalUploadPeers = livePeers.count
    }
}

private func torrentListStatusText(for torrent: Torrent) -> String {
    if let error = torrent.error, !error.isEmpty {
        return error
    }

    var parts = [torrent.statusLabel]

    if torrent.totalBytes > 0 {
        parts.append("\(TorrentDisplayFormat.percent(torrent.progress)) of \(ByteFormatter.bytes(torrent.totalBytes))")
    } else {
        parts.append("Waiting for metadata")
    }

    if torrent.remainingBytes > 0 {
        parts.append("\(ByteFormatter.bytes(torrent.remainingBytes)) remaining")
    }

    if let eta = torrent.etaSeconds {
        parts.append("\(TorrentDisplayFormat.duration(eta)) left")
    }

    if torrent.downloadBps > 1 {
        parts.append("\(ByteFormatter.rate(torrent.downloadBps)) down")
    }

    if torrent.uploadBps > 1 {
        parts.append("\(ByteFormatter.rate(torrent.uploadBps)) up")
    }

    if !torrent.peers.isEmpty {
        let peerText = torrent.peers.count == 1 ? "1 peer" : "\(torrent.peers.count) peers"
        parts.append(peerText)
    }

    return parts.joined(separator: " - ")
}

private struct TorrentStatusDisplay {
    let symbolName: String
    let color: NSColor
    let help: String
    let usesSelectionColor: Bool
}

private func torrentStatusDisplay(for torrent: Torrent) -> TorrentStatusDisplay {
    if torrent.error != nil {
        return TorrentStatusDisplay(
            symbolName: "exclamationmark.circle.fill",
            color: .systemRed,
            help: "Error",
            usesSelectionColor: false
        )
    }
    if torrent.desiredState == .paused || torrent.isPausedInEngine {
        return TorrentStatusDisplay(
            symbolName: "circle.fill",
            color: .secondaryLabelColor,
            help: "Paused",
            usesSelectionColor: false
        )
    }
    if torrent.progress >= 1 {
        if torrent.uploadBps > 1 {
            return TorrentStatusDisplay(
                symbolName: "arrow.up.circle.fill",
                color: .systemGreen,
                help: "Seeding",
                usesSelectionColor: true
            )
        }
        return TorrentStatusDisplay(
            symbolName: "checkmark.circle.fill",
            color: .systemGreen,
            help: "Complete",
            usesSelectionColor: true
        )
    }
    if torrent.downloadBps > 1 {
        return TorrentStatusDisplay(
            symbolName: "arrow.down.circle.fill",
            color: .systemBlue,
            help: "Downloading",
            usesSelectionColor: true
        )
    }
    return TorrentStatusDisplay(
        symbolName: "circle.dotted",
        color: .secondaryLabelColor,
        help: "Waiting",
        usesSelectionColor: false
    )
}

private func progressDetailText(for torrent: Torrent, isSelected: Bool) -> NSAttributedString {
    let result = NSMutableAttributedString(
        string: TorrentDisplayFormat.percent(torrent.progress),
        attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: rowSecondaryColor(selected: isSelected)
        ]
    )

    if torrent.remainingBytes > 0 {
        result.append(
            NSAttributedString(
                string: " \(ByteFormatter.bytes(torrent.remainingBytes))",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: rowTertiaryColor(selected: isSelected)
                ]
            )
        )
    }

    return result
}

@MainActor
private func makeLabel(font: NSFont) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = font
    label.backgroundColor = .clear
    label.isBezeled = false
    label.isEditable = false
    label.isSelectable = false
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}

@MainActor
private func makeIconButton() -> NSButton {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.imagePosition = .imageOnly
    button.focusRingType = .none
    button.controlSize = .small
    return button
}

@MainActor
private func symbolImage(_ systemName: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
}

private func rowPrimaryColor(selected: Bool) -> NSColor {
    selected ? .alternateSelectedControlTextColor : .labelColor
}

private func rowSecondaryColor(selected: Bool) -> NSColor {
    let color = selected ? NSColor.alternateSelectedControlTextColor : .secondaryLabelColor
    return color.withAlphaComponent(selected ? 0.82 : 1)
}

private func rowTertiaryColor(selected: Bool) -> NSColor {
    let color = selected ? NSColor.alternateSelectedControlTextColor : .tertiaryLabelColor
    return color.withAlphaComponent(selected ? 0.64 : 1)
}

private struct TransferStatusBar: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        HStack(spacing: 16) {
            Label(ByteFormatter.rate(store.sessionStats.downloadBps), systemImage: "arrow.down")
            Label(ByteFormatter.rate(store.sessionStats.uploadBps), systemImage: "arrow.up")
            Label("\(store.sessionStats.livePeers) peers", systemImage: "person.2")

            if store.sessionStats.connectingPeers > 0 {
                Text("\(store.sessionStats.connectingPeers) connecting")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let error = store.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let torrent = store.selectedTorrent {
                Text(torrent.statusLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.bar)
    }
}
