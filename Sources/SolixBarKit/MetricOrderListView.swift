import AppKit

/// Sortierbare Metrik-Liste für die Einstellungen: Häkchen wählt die Werte
/// aus, Ziehen einer Zeile ändert die Reihenfolge. Auswahl UND Reihenfolge
/// ergeben zusammen `result` — die Arrays in AppSettings sind geordnet.
@MainActor
final class MetricOrderListView: NSView {
    var onChange: (() -> Void)?

    private(set) var orderedMetrics: [BarMetric] = BarMetric.allCases
    private(set) var selected: Set<BarMetric> = []

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private static let dragType = NSPasteboard.PasteboardType("local.codex.SolixBar.metricRow")

    /// Ausgegraut, solange die Liste einer anderen folgt ("Folgt ..."-Modus).
    var isListEnabled = true {
        didSet {
            tableView.isEnabled = isListEnabled
            alphaValue = isListEnabled ? 1 : 0.5
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Setzt Zustand ohne onChange auszulösen: ausgewählte Metriken in
    /// gespeicherter Reihenfolge zuerst, alle übrigen (abgewählt) dahinter.
    func load(order: [BarMetric], selected: Set<BarMetric>) {
        var full = order.filter { BarMetric.allCases.contains($0) }
        for metric in BarMetric.allCases where !full.contains(metric) {
            full.append(metric)
        }
        orderedMetrics = full
        self.selected = selected
        tableView.reloadData()
    }

    /// Geordnete Auswahl — das, was in AppSettings gespeichert wird.
    var result: [BarMetric] {
        orderedMetrics.filter(selected.contains)
    }

    func reloadTitles() {
        tableView.reloadData()
    }

    private func buildView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("metric"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.registerForDraggedTypes([Self.dragType])

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let height = CGFloat(BarMetric.allCases.count) * (tableView.rowHeight + 2) + 6
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: height),
            scrollView.widthAnchor.constraint(equalToConstant: 240)
        ])
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        // Zeile über die aktuelle Position auflösen — nach einem Drag stimmen
        // gemerkte Indizes nicht mehr.
        let row = tableView.row(for: sender)
        guard row >= 0, row < orderedMetrics.count else { return }
        let metric = orderedMetrics[row]
        if sender.state == .on {
            selected.insert(metric)
        } else {
            selected.remove(metric)
        }
        onChange?()
    }
}

extension MetricOrderListView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        orderedMetrics.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let metric = orderedMetrics[row]
        // Zellen bewusst nicht wiederverwenden (8 Zeilen): target/action und
        // Zustand werden so bei jedem Aufbau frisch gesetzt.
        let checkbox = NSButton(
            checkboxWithTitle: metric.localizedTitle,
            target: self,
            action: #selector(checkboxToggled(_:))
        )
        checkbox.state = selected.contains(metric) ? .on : .off
        checkbox.isEnabled = isListEnabled
        checkbox.toolTip = metric.localizedTooltip

        let grip = NSImageView()
        grip.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        grip.contentTintColor = .tertiaryLabelColor

        let cell = NSStackView(views: [checkbox, NSView(), grip])
        cell.orientation = .horizontal
        cell.spacing = 4
        cell.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 8)
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard isListEnabled else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.dragType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard isListEnabled, dropOperation == .above else { return [] }
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let raw = info.draggingPasteboard.string(forType: Self.dragType),
              let sourceRow = Int(raw),
              sourceRow >= 0, sourceRow < orderedMetrics.count else { return false }
        var target = row
        if sourceRow < target { target -= 1 }
        guard target != sourceRow else { return true }
        let metric = orderedMetrics.remove(at: sourceRow)
        orderedMetrics.insert(metric, at: target)
        tableView.reloadData()
        onChange?()
        return true
    }
}
