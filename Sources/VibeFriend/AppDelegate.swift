import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var petController: PetController?
    private var statusItem: NSStatusItem?
    private var monochromeItem: NSMenuItem?
    private var sizeSlider: NSSlider?

    private static let monochromeKey = "monochrome"
    private static let scaleKey = "petScale"
    private static let defaultScale: CGFloat = 1.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        let controller = PetController()
        controller.isMonochrome = UserDefaults.standard.bool(forKey: Self.monochromeKey)
        let savedScale = UserDefaults.standard.object(forKey: Self.scaleKey) as? CGFloat ?? Self.defaultScale
        controller.petScale = savedScale
        petController = controller
        controller.start()
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

        let isMonochrome = UserDefaults.standard.bool(forKey: Self.monochromeKey)
        let monoItem = NSMenuItem(title: "Monochrome", action: #selector(toggleMonochrome), keyEquivalent: "")
        monoItem.state = isMonochrome ? .on : .off
        monochromeItem = monoItem

        let sliderItem = makeSizeSliderItem()

        let menu = NSMenu()
        menu.addItem(monoItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(sliderItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit VibeFriend", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func makeSizeSliderItem() -> NSMenuItem {
        let savedScale = UserDefaults.standard.object(forKey: Self.scaleKey) as? CGFloat ?? Self.defaultScale

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 36))

        let label = NSTextField(labelWithString: "Size")
        label.frame = NSRect(x: 14, y: 10, width: 36, height: 16)
        label.font = .menuFont(ofSize: 13)
        container.addSubview(label)

        let slider = NSSlider(frame: NSRect(x: 54, y: 8, width: 132, height: 20))
        slider.minValue = 0.5
        slider.maxValue = 2.0
        slider.doubleValue = Double(savedScale)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sizeSliderChanged(_:))
        sizeSlider = slider
        container.addSubview(slider)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    @objc private func toggleMonochrome() {
        let newValue = !(petController?.isMonochrome ?? false)
        petController?.isMonochrome = newValue
        monochromeItem?.state = newValue ? .on : .off
        UserDefaults.standard.set(newValue, forKey: Self.monochromeKey)
    }

    @objc private func sizeSliderChanged(_ sender: NSSlider) {
        let scale = CGFloat(sender.doubleValue)
        petController?.petScale = scale
        UserDefaults.standard.set(scale, forKey: Self.scaleKey)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
