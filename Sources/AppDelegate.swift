import AppKit
import SwiftUI
import Combine

/// 面板尺寸（弹出框与悬浮面板共用）
enum PanelLayout {
    static let width: CGFloat = 380
    static let height: CGFloat = 500
}

public final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var floatingPanel: NSPanel?
    private let manager = AppManager()
    private var cancellables = Set<AnyCancellable>()
    private var panelClickMonitor: Any?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        setupBindings()
        setupHotKey()
    }

    // MARK: - 状态栏图标

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let img = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: "后台应用管家")?.withSymbolConfiguration(config)

            button.image = img
            button.imagePosition = .imageLeading
            button.title = " \(manager.menuBarAppCount)"
            button.toolTip = "菜单栏应用管家（右键查看更多选项）"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: PanelLayout.width, height: PanelLayout.height)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(manager: manager))
        self.popover = popover
    }

    private func setupBindings() {
        // 菜单栏文字 = 应用数量，开启「显示网速」时追加实时网速
        Publishers.CombineLatest(manager.$menuBarAppCount, SystemMonitor.shared.$menuBarSpeedText)
            .map { count, speed in
                speed.map { " \(count)  \($0)" } ?? " \(count)"
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title in
                self?.statusItem?.button?.title = title
            }
            .store(in: &cancellables)
    }

    private func setupHotKey() {
        HotKeyManager.shared.onHotKeyPressed = { [weak self] in
            self?.toggleViaHotKey()
        }
        manager.applySavedHotKey()
    }

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            closePopover()
        } else {
            closeFloatingPanel()
            showPopover(relativeTo: button, popover: popover)
        }
    }

    // MARK: - 右键菜单

    private func showStatusMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "打开面板", action: #selector(openPanelFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = manager.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        let speedItem = NSMenuItem(title: "菜单栏显示实时网速", action: #selector(toggleMenuBarSpeed), keyEquivalent: "")
        speedItem.target = self
        speedItem.state = SystemMonitor.shared.showsSpeedInMenuBar ? .on : .off
        menu.addItem(speedItem)

        let hotKeyMenu = NSMenu()
        for preset in HotKeyPreset.all {
            let item = NSMenuItem(title: preset.title, action: #selector(selectHotKey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            item.state = (preset == manager.hotKeyPreset) ? .on : .off
            hotKeyMenu.addItem(item)
        }
        let hotKeyItem = NSMenuItem(title: "全局快捷键", action: nil, keyEquivalent: "")
        hotKeyItem.submenu = hotKeyMenu
        menu.addItem(hotKeyItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 菜单栏应用管家", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        // 临时挂载菜单并模拟点击，弹出后立即卸载，左键仍然打开面板
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openPanelFromMenu() {
        guard let button = statusItem?.button, let popover = popover else { return }
        closeFloatingPanel()
        showPopover(relativeTo: button, popover: popover)
    }

    @objc private func toggleMenuBarSpeed() {
        SystemMonitor.shared.showsSpeedInMenuBar.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        manager.setLaunchAtLogin(!manager.launchAtLogin)
    }

    @objc private func selectHotKey(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        manager.applyHotKey(HotKeyPreset.preset(withId: id))
    }

    // MARK: - 弹出框

    private func showPopover(relativeTo button: NSStatusBarButton, popover: NSPopover) {
        manager.setPanelVisible(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    public func popoverDidClose(_ notification: Notification) {
        if floatingPanel?.isVisible != true {
            manager.setPanelVisible(false)
        }
    }

    private func toggleViaHotKey() {
        // 如果面板已在展示，则关闭
        if let popover = popover, popover.isShown {
            closePopover()
            return
        }
        if let panel = floatingPanel, panel.isVisible {
            closeFloatingPanel()
            return
        }

        // 检查状态栏按钮是否在可见屏幕范围内（未被刘海或其他图标挤出）
        if let button = statusItem?.button,
           let window = button.window,
           let screen = window.screen,
           let popover = popover {
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            var isVisible = window.occlusionState.contains(.visible) &&
                screen.frame.contains(NSPoint(x: buttonFrame.midX, y: buttonFrame.midY))
            // 刘海屏：图标被挤到刘海后面时同样视为不可见
            if isVisible, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                // 兼容相对/绝对两种坐标：左侧区域起点等于屏幕起点时说明已经是绝对坐标
                let offset = (left.minX == screen.frame.minX) ? 0 : screen.frame.minX
                let notchMinX = offset + left.maxX
                let notchMaxX = offset + right.minX
                if buttonFrame.maxX > notchMinX && buttonFrame.minX < notchMaxX {
                    isVisible = false
                }
            }
            if isVisible {
                showPopover(relativeTo: button, popover: popover)
                return
            }
        }

        // 状态栏图标被遮挡或在屏幕外：弹出无标题栏悬浮面板
        showFloatingPanel()
    }

    // MARK: - 悬浮面板

    private func showFloatingPanel() {
        closeFloatingPanel()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.setContentSize(NSSize(width: PanelLayout.width, height: PanelLayout.height))
        panel.contentViewController = NSHostingController(rootView: PopoverView(manager: manager))

        // 放置在鼠标所在屏幕的右上角安全区域
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            let x = visibleFrame.maxX - PanelLayout.width - 20
            let y = visibleFrame.maxY - PanelLayout.height - 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        manager.setPanelVisible(true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.floatingPanel = panel
        startMonitoringPanelOutsideClicks()
    }

    private func closeFloatingPanel() {
        guard let panel = floatingPanel else { return }
        panel.close()
        floatingPanel = nil
        stopMonitoringPanelOutsideClicks()
        if popover?.isShown != true {
            manager.setPanelVisible(false)
        }
    }

    /// 悬浮面板没有 transient 行为，点击外部时手动关闭
    private func startMonitoringPanelOutsideClicks() {
        stopMonitoringPanelOutsideClicks()
        panelClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let panel = self.floatingPanel, panel.isVisible else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.closeFloatingPanel()
            }
        }
    }

    private func stopMonitoringPanelOutsideClicks() {
        if let monitor = panelClickMonitor {
            NSEvent.removeMonitor(monitor)
            panelClickMonitor = nil
        }
    }
}
