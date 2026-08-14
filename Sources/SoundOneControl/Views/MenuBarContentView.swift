import AppKit
import SwiftUI

struct MenuBarContentView: View {
  @ObservedObject var controller: HeadphoneController
  let openSettings: () -> Void
  @EnvironmentObject private var preferences: AppPreferences

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header

      if let state = controller.state {
        modePicker(state)
        quickControls(state)
        Divider()
        footer
      } else {
        connectionPlaceholder
      }
    }
    .padding(20)
    .frame(width: 360)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "headphones")
        .font(.title2)
        .foregroundStyle(.tint)
        .frame(width: 38, height: 38)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

      VStack(alignment: .leading, spacing: 2) {
        Text("Soundcore Space One Pro")
          .font(.headline)
        Text(connectionSubtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if let state = controller.state {
        Label(
          "\(state.batteryPercent)%",
          systemImage: state.isCharging
            ? "battery.100percent.bolt" : batterySymbol(state.batteryPercent)
        )
        .labelStyle(.titleAndIcon)
        .font(.callout.monospacedDigit().weight(.medium))
        .accessibilityLabel("Battery \(state.batteryPercent) percent")
      }
    }
  }

  private func modePicker(_ state: SpaceOneProState) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Ambient sound")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      HStack(spacing: 6) {
        ForEach(AmbientMode.allCases) { mode in
          AmbientModeButton(
            mode: mode,
            isSelected: mode == state.soundModes.ambient,
            fillsWidth: true
          ) { controller.setAmbientMode(mode) }
        }
      }
      .disabled(controller.isApplyingChange)
    }
  }

  private func quickControls(_ state: SpaceOneProState) -> some View {
    VStack(spacing: 0) {
      if state.soundModes.ambient == .noiseCanceling {
        controlRow("Noise canceling") {
          Picker(
            "Noise canceling profile",
            selection: Binding(
              get: { state.soundModes.noiseCancelingMode },
              set: controller.setNoiseCancelingMode
            )
          ) {
            ForEach(NoiseCancelingMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .labelsHidden()
          .frame(width: 120)
        }
        controlDivider

        if state.soundModes.noiseCancelingMode == .custom {
          levelRow(
            "ANC strength",
            value: state.soundModes.customNoiseCancelingLevel,
            set: controller.setNoiseCancelingLevel
          )
        } else {
          controlRow("Adaptive level") {
            Text("\(state.soundModes.adaptiveNoiseCancelingLevel) of 5")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
        }
        controlDivider
      } else if state.soundModes.ambient == .transparency {
        levelRow(
          "Transparency level",
          value: state.soundModes.transparencyLevel,
          set: controller.setTransparencyLevel
        )
        controlDivider
      }

      controlRow("Equalizer") {
        Picker(
          "Equalizer",
          selection: Binding(
            get: { state.equalizerPresetID },
            set: controller.setEqualizerProfile
          )
        ) {
          Text("Custom").tag(SpaceOneProState.customEqualizerID)
          ForEach(EqualizerPreset.all) { preset in
            Text(preset.name).tag(preset.id)
          }
        }
        .labelsHidden()
        .frame(width: 174)
      }
      controlDivider

      controlRow("Dolby Audio") {
        Toggle(
          "Dolby Audio",
          isOn: Binding(
            get: { state.dolbyAudio },
            set: controller.setDolby
          )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .accessibilityLabel("Dolby Audio")
      }
    }
    .padding(.horizontal, 12)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(Color.secondary.opacity(0.14))
    }
    .disabled(controller.isApplyingChange)
  }

  private func controlRow<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(spacing: 12) {
      Text(title)
      Spacer(minLength: 8)
      content()
    }
    .frame(minHeight: 42)
  }

  private func levelRow(_ title: String, value: Int, set: @escaping (Int) -> Void) -> some View {
    controlRow(title) {
      Picker(title, selection: Binding(get: { value }, set: set)) {
        ForEach(1...5, id: \.self) { level in
          Text("Level \(level)").tag(level)
        }
      }
      .labelsHidden()
      .frame(width: 120)
    }
  }

  private var controlDivider: some View {
    Divider()
  }

  private var footer: some View {
    HStack {
      Button("Settings…") {
        openSettings()
      }
      .keyboardShortcut(",")

      Spacer()

      Button(action: controller.refresh) {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Refresh headphone state")
      .help("Refresh")

      Button("Quit") { NSApp.terminate(nil) }
        .keyboardShortcut("q")
    }
    .controlSize(.small)
  }

  private var connectionPlaceholder: some View {
    VStack(alignment: .leading, spacing: 10) {
      if case .error(let message) = controller.connectionState {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .font(.callout)
      } else {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Opening the headphone control channel…")
            .font(.callout)
        }
      }
      Button("Try Again", action: controller.reconnect)
        .disabled(controller.connectionState.isBusy)
    }
  }

  private var connectionSubtitle: String {
    switch controller.connectionState {
    case .connected: "Connected"
    case .connecting: "Connecting…"
    case .disconnected: "Disconnected"
    case .error: "Needs attention"
    }
  }

  private func batterySymbol(_ percent: Int) -> String {
    switch percent {
    case 76...: "battery.100percent"
    case 51...: "battery.75percent"
    case 26...: "battery.50percent"
    case 11...: "battery.25percent"
    default: "battery.0percent"
    }
  }
}
