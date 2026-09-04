import AppKit
import CoreSpotlight

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var watcher: BookmarksWatcher?

    private let statusMenuItem = NSMenuItem(title: "Not indexed yet", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(
        title: "Launch at Login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )

    private lazy var timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        let watcher = BookmarksWatcher { [weak self] in
            DispatchQueue.main.async { self?.reindex() }
        }
        watcher.start(files: ChromeBookmarksReader.bookmarkFiles())
        self.watcher = watcher

        reindex()
    }

    // MARK: - Spotlight result activation

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void
    ) -> Bool {
        handle(userActivity)
    }

    @discardableResult
    private func handle(_ userActivity: NSUserActivity) -> Bool {
        guard
            userActivity.activityType == CSSearchableItemActionType,
            let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
            let url = SpotlightIndexer.url(forItemIdentifier: identifier)
        else {
            return false
        }
        NSWorkspace.shared.open(url)
        return true
    }

    // MARK: - Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "bookmark.fill",
            accessibilityDescription: "Chrome Bookmarks Spotlight"
        )

        let menu = NSMenu()

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        addItem(to: menu, title: "Reindex Now", action: #selector(reindexNow), key: "r")
        addItem(to: menu, title: "Open Chrome Bookmark Manager", action: #selector(openBookmarkManager), key: "")
        menu.addItem(.separator())

        launchAtLoginItem.target = self
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())

        addItem(to: menu, title: "Quit", action: #selector(quit), key: "q")

        statusItem.menu = menu
    }

    private func addItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        key: String,
        target: AnyObject? = nil
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func reindexNow() {
        reindex()
    }

    @objc private func openBookmarkManager() {
        if let url = URL(string: "chrome://bookmarks") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        let shouldEnable = !LaunchAtLogin.isEnabled
        LaunchAtLogin.setEnabled(shouldEnable)
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    // MARK: - Indexing

    private func reindex() {
        statusMenuItem.title = "Indexing…"
        let bookmarks = ChromeBookmarksReader.readAll()

        SpotlightIndexer.reindex(bookmarks) { [weak self] count, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.statusMenuItem.title = "Error: \(error.localizedDescription)"
                } else {
                    let time = self.timestampFormatter.string(from: Date())
                    self.statusMenuItem.title = "\(count) bookmarks indexed · \(time)"
                }
            }
        }
    }
}
