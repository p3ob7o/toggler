import Carbon.HIToolbox
import Foundation

final class HotKeyManager {
    private struct RegisteredHotKey {
        let reference: EventHotKeyRef
        let binding: ShortcutBinding
    }

    private let registrationSignature = OSType("TGLR")
    private let errorHandler: @MainActor (String) -> Void
    private var eventHandler: EventHandlerRef?
    private var registeredHotKeys: [UInt32: RegisteredHotKey] = [:]
    private var action: (@MainActor (ShortcutBinding) -> Void)?
    private var nextIdentifier: UInt32 = 1

    init(errorHandler: @escaping @MainActor (String) -> Void) {
        self.errorHandler = errorHandler
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(_ bindings: [ShortcutBinding], action: @escaping @MainActor (ShortcutBinding) -> Void) {
        unregisterAll()
        self.action = action
        nextIdentifier = 1

        for binding in bindings {
            register(binding)
        }
    }

    func unregisterAll() {
        for registered in registeredHotKeys.values {
            UnregisterEventHotKey(registered.reference)
        }

        registeredHotKeys.removeAll()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else {
                return OSStatus(eventNotHandledErr)
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr else {
                return status
            }

            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleHotKey(id: hotKeyID.id)
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        if status != noErr {
            reportError("Could not install keyboard shortcut handler: \(status)")
        }
    }

    private func register(_ binding: ShortcutBinding) {
        let identifier = EventHotKeyID(signature: registrationSignature, id: nextIdentifier)
        var hotKeyReference: EventHotKeyRef?

        let status = RegisterEventHotKey(
            binding.shortcut.keyCode,
            binding.shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        guard status == noErr, let hotKeyReference else {
            reportError("Could not register \(binding.shortcut.displayValue): \(hotKeyErrorMessage(status))")
            return
        }

        registeredHotKeys[identifier.id] = RegisteredHotKey(reference: hotKeyReference, binding: binding)
        nextIdentifier += 1
    }

    private func handleHotKey(id: UInt32) {
        guard let binding = registeredHotKeys[id]?.binding else {
            return
        }

        let action = action
        Task { @MainActor in
            action?(binding)
        }
    }

    private func reportError(_ message: String) {
        let errorHandler = errorHandler
        Task { @MainActor in
            errorHandler(message)
        }
    }

    private func hotKeyErrorMessage(_ status: OSStatus) -> String {
        switch status {
        case OSStatus(eventHotKeyExistsErr):
            return "that shortcut is already registered by another app"
        case OSStatus(eventHotKeyInvalidErr):
            return "invalid shortcut"
        default:
            return "Carbon error \(status)"
        }
    }
}

private extension OSType {
    init(_ string: String) {
        let scalars = Array(string.unicodeScalars.prefix(4))
        self = scalars.reduce(UInt32(0)) { result, scalar in
            (result << 8) + scalar.value
        }
    }
}
