//
//  AgentMonitorViewController.swift
//  AgentPad
//
//  Popover 主视图：Header / List / Footer。
//  代码布局，无 xib / storyboard。
//

import AppKit

final class AgentMonitorViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}
    var onRetry: () -> Void = {}

    private let countLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyView = AgentMonitorEmptyView()
    private let errorView = AgentMonitorErrorView()
    private let listContainer = NSView()

    private var processes: [AgentProcess] = []
    private var currentEvent: AgentMonitorEvent = .empty

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.setFrameSize(NSSize(width: 320, height: 400))

        let header = makeHeader()
        let footer = makeFooter()
        let list = makeList()

        root.addSubview(header)
        root.addSubview(list)
        root.addSubview(footer)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 320),
            root.heightAnchor.constraint(equalToConstant: 400),

            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 40),

            list.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            list.topAnchor.constraint(equalTo: header.bottomAnchor),
            list.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 36),
        ])

        self.view = root
        applyEventToUI()
    }

    // MARK: - Header
    private func makeHeader() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = NSLocalizedString("agent.monitor.header.title", comment: "")
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.alignment = .right

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(titleLabel)
        v.addSubview(countLabel)
        v.addSubview(separator)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            countLabel.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
        return v
    }

    // MARK: - List
    private func makeList() -> NSView {
        listContainer.translatesAutoresizingMaskIntoConstraints = false

        // table
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("agent"))
        column.width = 320
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = AgentRowView.rowHeight
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.gridStyleMask = []

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        emptyView.isHidden = true
        errorView.isHidden = true
        errorView.onRetry = { [weak self] in self?.onRetry() }

        listContainer.addSubview(scrollView)
        listContainer.addSubview(emptyView)
        listContainer.addSubview(errorView)

        for sub in [scrollView, emptyView, errorView] {
            NSLayoutConstraint.activate([
                sub.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
                sub.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
                sub.topAnchor.constraint(equalTo: listContainer.topAnchor),
                sub.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            ])
        }
        return listContainer
    }

    // MARK: - Footer
    private func makeFooter() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let settings = NSButton(title: NSLocalizedString("Settings...", comment: ""),
                                target: self, action: #selector(openSettings(_:)))
        settings.bezelStyle = .inline
        settings.translatesAutoresizingMaskIntoConstraints = false

        let quit = NSButton(title: NSLocalizedString("Quit", comment: ""),
                            target: self, action: #selector(quitApp(_:)))
        quit.bezelStyle = .inline
        quit.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(separator)
        v.addSubview(settings)
        v.addSubview(quit)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            separator.topAnchor.constraint(equalTo: v.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            settings.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            settings.centerYAnchor.constraint(equalTo: v.centerYAnchor),

            quit.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            quit.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    @objc private func openSettings(_ sender: Any?) { onOpenSettings() }
    @objc private func quitApp(_ sender: Any?) { onQuit() }

    // MARK: - Apply event

    func apply(event: AgentMonitorEvent) {
        currentEvent = event
        if isViewLoaded { applyEventToUI() }
    }

    private func applyEventToUI() {
        switch currentEvent {
        case .empty:
            processes = []
            scrollView.isHidden = true
            errorView.isHidden = true
            emptyView.isHidden = false
            countLabel.stringValue = NSLocalizedString("agent.monitor.header.idle", comment: "")
        case .pollingFailed:
            scrollView.isHidden = true
            emptyView.isHidden = true
            errorView.isHidden = false
            countLabel.stringValue = NSLocalizedString("agent.monitor.header.idle", comment: "")
        case .updated(let list):
            processes = list
            errorView.isHidden = true
            if list.isEmpty {
                scrollView.isHidden = true
                emptyView.isHidden = false
                countLabel.stringValue = NSLocalizedString("agent.monitor.header.idle", comment: "")
            } else {
                scrollView.isHidden = false
                emptyView.isHidden = true
                let fmt = NSLocalizedString("agent.monitor.header.count.fmt", comment: "")
                countLabel.stringValue = String(format: fmt, list.count)
            }
            tableView.reloadData()
        }
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { processes.count }

    private static let rowReuseID = NSUserInterfaceItemIdentifier("agent.row")

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell: AgentRowView
        if let reused = tableView.makeView(withIdentifier: Self.rowReuseID, owner: self) as? AgentRowView {
            cell = reused
        } else {
            cell = AgentRowView(frame: .zero)
            cell.identifier = Self.rowReuseID
        }
        cell.configure(with: processes[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return AgentRowView.rowHeight
    }
}
