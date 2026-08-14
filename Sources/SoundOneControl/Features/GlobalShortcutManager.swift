import Carbon
import Foundation

@MainActor
final class GlobalShortcutManager {
  enum Action: UInt32, CaseIterable {
    case cycleAmbient = 1
    case toggleDolby = 2
    case favoriteEqualizer = 3
  }

  private static var shared: GlobalShortcutManager?
  private var hotKeys: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?
  private weak var controller: HeadphoneController?

  init(controller: HeadphoneController) {
    self.controller = controller
    Self.shared = self
  }

  deinit {
    for hotKey in hotKeys {
      _ = UnregisterEventHotKey(hotKey)
    }
    if let handler { RemoveEventHandler(handler) }
  }

  func register() {
    guard hotKeys.isEmpty else { return }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ in
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &identifier
        )
        guard status == noErr else { return status }
        Task { @MainActor in
          GlobalShortcutManager.shared?.perform(Action(rawValue: identifier.id))
        }
        return noErr
      },
      1,
      &eventType,
      nil,
      &handler
    )

    // Option-Command-A/D/E avoids overriding familiar system and application shortcuts.
    register(.cycleAmbient, keyCode: UInt32(kVK_ANSI_A))
    register(.toggleDolby, keyCode: UInt32(kVK_ANSI_D))
    register(.favoriteEqualizer, keyCode: UInt32(kVK_ANSI_E))
  }

  private func register(_ action: Action, keyCode: UInt32) {
    var reference: EventHotKeyRef?
    let signature = OSType(0x534f_4e45)  // "SONE"
    let identifier = EventHotKeyID(signature: signature, id: action.rawValue)
    let result = RegisterEventHotKey(
      keyCode,
      UInt32(optionKey | cmdKey),
      identifier,
      GetApplicationEventTarget(),
      0,
      &reference
    )
    if result == noErr, let reference { hotKeys.append(reference) }
  }

  private func perform(_ action: Action?) {
    guard let controller, controller.state != nil, let action else { return }
    switch action {
    case .cycleAmbient:
      controller.cycleAmbientMode()
    case .toggleDolby:
      controller.toggleDolby()
    case .favoriteEqualizer:
      guard
        let preset = EqualizerPreset.all.first(where: {
          $0.id == AppPreferences.shared.favoriteEqualizerPresetID
        })
      else { return }
      controller.setEqualizerPreset(preset)
    }
  }
}
