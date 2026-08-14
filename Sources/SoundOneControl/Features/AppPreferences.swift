import Foundation
import ServiceManagement

@MainActor
final class AppPreferences: ObservableObject {
  static let shared = AppPreferences()

  @Published var launchAtLogin: Bool {
    didSet {
      guard !isLoading else { return }
      do {
        if launchAtLogin {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
        launchAtLoginError = nil
      } catch {
        launchAtLoginError = error.localizedDescription
        isLoading = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isLoading = false
      }
    }
  }

  @Published private(set) var launchAtLoginError: String?
  @Published var showConnectionNotifications: Bool {
    didSet {
      UserDefaults.standard.set(showConnectionNotifications, forKey: Keys.connectionNotifications)
    }
  }
  @Published var showLowBatteryNotifications: Bool {
    didSet {
      UserDefaults.standard.set(showLowBatteryNotifications, forKey: Keys.lowBatteryNotifications)
    }
  }
  @Published var favoriteEqualizerPresetID: UInt16 {
    didSet {
      UserDefaults.standard.set(
        Int(favoriteEqualizerPresetID), forKey: Keys.favoriteEqualizerPresetID)
    }
  }
  @Published private(set) var customEqualizerAdjustments: [Int]

  private var isLoading = true

  private enum Keys {
    static let connectionNotifications = "showConnectionNotifications"
    static let lowBatteryNotifications = "showLowBatteryNotifications"
    static let favoriteEqualizerPresetID = "favoriteEqualizerPresetID"
    static let customEqualizerAdjustments = "customEqualizerAdjustments"
  }

  private init() {
    launchAtLogin = SMAppService.mainApp.status == .enabled
    showConnectionNotifications =
      UserDefaults.standard.object(forKey: Keys.connectionNotifications) as? Bool ?? true
    showLowBatteryNotifications =
      UserDefaults.standard.object(forKey: Keys.lowBatteryNotifications) as? Bool ?? true
    let storedPreset =
      UserDefaults.standard.object(forKey: Keys.favoriteEqualizerPresetID) as? Int ?? 0
    favoriteEqualizerPresetID = UInt16(clamping: storedPreset)
    let storedAdjustments = UserDefaults.standard.array(forKey: Keys.customEqualizerAdjustments)?
      .compactMap { ($0 as? NSNumber)?.intValue }
    customEqualizerAdjustments = Self.normalizedCustomAdjustments(storedAdjustments ?? [])
    isLoading = false
  }

  func storeCustomEqualizerAdjustments(_ adjustments: [Int]) {
    let normalized = Self.normalizedCustomAdjustments(adjustments)
    guard normalized != customEqualizerAdjustments else { return }
    customEqualizerAdjustments = normalized
    UserDefaults.standard.set(normalized, forKey: Keys.customEqualizerAdjustments)
  }

  private static func normalizedCustomAdjustments(_ adjustments: [Int]) -> [Int] {
    let fallback = Array(repeating: 0, count: 8) + [-120, -120]
    guard adjustments.count == 10 else { return fallback }
    return adjustments.map { $0.clamped(to: -120...120) }
  }
}
