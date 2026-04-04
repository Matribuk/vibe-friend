import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var petController: PetController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        petController = PetController()
        petController?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        petController?.stop()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            if let url = Bundle.module.url(forResource: "claude", withExtension: "svg"),
               let icon = NSImage(contentsOf: url) {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "VibeFriend")
            }
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit VibeFriend", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
