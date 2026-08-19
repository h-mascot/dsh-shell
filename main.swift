import Cocoa
import WebKit

// MARK: - Profile store

struct Profile: Codable, Equatable {
    var name: String
    var url: String
}

final class ProfileStore {
    static let shared = ProfileStore()
    private(set) var profiles: [Profile] = []

    func replace(with newProfiles: [Profile]) {
        profiles = newProfiles
        save()
    }
    let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DSH Shell", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("profiles.json")
        load()
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
}

// MARK: - Tab record

final class TabRecord {
    let webView: WKWebView
    let tabItem: NSTabViewItem
    var observationTokens: [NSKeyValueObservation] = []

    init(webView: WKWebView, tabItem: NSTabViewItem) {
        self.webView = webView
        self.tabItem = tabItem
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSTabViewDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var tabView: NSTabView!
    var profilePopup: NSPopUpButton!
    var addressField: NSTextField!
    var tabs: [TabRecord] = []
    var selectedProfileIndex: Int = 0
    var suppressTabSelect = false

    let profilesMenuIdentifier = NSToolbarItem.Identifier("dsh.profiles")
    let addressIdentifier = NSToolbarItem.Identifier("dsh.address")
    let addTabIdentifier = NSToolbarItem.Identifier("dsh.addTab")
    let closeTabIdentifier = NSToolbarItem.Identifier("dsh.closeTab")

    var currentTab: TabRecord? {
        let idx = tabView.indexOfTabViewItem(tabView.selectedTabViewItem ?? NSTabViewItem())
        guard idx != NSNotFound, idx < tabs.count else { return nil }
        return tabs[idx]
    }

    func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About DSH Shell", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide DSH Shell", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit DSH Shell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTabAction(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTabAction(_:)), keyEquivalent: "w")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Manage Profiles…", action: #selector(manageProfilesAction(_:)), keyEquivalent: ",")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Edit menu (required for copy/paste inside WKWebView)
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

        // Window menu
        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        winItem.submenu = winMenu
        mainMenu.addItem(winItem)
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        selectedProfileIndex = UserDefaults.standard.integer(forKey: "selectedProfileIndex")
        if selectedProfileIndex < 0 || selectedProfileIndex >= ProfileStore.shared.profiles.count {
            selectedProfileIndex = 0
        }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "DSH Shell"
        window.minSize = NSSize(width: 640, height: 420)
        window.center()

        tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 1280, height: 860))
        tabView.tabViewType = .topTabsBezelBorder
        tabView.delegate = self
        tabView.autoresizingMask = [.width, .height]
        window.contentView = tabView

        // Toolbar
        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar

        buildMenu()

        restoreState()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Toolbar delegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [profilesMenuIdentifier, addressIdentifier, .flexibleSpace, addTabIdentifier, closeTabIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case profilesMenuIdentifier:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Environment"
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 230, height: 26), pullsDown: false)
            popup.target = self
            popup.action = #selector(profileChanged(_:))
            self.profilePopup = popup
            item.view = popup
            item.minSize = NSSize(width: 160, height: 26)
            item.maxSize = NSSize(width: 320, height: 30)
            rebuildProfilePopup()
            return item
        case addressIdentifier:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Address"
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 460, height: 24))
            field.placeholderString = "https://…"
            field.bezelStyle = .roundedBezel
            field.target = self
            field.action = #selector(addressEntered(_:))
            self.addressField = field
            item.view = field
            item.minSize = NSSize(width: 200, height: 24)
            item.maxSize = NSSize(width: 900, height: 28)
            return item
        case addTabIdentifier:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "New Tab"
            item.paletteLabel = "New Tab"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New tab")
            item.target = self
            item.action = #selector(newTabAction(_:))
            return item
        case closeTabIdentifier:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Close Tab"
            item.paletteLabel = "Close Tab"
            item.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
            item.target = self
            item.action = #selector(closeTabAction(_:))
            return item
        default:
            return nil
        }
    }

    // MARK: Profile popup

    func rebuildProfilePopup() {
        guard let popup = profilePopup else { return }
        popup.removeAllItems()
        popup.addItems(withTitles: ProfileStore.shared.profiles.map { $0.name })
        if selectedProfileIndex < popup.numberOfItems {
            popup.selectItem(at: selectedProfileIndex)
        }
    }

    @objc func profileChanged(_ sender: NSPopUpButton) {
        selectedProfileIndex = sender.indexOfSelectedItem
        UserDefaults.standard.set(selectedProfileIndex, forKey: "selectedProfileIndex")
        if let tab = currentTab, let url = currentProfileURL() {
            tab.webView.load(URLRequest(url: url))
        }
    }

    func currentProfileURL() -> URL? {
        let profiles = ProfileStore.shared.profiles
        guard selectedProfileIndex >= 0, selectedProfileIndex < profiles.count else { return nil }
        return URL(string: profiles[selectedProfileIndex].url)
    }

    // MARK: Address bar

    @objc func addressEntered(_ sender: NSTextField) {
        guard let tab = currentTab else { return }
        var text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return }
        if !text.contains("://") {
            if text.contains(" ") || !text.contains(".") {
                return // don't guess search; harness UIs are URLs
            }
            text = "http://" + text
        }
        guard let url = URL(string: text) else { return }
        tab.webView.load(URLRequest(url: url))
        window.makeFirstResponder(tab.webView)
    }

    // MARK: Tabs

    @objc func newTabAction(_ sender: Any?) {
        addTab(url: currentProfileURL(), select: true)
    }

    @objc func closeTabAction(_ sender: Any?) {
        guard let tab = currentTab else { return }
        closeTab(record: tab)
    }

    func closeTab(record: TabRecord) {
        let wasOnly = tabs.count == 1
        suppressTabSelect = true
        if let idx = tabs.firstIndex(where: { $0 === record }) {
            tabs.remove(at: idx)
        }
        if let item = tabView.tabViewItems.first(where: { $0 === record.tabItem }) {
            tabView.removeTabViewItem(item)
        }
        suppressTabSelect = false
        if wasOnly {
            addTab(url: currentProfileURL(), select: true)
        }
        saveState()
        refreshChrome()
    }

    @discardableResult
    func addTab(url: URL?, select: Bool) -> TabRecord {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        if let effortScript = EffortControlScript.makeUserScript() {
            config.userContentController.addUserScript(effortScript)
        }
        let webView = WKWebView(frame: tabView.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.configuration.preferences.isElementFullscreenEnabled = true

        let tabItem = NSTabViewItem(identifier: UUID().uuidString)
        tabItem.view = webView
        tabItem.label = "New Tab"
        tabView.addTabViewItem(tabItem)

        let record = TabRecord(webView: webView, tabItem: tabItem)
        tabs.append(record)

        record.observationTokens.append(webView.observe(\.url, options: [.new, .initial]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.tabURLChanged(record, webView: wv) }
        })
        record.observationTokens.append(webView.observe(\.title, options: [.new, .initial]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.tabTitleChanged(record, webView: wv) }
        })
        record.observationTokens.append(webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.saveState() }
        })

        if let url = url {
            webView.load(URLRequest(url: url))
        }
        if select {
            tabView.selectTabViewItem(tabItem)
        }
        saveState()
        return record
    }

    func tabURLChanged(_ record: TabRecord, webView: WKWebView) {
        guard let url = webView.url else { return }
        let host = url.host ?? url.absoluteString
        // Label by profile name if the URL matches one, else by host.
        let profiles = ProfileStore.shared.profiles
        var label = host
        for (idx, p) in profiles.enumerated() {
            if let purl = URL(string: p.url), sameOrigin(purl, url) {
                label = p.name
                if !suppressTabSelect { break }
                _ = idx
            }
        }
        record.tabItem.label = label
        if record === currentTab {
            if !(window.firstResponder is NSTextField) {
                addressField?.stringValue = url.absoluteString
            }
            window.title = "DSH Shell — \(label)"
        }
    }

    func tabTitleChanged(_ record: TabRecord, webView: WKWebView) {
        let t = webView.title ?? ""
        guard !t.isEmpty else { return }
        record.tabItem.label = String(t.prefix(28))
    }

    func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        (a.scheme ?? "") == (b.scheme ?? "") && (a.host ?? "") == (b.host ?? "") && (a.port ?? 80) == (b.port ?? 80)
    }

    // MARK: NSTabViewDelegate

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard !suppressTabSelect else { return }
        refreshChrome()
        saveState()
    }

    func refreshChrome() {
        guard let tab = currentTab else { return }
        let url = tab.webView.url
        addressField?.stringValue = url?.absoluteString ?? ""
        window.title = "DSH Shell — \(tab.tabItem.label)"
    }

    // MARK: WKUIDelegate — open _blank links as new tabs

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let record = addTab(url: navigationAction.request.url, select: true)
        return record.webView
    }

    // MARK: State persistence

    func saveState() {
        let urls = tabs.compactMap { $0.webView.url?.absoluteString }
        UserDefaults.standard.set(urls, forKey: "openTabs")
        let sel = tabView.tabViewItems.firstIndex(of: tabView.selectedTabViewItem ?? NSTabViewItem()) ?? 0
        UserDefaults.standard.set(sel, forKey: "activeTab")
    }

    func restoreState() {
        let saved = UserDefaults.standard.stringArray(forKey: "openTabs") ?? []
        if saved.isEmpty {
            addTab(url: currentProfileURL(), select: true)
        } else {
            for s in saved {
                addTab(url: URL(string: s), select: false)
            }
            let active = UserDefaults.standard.integer(forKey: "activeTab")
            if active >= 0, active < tabView.tabViewItems.count {
                suppressTabSelect = true
                tabView.selectTabViewItem(at: active)
                suppressTabSelect = false
            } else if let first = tabView.tabViewItems.first {
                tabView.selectTabViewItem(first)
            }
        }
        refreshChrome()
    }

    // MARK: Profiles manager window

    var profilesWindow: NSWindow?
    var profileRows: [(name: NSTextField, url: NSTextField)] = []

    @objc func manageProfilesAction(_ sender: Any?) {
        if let pw = profilesWindow {
            pw.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        w.title = "Manage Profiles"
        w.isReleasedWhenClosed = false
        w.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 420))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        let scroll = NSScrollView()
        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        content.addSubview(scroll)

        let addButton = NSButton(title: "+ Add Profile", target: self, action: #selector(addProfileRow(_:)))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveProfilesAction(_:)))
        saveButton.keyEquivalent = "\r"
        saveButton.controlSize = .large

        let buttonRow = NSStackView(views: [addButton, NSView(), saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -8),
            buttonRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])

        w.contentView = content
        self.profilesWindow = w
        self.profileRows = []
        for p in ProfileStore.shared.profiles {
            appendProfileRow(to: stack, name: p.name, url: p.url)
        }
        w.makeKeyAndOrderFront(nil)
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

        if let pw = profilesWindow {
            _ = pw // keep reference semantics simple
        }
        profileRows.append((name: nameField, url: urlField))

        nameField.widthAnchor.constraint(equalToConstant: 150).isActive = true
        urlField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
    }

    func makeSeparator() -> NSView {
        let sep = NSBox()
        sep.boxType = .separator
        return sep
    }

    @objc func addProfileRow(_ sender: Any?) {
        guard let stack = profilesWindow?.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first?.documentView as? NSStackView else { return }
        appendProfileRow(to: stack, name: "", url: "")
    }

    @objc func removeProfileRow(_ sender: NSButton) {
        // Walk up to the row stack containing this button and drop its fields.
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
    }

    @objc func saveProfilesAction(_ sender: Any?) {
        var collected: [Profile] = []
        for row in profileRows {
            let n = row.name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var u = row.url.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty, !u.isEmpty else { continue }
            if !u.contains("://") { u = "http://" + u }
            collected.append(Profile(name: n, url: u))
        }
        if collected.isEmpty { return }
        ProfileStore.shared.replace(with: collected)
        if selectedProfileIndex >= collected.count { selectedProfileIndex = 0 }
        UserDefaults.standard.set(selectedProfileIndex, forKey: "selectedProfileIndex")
        rebuildProfilePopup()
        profilesWindow?.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveState()
    }
}

// MARK: - Bootstrap

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
