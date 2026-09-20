import AppKit
import Carbon

public final class HotKeyManager {
    public static let shared = HotKeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    public var onHotKeyPressed: (() -> Void)?
    
    private init() {}
    
    public func registerDefaultHotKey() {
        // 注册 Option + Shift + A (keyCode 0 为 'a')
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            DispatchQueue.main.async {
                HotKeyManager.shared.onHotKeyPressed?()
            }
            return noErr
        }
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            nil
        )
        
        let hotKeyID = EventHotKeyID(signature: OSType(1836021104), id: 1)
        let status = RegisterEventHotKey(
            0, // 'A'
            UInt32(optionKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            print("✅ 全局快捷键 Option + Shift + A 注册成功")
        } else {
            print("⚠️ 全局快捷键注册失败，错误码: \(status)")
        }
    }
}
