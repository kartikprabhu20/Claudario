import AppKit
import ServiceManagement

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var appDelegate: AppDelegate?
    private let settings: MascotSettings

    init(appDelegate: AppDelegate, settings: MascotSettings) {
        self.appDelegate = appDelegate
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            button.image = Self.makeIcon(settings: settings)
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = "Claudario"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)
    }

    /// Re-renders the menu-bar icon from the current variant/color in
    /// settings. Called by AppDelegate via settings change callbacks.
    func refreshIcon() {
        statusItem.button?.image = Self.makeIcon(settings: settings)
    }

    private static func makeIcon(settings: MascotSettings) -> NSImage {
        let variant = MascotVariant(rawValue: settings.variantIndex) ?? .classic
        let color = MascotPalette.colors[settings.colorIndex]
        return MascotIconRenderer.render(variant: variant, color: color, pointSize: 18)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = (appDelegate?.isEnabled ?? false) ? .on : .off
        menu.addItem(enabled)

        if #available(macOS 13.0, *) {
            let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginAtLaunch), keyEquivalent: "")
            login.target = self
            login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            menu.addItem(login)
        }

        menu.addItem(.separator())

        let install = NSMenuItem(title: "Install Claude Code Hooks", action: #selector(installHooks), keyEquivalent: "")
        install.target = self
        menu.addItem(install)

        let uninstall = NSMenuItem(title: "Uninstall Claude Code Hooks", action: #selector(uninstallHooks), keyEquivalent: "")
        uninstall.target = self
        menu.addItem(uninstall)

        menu.addItem(.separator())

        let walk = NSMenuItem(title: "Test: Walk + Jump", action: #selector(testWalkJump), keyEquivalent: "")
        walk.target = self
        menu.addItem(walk)

        let notif = NSMenuItem(title: "Test: Notify", action: #selector(testNotify), keyEquivalent: "")
        notif.target = self
        menu.addItem(notif)

        menu.addItem(.separator())

        let controls = NSMenuItem(title: "Show Controls…", action: #selector(showControls), keyEquivalent: "")
        controls.target = self
        menu.addItem(controls)

        let about = NSMenuItem(title: "About Claudario", action: #selector(about), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        appDelegate?.isEnabled.toggle()
    }

    @objc private func toggleLoginAtLaunch() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                presentError(error, summary: "Couldn't update Launch at Login")
            }
        }
    }

    @objc private func installHooks() {
        do {
            let path = try HookInstaller().install()
            presentInfo(
                "Hooks installed.",
                detail: "Patched: \(path.path)\nClaude Code will now notify Claudario."
            )
        } catch {
            presentError(error, summary: "Hook install failed")
        }
    }

    @objc private func uninstallHooks() {
        do {
            try HookInstaller().uninstall()
            presentInfo("Hooks removed.", detail: "Claude Code will no longer notify Claudario.")
        } catch {
            presentError(error, summary: "Hook uninstall failed")
        }
    }

    @objc private func testWalkJump() {
        guard let router = appDelegate?.router else { return }
        let start = #"{"hook_event_name":"UserPromptSubmit","session_id":"menubar-test"}"#
        router.handle(Data(start.utf8))
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            let stop = #"{"hook_event_name":"Stop","session_id":"menubar-test"}"#
            router.handle(Data(stop.utf8))
        }
    }

    @objc private func testNotify() {
        guard let router = appDelegate?.router else { return }
        let n = #"{"hook_event_name":"Notification","session_id":"menubar-test"}"#
        router.handle(Data(n.utf8))
    }

    @objc private func showControls() {
        let alert = NSAlert()
        alert.messageText = "Claudario Controls"
        
        let activities = [
            ("1", "Idle", "6", "Planning"),
            ("2", "Thinking", "7", "Browsing"),
            ("3", "Reading", "8", "Deep thinking"),
            ("4", "Coding", "9", "Compacting"),
            ("5", "Running", "0", "Dancing")
        ]
        
        var activityRows = ""
        for (n1, name1, n2, name2) in activities {
            let leftSide = "  \(n1)  \(name1)".padding(toLength: 18, withPad: " ", startingAt: 0)
            activityRows += "\(leftSide)\(n2)  \(name2)\n"
        }

        let fullText = """
        Click the mascot to take control. While in control:

          ←  →      Walk left / right
          ↑         Jump with chime
          Esc       Release control

        Activities (test):
        \(activityRows)
        Size:
          ,  or  <        smaller
          .  or  >        larger

        Color:
          c               cycle to next color (10 total)

        Variant:
          v               cycle mascot shape (7 total)

        Esc, click outside, app-switch, or any incoming
        Claude activity releases control.
        """

        // 1. Create a font that is strictly fixed-width
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        
        // 2. Use a label with the fixed-width font
        let textField = NSTextField(labelWithString: fullText)
        textField.font = font
        textField.lineBreakMode = .byWordWrapping
        
        // 3. Add it to the alert
        alert.accessoryView = textField
        alert.informativeText = "" // Clear the default text area
        
        alert.runModal()
    }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Claudario"
        alert.informativeText = "Mascot companion for Claude Code.\nWalks above the Dock while Claude works."
        alert.runModal()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func presentInfo(_ msg: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.informativeText = detail
        alert.runModal()
    }

    private func presentError(_ error: Error, summary: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = summary
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
