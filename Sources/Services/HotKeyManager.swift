import AppKit
import Carbon

/// 可选的全局快捷键组合
public struct HotKeyPreset: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let keyCode: UInt32
    public let modifiers: UInt32

    public static let all: [HotKeyPreset] = [
        HotKeyPreset(id: "optShiftA", title: "⌥⇧A", keyCode: 0, modifiers: UInt32(optionKey | shiftKey)),
        HotKeyPreset(id: "ctrlOptA", title: "⌃⌥A", keyCode: 0, modifiers: UInt32(controlKey | optionKey)),
        HotKeyPreset(id: "ctrlOptM", title: "⌃⌥M", keyCode: 46, modifiers: UInt32(controlKey | optionKey)),
        HotKeyPreset(id: "ctrlOptSpace", title: "⌃⌥Space", keyCode: 49, modifiers: UInt32(controlKey | optionKey))
    ]

    public static let defaultPreset = all[0]

    public static func preset(withId id: String?) -> HotKeyPreset {
        return all.first(where: { $0.id == id }) ?? defaultPreset
    }
}

public final class HotKeyManager {
    public static let shared = HotKeyManager()

    private let defaultsKey = "com.quiet52.MenuBarApps.hotKeyPreset"
    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false
    public var onHotKeyPressed: (() -> Void)?

    private init() {}

    public var savedPreset: HotKeyPreset {
        return HotKeyPreset.preset(withId: UserDefaults.standard.string(forKey: defaultsKey))
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                HotKeyManager.shared.onHotKeyPressed?()
            }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
        handlerInstalled = (status == noErr)
    }

    /// 注册（或切换）全局快捷键。返回 false 表示该组合已被其他应用占用。
    @discardableResult
    public func register(_ preset: HotKeyPreset) -> Bool {
        installHandlerIfNeeded()

        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }

        let hotKeyID = EventHotKeyID(signature: OSType(1836021104), id: 1)
        let status = RegisterEventHotKey(
            preset.keyCode,
            preset.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        UserDefaults.standard.set(preset.id, forKey: defaultsKey)
        return status == noErr
    }
}
