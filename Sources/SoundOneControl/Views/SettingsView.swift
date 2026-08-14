import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var controller: HeadphoneController
  @EnvironmentObject private var preferences: AppPreferences
  @State private var selection = SettingsPane.sound

  var body: some View {
    NavigationSplitView {
      List(SettingsPane.allCases, selection: $selection) { pane in
        Label(pane.title, systemImage: pane.symbol)
          .tag(pane)
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
    } detail: {
      VStack(spacing: 0) {
        SettingsPageHeader(pane: selection)
        Divider()
        selectedSettingsView
      }
    }
    .navigationSplitViewStyle(.prominentDetail)
    .frame(minWidth: 680, minHeight: 500)
  }

  @ViewBuilder
  private var selectedSettingsView: some View {
    switch selection {
    case .sound:
      SoundSettingsView(controller: controller)
    case .equalizer:
      EqualizerSettingsView(controller: controller)
        .environmentObject(preferences)
    case .headphones:
      HeadphoneSettingsView(controller: controller)
    case .app:
      AppSettingsView(controller: controller)
        .environmentObject(preferences)
    }
  }
}

private struct SettingsPageHeader: View {
  let pane: SettingsPane

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(pane.title)
        .font(.headline)
      Text(pane.subtitle)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 30)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
  case sound
  case equalizer
  case headphones
  case app

  var id: Self { self }

  var title: String {
    switch self {
    case .sound: "Sound"
    case .equalizer: "Equalizer"
    case .headphones: "Headphones"
    case .app: "App"
    }
  }

  var subtitle: String {
    switch self {
    case .sound: "Ambient modes and listening effects"
    case .equalizer: "Presets and your custom sound profile"
    case .headphones: "Device behavior, protection, and connections"
    case .app: "Startup, notifications, and shortcuts"
    }
  }

  var symbol: String {
    switch self {
    case .sound: "waveform"
    case .equalizer: "slider.vertical.3"
    case .headphones: "headphones"
    case .app: "gearshape"
    }
  }
}

private struct SoundSettingsView: View {
  @ObservedObject var controller: HeadphoneController

  var body: some View {
    Form {
      if let state = controller.state {
        Section("Ambient sound") {
          LabeledContent("Mode") {
            HStack(spacing: 6) {
              ForEach(AmbientMode.allCases) { mode in
                AmbientModeButton(
                  mode: mode,
                  isSelected: mode == state.soundModes.ambient,
                  fillsWidth: false
                ) { controller.setAmbientMode(mode) }
              }
            }
          }

          if state.soundModes.ambient == .noiseCanceling {
            Picker(
              "Noise canceling",
              selection: Binding(
                get: { state.soundModes.noiseCancelingMode },
                set: controller.setNoiseCancelingMode
              )
            ) {
              ForEach(NoiseCancelingMode.allCases) { mode in Text(mode.title).tag(mode) }
            }

            if state.soundModes.noiseCancelingMode == .custom {
              LevelControl(
                title: "ANC strength",
                value: state.soundModes.customNoiseCancelingLevel,
                set: controller.setNoiseCancelingLevel
              )
            } else {
              LabeledContent(
                "Adaptive level", value: "\(state.soundModes.adaptiveNoiseCancelingLevel) of 5")
            }
          }

          if state.soundModes.ambient == .transparency {
            LevelControl(
              title: "Transparency strength",
              value: state.soundModes.transparencyLevel,
              set: controller.setTransparencyLevel
            )
          }

          Toggle(
            "Wind noise reduction",
            isOn: Binding(
              get: { state.soundModes.windNoiseReduction },
              set: controller.setWindNoiseReduction
            ))
        }

        Section("Effects") {
          Toggle("Dolby Audio", isOn: Binding(get: { state.dolbyAudio }, set: controller.setDolby))
          Toggle(
            "Sidetone during calls",
            isOn: Binding(get: { state.sideTone }, set: controller.setSideTone))
        }

        Section("NC button cycle") {
          CycleToggleGroup(state: state, controller: controller)
        }
      } else {
        UnavailableSettingsView(controller: controller)
      }
    }
    .formStyle(.grouped)
    .disabled(controller.isApplyingChange)
  }
}

private struct LevelControl: View {
  let title: String
  let value: Int
  let set: (Int) -> Void

  var body: some View {
    LabeledContent(title) {
      Picker(title, selection: Binding(get: { value }, set: set)) {
        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
      }
      .labelsHidden()
      .fixedSize()
      .frame(width: 90, alignment: .trailing)
    }
  }
}

private struct CycleToggleGroup: View {
  let state: SpaceOneProState
  @ObservedObject var controller: HeadphoneController

  var body: some View {
    Toggle("Noise Canceling", isOn: cycleBinding(\.noiseCanceling))
    Toggle("Transparency", isOn: cycleBinding(\.transparency))
    Toggle("Normal", isOn: cycleBinding(\.normal))
    Text("Keep at least two modes enabled so the NC button has something to cycle between.")
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  private func cycleBinding(_ keyPath: WritableKeyPath<AmbientCycle, Bool>) -> Binding<Bool> {
    Binding(
      get: { state.ambientCycle[keyPath: keyPath] },
      set: { newValue in
        var cycle = state.ambientCycle
        cycle[keyPath: keyPath] = newValue
        let count = [cycle.noiseCanceling, cycle.transparency, cycle.normal].filter { $0 }.count
        guard count >= 2 else { return }
        controller.setAmbientCycle(cycle)
      }
    )
  }
}

private struct EqualizerSettingsView: View {
  @ObservedObject var controller: HeadphoneController
  @EnvironmentObject private var preferences: AppPreferences
  @State private var draft: [Int] = Array(repeating: 0, count: 10)

  private let bandNames = ["100", "200", "400", "800", "1.6k", "3.2k", "6.4k", "12.8k"]

  var body: some View {
    Form {
      if let state = controller.state {
        Section("Profile") {
          Picker(
            "Preset",
            selection: Binding(
              get: { state.equalizerPresetID },
              set: controller.setEqualizerProfile
            )
          ) {
            Text("Custom").tag(SpaceOneProState.customEqualizerID)
            ForEach(EqualizerPreset.all) { preset in Text(preset.name).tag(preset.id) }
          }
        }

        Section("Custom equalizer") {
          Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(0..<8, id: \.self) { index in
              GridRow {
                Text("\(bandNames[index]) Hz")
                  .font(.callout.monospacedDigit())
                  .frame(width: 70, alignment: .trailing)
                Slider(
                  value: Binding(
                    get: { Double(draft[index]) },
                    set: { draft[index] = Int($0.rounded()) }
                  ),
                  in: -120...120,
                  step: 10
                )
                .frame(minWidth: 300)
                .accessibilityLabel("\(bandNames[index]) hertz")
                .accessibilityValue(formatAdjustment(draft[index]))
                Text(formatAdjustment(draft[index]))
                  .font(.callout.monospacedDigit())
                  .frame(width: 58, alignment: .trailing)
              }
            }
          }
          .padding(.vertical, 8)

          HStack {
            Button("Reset Flat") {
              for index in 0..<8 { draft[index] = 0 }
            }
            Spacer()
            Button("Apply Custom EQ") {
              controller.setCustomEqualizer(draft)
            }
            .buttonStyle(.borderedProminent)
          }
        }
      } else {
        UnavailableSettingsView(controller: controller)
      }
    }
    .formStyle(.grouped)
    .disabled(controller.isApplyingChange)
    .onAppear { syncDraft() }
    .onChange(of: controller.state?.equalizerPresetID) { _, _ in syncDraft() }
    .onChange(of: controller.state?.equalizerAdjustments) { _, _ in
      guard controller.state?.equalizerPresetID == SpaceOneProState.customEqualizerID else {
        return
      }
      syncDraft()
    }
  }

  private func syncDraft() {
    if controller.state?.equalizerPresetID == SpaceOneProState.customEqualizerID,
      let adjustments = controller.state?.equalizerAdjustments,
      adjustments.count == 10
    {
      draft = adjustments
    } else {
      draft = preferences.customEqualizerAdjustments
    }
  }

  private func formatAdjustment(_ value: Int) -> String {
    String(format: "%+.0f dB", Double(value) / 10)
  }
}

private struct HeadphoneSettingsView: View {
  @ObservedObject var controller: HeadphoneController

  var body: some View {
    Form {
      if let state = controller.state {
        Section("Daily controls") {
          Toggle(
            "Double-press NC button for BassUp",
            isOn: Binding(
              get: { state.buttonDoublePressBassUp },
              set: controller.setButtonBassUp
            ))
        }

        Section("Automatic power off") {
          Toggle(
            "Power off when idle",
            isOn: Binding(
              get: { state.autoPowerOff.enabled },
              set: {
                controller.setAutoPowerOff(
                  enabled: $0, durationIndex: state.autoPowerOff.durationIndex)
              }
            ))
          Picker(
            "After",
            selection: Binding(
              get: { state.autoPowerOff.durationIndex },
              set: {
                controller.setAutoPowerOff(enabled: state.autoPowerOff.enabled, durationIndex: $0)
              }
            )
          ) {
            ForEach(0..<8, id: \.self) { index in Text(durationLabel(index)).tag(index) }
          }
          .disabled(!state.autoPowerOff.enabled)
        }

        Section("Hearing protection") {
          Toggle(
            "Limit high volume",
            isOn: Binding(
              get: { state.volumeLimit.enabled },
              set: { controller.setVolumeLimit(enabled: $0, decibels: state.volumeLimit.decibels) }
            ))
          Picker(
            "Maximum",
            selection: Binding(
              get: { state.volumeLimit.decibels },
              set: { controller.setVolumeLimit(enabled: state.volumeLimit.enabled, decibels: $0) }
            )
          ) {
            ForEach(Array(stride(from: 75, through: 100, by: 5)), id: \.self) {
              Text("\($0) dB").tag($0)
            }
          }
          .disabled(!state.volumeLimit.enabled)
          Picker(
            "Meter refresh",
            selection: Binding(
              get: { state.volumeLimit.refreshRate },
              set: controller.setVolumeRefreshRate
            )
          ) {
            ForEach(DecibelRefreshRate.allCases) { Text($0.title).tag($0) }
          }
        }

        Section("Multipoint") {
          Toggle(
            "Connect to two devices",
            isOn: Binding(
              get: { state.multipointEnabled },
              set: controller.setMultipoint
            ))
          if state.multipointEnabled {
            ForEach(controller.multipointDevices) { device in
              HStack {
                VStack(alignment: .leading) {
                  Text(device.name.isEmpty ? "Unknown device" : device.name)
                  Text(device.addressString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(device.isConnected ? "Disconnect" : "Connect") {
                  controller.setMultipointDevice(device, connected: !device.isConnected)
                }
                Menu {
                  Button("Forget Device", role: .destructive) {
                    controller.forgetMultipointDevice(device)
                  }
                } label: {
                  Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
              }
            }
          }
        }

        Section("Capabilities") {
          LabeledContent("LDAC", value: state.ldac ? "Enabled for Android" : "Android only")
          LabeledContent("Wear detection", value: "Not exposed by firmware")
        }

        Section("Device") {
          LabeledContent("Battery", value: "\(state.batteryPercent)%")
          LabeledContent("Firmware", value: state.firmwareVersion)
          LabeledContent("Serial number", value: state.serialNumber)
        }
      } else {
        UnavailableSettingsView(controller: controller)
      }
    }
    .formStyle(.grouped)
    .disabled(controller.isApplyingChange)
  }

  private func durationLabel(_ index: Int) -> String {
    let minutes = (index + 1) * 30
    return minutes < 60
      ? "\(minutes) minutes"
      : minutes % 60 == 0 ? "\(minutes / 60) hours" : "\(minutes / 60) hr \(minutes % 60) min"
  }
}

private struct AppSettingsView: View {
  @ObservedObject var controller: HeadphoneController
  @EnvironmentObject private var preferences: AppPreferences

  var body: some View {
    Form {
      Section("Startup") {
        Toggle("Launch SoundOne Control at login", isOn: $preferences.launchAtLogin)
        if let error = preferences.launchAtLoginError {
          Text(error).font(.caption).foregroundStyle(.red)
        }
        Text("The menu-bar icon appears only while Space One Pro is connected.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Notifications") {
        Toggle("Connection changes", isOn: $preferences.showConnectionNotifications)
        Toggle("Low battery", isOn: $preferences.showLowBatteryNotifications)
      }

      Section("Keyboard shortcuts") {
        LabeledContent("Cycle ambient mode", value: "⌥⌘A")
        LabeledContent("Toggle Dolby Audio", value: "⌥⌘D")
        LabeledContent("Apply favorite EQ", value: "⌥⌘E")
        Picker("Favorite EQ", selection: $preferences.favoriteEqualizerPresetID) {
          ForEach(EqualizerPreset.all) { preset in Text(preset.name).tag(preset.id) }
        }
      }

      Section("Connection") {
        Button("Refresh Headphone State", action: controller.refresh)
        Button("Disconnect Headphones", role: .destructive, action: controller.disconnectHeadphones)
      }

      Section("About") {
        LabeledContent("SoundOne Control", value: "0.1.0")
        Text("Unofficial, open-source software. Not affiliated with Soundcore or Anker.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}

private struct UnavailableSettingsView: View {
  @ObservedObject var controller: HeadphoneController

  var body: some View {
    ContentUnavailableView {
      Label("Headphones unavailable", systemImage: "headphones")
    } description: {
      Text("Connect Space One Pro over Bluetooth, then try again.")
    } actions: {
      Button("Try Again", action: controller.reconnect)
    }
  }
}
