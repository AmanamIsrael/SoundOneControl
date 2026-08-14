import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
  private var lowBatteryNotified = false

  private var center: UNUserNotificationCenter { .current() }

  func requestAuthorization() {
    Task {
      _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
  }

  func connected(batteryPercent: Int) {
    guard AppPreferences.shared.showConnectionNotifications else { return }
    send(title: "Space One Pro connected", body: "Battery is at \(batteryPercent)%.")
  }

  func disconnected() {
    lowBatteryNotified = false
    guard AppPreferences.shared.showConnectionNotifications else { return }
    send(
      title: "Space One Pro disconnected", body: "SoundOne Control will reconnect automatically.")
  }

  func checkLowBattery(_ percent: Int) {
    guard AppPreferences.shared.showLowBatteryNotifications else { return }
    if percent <= 20, !lowBatteryNotified {
      lowBatteryNotified = true
      send(title: "Space One Pro battery low", body: "Battery is at \(percent)%.")
    } else if percent > 30 {
      lowBatteryNotified = false
    }
  }

  private func send(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
  }
}
