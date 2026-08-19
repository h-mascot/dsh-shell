import Cocoa
import WebKit

// MARK: - Version

let kShellVersion = "3.0"

// MARK: - Tab state (v3: names persist)

struct SavedTab: Codable {
    var name: String?
    var url: String
}

final class TabStateStore {
    static let shared = TabStateStore()
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DSH Shell", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tabs-v3.json")
    }

    func load() -> [SavedTab] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SavedTab].self, from: data),
              !decoded.isEmpty
        else { return [] }
        return decoded
    }

    func save(_ tabs: [SavedTab]) {
        if let data = try? JSONEncoder().encode(tabs) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Environment profiles (Settings-only in v3)

struct Profile: Codable, Equatable {
    var name: String
    var url: String
}

final class ProfileStore {
    static let shared = ProfileStore()
    private(set) var profiles: [Profile] = []
    let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DSH Shell", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("profiles.json")
        load()
    }

    func replace(with newProfiles: [Profile]) {
        profiles = newProfiles
        save()
    }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data),
           decoded.contains(where: { !$0.name.isEmpty }) {
            profiles = decoded
        } else {
            profiles = [
                Profile(name: "Enterprise", url: "https://enterprise.tail032b4d.ts.net:3092/"),
                Profile(name: "Enterprise (localhost)", url: "http://127.0.0.1:3092/"),
                Profile(name: "MascotM3", url: "http://100.86.150.96:3092/")
            ]
            save()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func url(forProfileNamed name: String) -> URL? {
        guard let p = profiles.first(where: { $0.name == name }) else { return nil }
        return URL(string: p.url)
    }

    func profile(matchingOriginOf url: URL?) -> Profile? {
        guard let url else { return nil }
        return profiles.first { p in
            guard let purl = URL(string: p.url) else { return false }
            return AppDelegate.sameOrigin(purl, url)
        }
    }
}

// MARK: - Tab record (one window per tab, native tab group)

final class TabRecord: NSObject {
    let id = UUID()
    let window: NSWindow
    let webView: WKWebView
    var customName: String?
    var observationTokens: [NSKeyValueObservation] = []

    init(window: NSWindow, webView: WKWebView) {
        self.window = window
        self.webView = webView
        super.init()
    }

    var displayName: String {
        let custom = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        return TabRecord.fallbackLabel(for: webView.url)
    }

    static func fallbackLabel(for url: URL?) -> String {
        guard let url else { return "New Tab" }
        if let p = ProfileStore.shared.profile(matchingOriginOf: url) {
            return p.name
        }
        return url.host ?? url.absoluteString
    }

    func refreshTitle() {
        window.title = displayName
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    var tabs: [TabRecord] = []
    var suppressSave = false
    let tabbingIdentifier = "ai.heraldlabs.dsh-shell.tab"

    var settingsWindow: NSWindow?
    var profileRows: [(name: NSTextField, url: NSTextField)] = []
    var defaultProfilePopup: NSPopUpButton?
    var founderMenuItem: NSMenuItem?

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        restoreState()
        if let key = tabs.first?.window {
            key.makeKeyAndOrderFront(nil)
            for other in tabs.dropFirst() {
                key.addTabbedWindow(other.window, ordered: .above)
            }
            if let activeId = UserDefaults.standard.string(forKey: "activeTabIdV3"),
               let active = tabs.first(where: { $0.id.uuidString == activeId }) {
                active.window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Settings window closing should never quit; only the last tab does.
        tabs.isEmpty && settingsWindow == nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveState()
    }

    // MARK: menu (platform conventions; tab navigation items are native)

    func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About DSH Shell", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction(_:)), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide DSH Shell", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit DSH Shell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTabAction(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Open Location…", action: #selector(openLocationAction(_:)), keyEquivalent: "l")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTabAction(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let founderItem = viewMenu.addItem(withTitle: "Show Founder Morph", action: #selector(toggleFounderThemeMenuAction(_:)), keyEquivalent: "f")
        founderItem.keyEquivalentModifierMask = [.command, .shift]
        founderItem.state = (UserDefaults.standard.object(forKey: EffortControlScript.founderThemeDefaultsKey) as? Bool ?? true) ? .on : .off
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)
        founderMenuItem = founderItem

        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        winMenu.addItem(NSMenuItem.separator())
        winMenu.addItem(withTitle: "Rename Tab…", action: #selector(renameTabAction(_:)), keyEquivalent: "r")
        winMenu.addItem(NSMenuItem.separator())
        for i in 1...9 {
            let item = winMenu.addItem(withTitle: "Select Tab \(i)", action: #selector(selectTabByIndexAction(_:)), keyEquivalent: String(i))
            item.tag = i
        }
        winItem.submenu = winMenu
        mainMenu.addItem(winItem)
        NSApp.windowsMenu = winMenu
        // AppKit appends native tab navigation (Show Next/Previous Tab,
        // Move Tab to New Window, Select Tab 1-9) to the Window menu.

        NSApp.mainMenu = mainMenu
    }

    // MARK: tabs

    var currentTab: TabRecord? {
        tabs.first { $0.window.isKeyWindow }
            ?? tabs.first { $0.window === NSApp.mainWindow }
            ?? tabs.first
    }

    @objc func newTabAction(_ sender: Any?) {
        _ = addTab(url: urlForNewTab(), name: nil, select: true)
    }

    func urlForNewTab() -> URL? {
        if let current = currentTab?.webView.url {
            if let profile = ProfileStore.shared.profile(matchingOriginOf: current) {
                return URL(string: profile.url)
            }
            var comps = URLComponents(url: current, resolvingAgainstBaseURL: false)
            comps?.path = "/"
            return comps?.url
        }
        let defaultName = UserDefaults.standard.string(forKey: "defaultNewTabProfile") ?? ProfileStore.shared.profiles.first?.name
        return ProfileStore.shared.url(forProfileNamed: defaultName ?? "")
    }

    @discardableResult
    func addTab(url: URL?, name: String?, select: Bool) -> TabRecord {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        if let effortScript = EffortControlScript.makeUserScript() {
            config.userContentController.addUserScript(effortScript)
        }
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 820), configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.configuration.preferences.isElementFullscreenEnabled = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.minSize = NSSize(width: 480, height: 360)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = tabbingIdentifier
        window.isRestorable = false
        window.delegate = self
        window.contentView = webView
        if let frame = savedFrame() {
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }

        let record = TabRecord(window: window, webView: webView)
        record.customName = name
        tabs.append(record)

        record.observationTokens.append(webView.observe(\.url, options: [.new, .initial]) { [weak self] wv, _ in
            DispatchQueue.main.async {
                record.refreshTitle()
                self?.saveState()
            }
        })

        if let url {
            webView.load(URLRequest(url: url))
        }
        record.refreshTitle()

        if select, let key = currentTab?.window ?? tabs.first?.window {
            if key !== window, tabs.count > 1 {
                key.addTabbedWindow(window, ordered: .above)
            }
            window.makeKeyAndOrderFront(nil)
        }
        saveState()
        return record
    }

    @objc func closeTabAction(_ sender: Any?) {
        guard let tab = currentTab else { return }
        closeTab(record: tab)
    }

    func closeTab(record: TabRecord) {
        let willBeEmpty = tabs.count == 1
        record.observationTokens.forEach { $0.invalidate() }
        if let idx = tabs.firstIndex(where: { $0.id == record.id }) {
            tabs.remove(at: idx)
        }
        record.window.orderOut(nil)
        record.window.close()
        if willBeEmpty {
            _ = addTab(url: urlForNewTab(), name: nil, select: true)
            return
        }
        saveState()
    }

    // NSWindowDelegate: window closed via traffic light or ⌘W
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard let record = tabs.first(where: { $0.window === window }) else { return }
        let willBeEmpty = tabs.count == 1
        record.observationTokens.forEach { $0.invalidate() }
        if let idx = tabs.firstIndex(where: { $0.id == record.id }) {
            tabs.remove(at: idx)
        }
        if willBeEmpty {
            _ = addTab(url: urlForNewTab(), name: nil, select: true)
        } else {
            saveState()
        }
    }

    func windowDidMove(_ notification: Notification) { persistFrame() }
    func windowDidResize(_ notification: Notification) { persistFrame(); saveState() }
    func windowDidBecomeKey(_ notification: Notification) { saveState() }

    // MARK: rename sheet

    @objc func renameTabAction(_ sender: Any?) {
        guard let record = currentTab else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = "This name appears on the tab and stays after relaunch."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = record.customName ?? record.displayName
        field.placeholderString = TabRecord.fallbackLabel(for: record.webView.url)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: record.window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            record.customName = value.isEmpty ? nil : value
            record.refreshTitle()
            self?.saveState()
        }
    }

    // MARK: open location sheet

    @objc func selectTabByIndexAction(_ sender: NSMenuItem) {
        guard let key = currentTab?.window ?? tabs.first?.window,
              let group = key.tabbedWindows, !group.isEmpty else { return }
        let idx = sender.tag - 1
        guard idx >= 0, idx < group.count else { return }
        group[idx].makeKeyAndOrderFront(nil)
    }

    @objc func openLocationAction(_ sender: Any?) {
        guard let record = currentTab else { return }
        let alert = NSAlert()
        alert.messageText = "Open Location"
        alert.informativeText = "Load a URL in the current tab."
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = record.webView.url?.absoluteString ?? ""
        field.placeholderString = "https://host:port/"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: record.window) { response in
            guard response == .alertFirstButtonReturn else { return }
            var text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            if !text.contains("://") {
                guard text.contains("."), !text.contains(" ") else { return }
                text = "https://" + text
            }
            guard let url = URL(string: text) else { return }
            record.webView.load(URLRequest(url: url))
        }
    }

    // MARK: state

    func saveState() {
        guard !suppressSave else { return }
        // Order tabs by the key window's tab group when available.
        var ordered: [TabRecord] = []
        if let group = (currentTab?.window ?? tabs.first?.window)?.tabbedWindows {
            let groupWindows = Set(group.map(ObjectIdentifier.init))
            ordered = tabs.filter { groupWindows.contains(ObjectIdentifier($0.window)) }
            ordered.sort { a, b in
                let ia = group.firstIndex(where: { $0 === a.window }) ?? 0
                let ib = group.firstIndex(where: { $0 === b.window }) ?? 0
                return ia < ib
            }
            let known = Set(ordered.map(\.id))
            ordered.append(contentsOf: tabs.filter { !known.contains($0.id) })
        } else {
            ordered = tabs
        }
        let saved = ordered.map { SavedTab(name: $0.customName, url: $0.webView.url?.absoluteString ?? "") }
        TabStateStore.shared.save(saved)
        if let active = currentTab {
            UserDefaults.standard.set(active.id.uuidString, forKey: "activeTabIdV3")
        }
    }

    func restoreState() {
        suppressSave = true
        defer { suppressSave = false }

        var restored: [SavedTab] = TabStateStore.shared.load()

        if restored.isEmpty {
            let legacy = UserDefaults.standard.stringArray(forKey: "openTabs") ?? []
            if !legacy.isEmpty {
                restored = legacy.map { SavedTab(name: nil, url: $0) }
            }
        }

        if restored.isEmpty {
            let url = ProfileStore.shared.profiles.first.flatMap { URL(string: $0.url) }
            addTab(url: url, name: nil, select: true)
        } else {
            for saved in restored {
                addTab(url: URL(string: saved.url), name: saved.name, select: false)
            }
        }
        saveState()
    }

    // MARK: frame persistence

    private func savedFrame() -> NSRect? {
        guard let s = UserDefaults.standard.string(forKey: "windowFrameV3") else { return nil }
        let parts = s.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        var f = NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        guard f.width >= 480, f.height >= 360 else { return nil }
        // Keep at least partially on screen.
        if f.maxX < screenFrame.minX + 100 || f.minX > screenFrame.maxX - 100 {
            f.origin.x = screenFrame.minX + 40
        }
        if f.maxY < screenFrame.minY + 100 || f.minY > screenFrame.maxY - 100 {
            f.origin.y = screenFrame.minY + 40
        }
        return f
    }

    private func persistFrame() {
        guard let w = currentTab?.window ?? tabs.first?.window else { return }
        let f = w.frame
        UserDefaults.standard.set("\(f.origin.x),\(f.origin.y),\(f.width),\(f.height)", forKey: "windowFrameV3")
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let record = addTab(url: navigationAction.request.url, name: nil, select: true)
        return record.webView
    }

    // MARK: Settings window

    @objc func openSettingsAction(_ sender: Any?) {
        if let sw = settingsWindow {
            sw.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 470),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        w.title = "Settings"
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        w.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 320))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        let scroll = NSScrollView()
        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        if #available(macOS 26.0, *) {
            scroll.verticalScroller?.scrollerStyle = .overlay
        }
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        content.addSubview(scroll)

        let defaultLabel = NSTextField(labelWithString: "New tabs open:")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 24), pullsDown: false)
        popup.addItems(withTitles: ProfileStore.shared.profiles.map { $0.name })
        let savedDefault = UserDefaults.standard.string(forKey: "defaultNewTabProfile") ?? ProfileStore.shared.profiles.first?.name
        if let savedDefault, let idx = ProfileStore.shared.profiles.firstIndex(where: { $0.name == savedDefault }) {
            popup.selectItem(at: idx)
        }
        defaultProfilePopup = popup

        let defaultRow = NSStackView(views: [defaultLabel, popup])
        defaultRow.orientation = .horizontal
        defaultRow.spacing = 6

        // Founder theme toggle: reasoning-effort background imagery (Off=suit,
        // High=mandarin jacket, Max=imperial robe) behind the new-session hero.
        let founderLabel = NSTextField(labelWithString: "Effort background theme:")
        let founderToggle = NSButton(checkboxWithTitle: "Show founder morph", target: self, action: #selector(founderThemeToggled(_:)))
        founderToggle.state = (UserDefaults.standard.object(forKey: EffortControlScript.founderThemeDefaultsKey) as? Bool ?? true) ? .on : .off
        let founderHint = NSTextField(labelWithString: "Off=suit · High=jacket · Max=robe")
        founderHint.font = .systemFont(ofSize: 10)
        founderHint.textColor = .secondaryLabelColor
        founderHint.cell?.truncatesLastVisibleLine = true
        founderHint.cell?.wraps = false
        let founderRow = NSStackView(views: [founderLabel, founderToggle, founderHint])
        founderRow.orientation = .horizontal
        founderRow.spacing = 6

        let addButton = NSButton(title: "+ Add Environment", target: self, action: #selector(addProfileRow(_:)))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveProfilesAction(_:)))
        saveButton.keyEquivalent = "\r"
        if #available(macOS 26.0, *) {
            saveButton.bezelStyle = .glass
        } else {
            saveButton.bezelStyle = .push
        }

        let buttonRow = NSStackView(views: [addButton, NSView(), saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 6
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -6),
            buttonRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])

        stack.addArrangedSubview(defaultRow)
        stack.addArrangedSubview(founderRow)
        stack.addArrangedSubview(makeSeparator())

        w.contentView = content
        w.minSize = NSSize(width: 560, height: 200)
        self.settingsWindow = w
        self.profileRows = []
        for p in ProfileStore.shared.profiles {
            appendProfileRow(to: stack, name: p.name, url: p.url)
        }
        fitSettingsWindow()
        w.makeKeyAndOrderFront(nil)
    }

    /// Size the settings window to exactly fit its content so nothing scrolls;
    /// past a sane cap the overlay scroller (auto-hiding) takes over.
    func fitSettingsWindow() {
        guard let w = settingsWindow,
              let scroll = w.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first,
              let stack = scroll.documentView as? NSStackView else { return }
        stack.layoutSubtreeIfNeeded()
        // stack fitting height + button row (~28) + button gap (6) + bottom pad (10) + safety (4)
        let required = stack.fittingSize.height + 48
        let cap: CGFloat = 640
        let target = min(max(required, 200), cap)
        let delta = target - w.contentView!.frame.height
        guard abs(delta) > 0.5 else { return }
        var frame = w.frame
        frame.origin.y -= delta
        frame.size.height += delta
        w.setFrame(frame, display: true)
    }

    func appendProfileRow(to stack: NSStackView, name: String, url: String) {
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 150, height: 24))
        nameField.stringValue = name
        nameField.placeholderString = "Name"
        let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        urlField.stringValue = url
        urlField.placeholderString = "https://host:port/"
        let remove = NSButton(title: "−", target: self, action: #selector(removeProfileRow(_:)))

        let row = NSStackView(views: [nameField, urlField, remove])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(makeSeparator())

        profileRows.append((name: nameField, url: urlField))

        nameField.widthAnchor.constraint(equalToConstant: 150).isActive = true
        urlField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        // Keep the remove button inside the window: window 620 − content insets
        // (24) − name (150) − remove (35) − inter-view spacing (3×8) ≈ 387 max
        // for the URL field; rows are allowed to compress from the old 360.
        urlField.setContentCompressionResistancePriority(.required, for: .horizontal)
        urlField.widthAnchor.constraint(lessThanOrEqualToConstant: 387).isActive = true
    }

    func makeSeparator() -> NSView {
        let sep = NSBox()
        sep.boxType = .separator
        return sep
    }

    @objc func founderThemeToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: EffortControlScript.founderThemeDefaultsKey)
        founderMenuItem?.state = enabled ? .on : .off
        for record in tabs {
            record.webView.evaluateJavaScript("window.__DSH_EFFORT_CONTROL__ && window.__DSH_EFFORT_CONTROL__.setFounderTheme ? window.__DSH_EFFORT_CONTROL__.setFounderTheme(\(enabled)) : undefined") { _, _ in }
        }
    }

    @objc func toggleFounderThemeMenuAction(_ sender: NSMenuItem) {
        let enabled = (sender.state != .on)
        sender.state = enabled ? .on : .off
        UserDefaults.standard.set(enabled, forKey: EffortControlScript.founderThemeDefaultsKey)
        for record in tabs {
            record.webView.evaluateJavaScript("window.__DSH_EFFORT_CONTROL__ && window.__DSH_EFFORT_CONTROL__.setFounderTheme ? window.__DSH_EFFORT_CONTROL__.setFounderTheme(\(enabled)) : undefined") { _, _ in }
        }
    }

    @objc func addProfileRow(_ sender: Any?) {
        guard let stack = settingsWindow?.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first?.documentView as? NSStackView else { return }
        appendProfileRow(to: stack, name: "", url: "")
        fitSettingsWindow()
    }

    @objc func removeProfileRow(_ sender: NSButton) {
        var node: NSView? = sender.superview
        while let v = node, !(v is NSStackView) || (v as? NSStackView)?.orientation != .horizontal {
            node = v.superview
            if node is NSScrollView { node = nil; break }
        }
        guard let row = node as? NSStackView else { return }
        profileRows.removeAll { row.views.contains($0.name) || row.views.contains($0.url) }
        let sep = row.superview?.subviews.first { $0 != row && abs($0.frame.minY - row.frame.minY) < 2 && $0 is NSBox }
        row.removeFromSuperview()
        sep?.removeFromSuperview()
        fitSettingsWindow()
    }

    @objc func saveProfilesAction(_ sender: Any?) {
        var collected: [Profile] = []
        for row in profileRows {
            let n = row.name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var u = row.url.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty, !u.isEmpty else { continue }
            if !u.contains("://") { u = "https://" + u }
            collected.append(Profile(name: n, url: u))
        }
        if !collected.isEmpty {
            ProfileStore.shared.replace(with: collected)
        }
        if let title = defaultProfilePopup?.titleOfSelectedItem {
            UserDefaults.standard.set(title, forKey: "defaultNewTabProfile")
        }
        for record in tabs {
            record.refreshTitle()
        }
        settingsWindow?.close()
    }

    // MARK: helpers

    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        (a.scheme ?? "") == (b.scheme ?? "") && (a.host ?? "") == (b.host ?? "") && (a.port ?? 80) == (b.port ?? 80)
    }
}

// MARK: - Bootstrap

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
