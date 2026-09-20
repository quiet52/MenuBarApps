import AppKit
import SwiftUI
import Combine

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var floatingPanel: NSPanel?
    private let manager = AppManager()
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusItem()
        setupPopover()
        setupBindings()
        setupHotKey()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let img = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: "后台应用管家")?.withSymbolConfiguration(config)
            
            button.image = img
            button.imagePosition = .imageLeading
            button.title = " \(manager.runningApps.count)"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView(manager: manager))
        self.popover = popover
    }
    
    private func setupBindings() {
        manager.$runningApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                self?.updateBadge(count: apps.count)
            }
            .store(in: &cancellables)
    }
    
    private func updateBadge(count: Int) {
        guard let button = statusItem?.button else { return }
        button.title = " \(count)"
    }
    
    private func setupHotKey() {
        HotKeyManager.shared.onHotKeyPressed = { [weak self] in
            self?.toggleViaHotKey()
        }
        HotKeyManager.shared.registerDefaultHotKey()
    }
    
    @objc private func statusItemClicked(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover = popover else { return }
        
        if popover.isShown {
            closePopover()
        } else {
            closeFloatingPanel()
            manager.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            startMonitoringOutsideClicks()
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
        
        manager.refresh()
        
        // 检查状态栏按钮是否在可见屏幕范围内（未被刘海或屏幕遮挡）
        if let button = statusItem?.button,
           let window = button.window,
           let screen = window.screen {
            let buttonFrame = window.convertToScreen(button.bounds)
            let isVisibleOnScreen = screen.visibleFrame.intersects(buttonFrame)
            
            if isVisibleOnScreen, let popover = popover {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
                startMonitoringOutsideClicks()
                return
            }
        }
        
        // 如果状态栏图标被遮挡或在屏幕外，则弹出优雅的无标题栏悬浮面板
        showFloatingPanel()
    }
    
    private func showFloatingPanel() {
        closeFloatingPanel()
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
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
        panel.setContentSize(NSSize(width: 340, height: 480))
        
        let hosting = NSHostingController(rootView: PopoverView(manager: manager))
        panel.contentViewController = hosting
        
        // 放置在当前主屏幕右上角安全区域
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.maxX - 360
            let y = visibleFrame.maxY - 500
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }
        
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.floatingPanel = panel
        startMonitoringOutsideClicks()
    }
    
    private func closePopover() {
        popover?.performClose(nil)
        stopMonitoringOutsideClicks()
    }
    
    private func closeFloatingPanel() {
        floatingPanel?.close()
        floatingPanel = nil
        stopMonitoringOutsideClicks()
    }
    
    private func startMonitoringOutsideClicks() {
        stopMonitoringOutsideClicks()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }
            if let popover = self.popover, popover.isShown {
                self.closePopover()
            }
            if let panel = self.floatingPanel, panel.isVisible {
                let clickPoint = NSEvent.mouseLocation
                if !panel.frame.contains(clickPoint) {
                    self.closeFloatingPanel()
                }
            }
        }
    }
    
    private func stopMonitoringOutsideClicks() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
