import AppKit
import Foundation

@MainActor
final class HeadphoneController: ObservableObject {
  enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isBusy: Bool { self == .connecting }
  }

  @Published private(set) var connectionState: ConnectionState = .disconnected
  @Published private(set) var state: SpaceOneProState?
  @Published private(set) var isApplyingChange = false
  @Published private(set) var multipointDevices: [MultipointDevice] = []
  @Published var showMenuBarItem = false

  private let transport = RFCOMMTransport()
  private let notifications = NotificationManager()
  private var monitorTimer: Timer?
  private var wasAudioConnected = false
  private var hasRunDevelopmentDiagnostic = false

  init() {
    transport.onChannelClosed = { [weak self] in
      guard let self else { return }
      self.connectionState = .disconnected
      self.state = nil
    }
  }

  deinit {
    monitorTimer?.invalidate()
  }

  func start() {
    notifications.requestAuthorization()
    monitorTimer?.invalidate()
    let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.monitorConnection() }
    }
    monitorTimer = timer
    RunLoop.main.add(timer, forMode: .common)
    timer.fire()
  }

  func reconnect() {
    Task { await connectAndRefresh() }
  }

  func runDiagnosticConnection() {
    Task { await connectAndRefresh() }
  }

  func refresh() {
    Task { await refreshState() }
  }

  func disconnectHeadphones() {
    transport.disconnectHeadphones()
    state = nil
    connectionState = .disconnected
    showMenuBarItem = false
  }

  func setAmbientMode(_ mode: AmbientMode) {
    mutate(
      { $0.soundModes.ambient = mode }, command: { SpaceOneProCommands.soundModes($0.soundModes) })
  }

  func cycleAmbientMode() {
    guard let current = state?.soundModes.ambient,
      let index = AmbientMode.allCases.firstIndex(of: current)
    else { return }
    let next = AmbientMode.allCases[(index + 1) % AmbientMode.allCases.count]
    setAmbientMode(next)
  }

  func setNoiseCancelingMode(_ mode: NoiseCancelingMode) {
    mutate(
      { $0.soundModes.noiseCancelingMode = mode },
      command: { SpaceOneProCommands.soundModes($0.soundModes) })
  }

  func setNoiseCancelingLevel(_ level: Int) {
    mutate(
      { $0.soundModes.customNoiseCancelingLevel = level },
      command: { SpaceOneProCommands.soundModes($0.soundModes) })
  }

  func setTransparencyLevel(_ level: Int) {
    mutate(
      { $0.soundModes.transparencyLevel = level },
      command: { SpaceOneProCommands.soundModes($0.soundModes) })
  }

  func setWindNoiseReduction(_ enabled: Bool) {
    mutate(
      { $0.soundModes.windNoiseReduction = enabled },
      command: { SpaceOneProCommands.soundModes($0.soundModes) })
  }

  func setDolby(_ enabled: Bool) {
    mutate({ $0.dolbyAudio = enabled }, command: { SpaceOneProCommands.dolby($0.dolbyAudio) })
  }

  func toggleDolby() {
    guard let state else { return }
    setDolby(!state.dolbyAudio)
  }

  func setSideTone(_ enabled: Bool) {
    mutate({ $0.sideTone = enabled }, command: { SpaceOneProCommands.sideTone($0.sideTone) })
  }

  func setLowBatteryPrompt(_ enabled: Bool) {
    mutate(
      { $0.lowBatteryPrompt = enabled },
      command: { SpaceOneProCommands.lowBatteryPrompt($0.lowBatteryPrompt) })
  }

  func setMultipoint(_ enabled: Bool) {
    mutate(
      { $0.multipointEnabled = enabled },
      command: { SpaceOneProCommands.multipoint($0.multipointEnabled) })
  }

  func setMultipointDevice(_ device: MultipointDevice, connected: Bool) {
    perform(SpaceOneProCommands.setMultipointDevice(device, connected: connected)) {
      await self.refreshMultipointDevices()
    }
  }

  func forgetMultipointDevice(_ device: MultipointDevice) {
    perform(SpaceOneProCommands.forgetMultipointDevice(device)) {
      await self.refreshMultipointDevices()
    }
  }

  func setButtonBassUp(_ enabled: Bool) {
    mutate(
      { $0.buttonDoublePressBassUp = enabled },
      command: { SpaceOneProCommands.buttonDoublePressBassUp($0.buttonDoublePressBassUp) })
  }

  func setAutoPowerOff(enabled: Bool, durationIndex: Int) {
    mutate(
      {
        $0.autoPowerOff.enabled = enabled
        $0.autoPowerOff.durationIndex = durationIndex
      }, command: { SpaceOneProCommands.autoPowerOff($0.autoPowerOff) })
  }

  func setVolumeLimit(enabled: Bool, decibels: Int) {
    mutate(
      {
        $0.volumeLimit.enabled = enabled
        $0.volumeLimit.decibels = decibels
      },
      command: {
        SpaceOneProCommands.volumeLimit(
          enabled: $0.volumeLimit.enabled, decibels: $0.volumeLimit.decibels)
      })
  }

  func setVolumeRefreshRate(_ rate: DecibelRefreshRate) {
    mutate(
      { $0.volumeLimit.refreshRate = rate },
      command: { SpaceOneProCommands.volumeRefreshRate($0.volumeLimit.refreshRate) })
  }

  func setAmbientCycle(_ cycle: AmbientCycle) {
    mutate(
      { $0.ambientCycle = cycle }, command: { SpaceOneProCommands.ambientCycle($0.ambientCycle) })
  }

  func setEqualizerPreset(_ preset: EqualizerPreset) {
    if state?.equalizerPresetID == SpaceOneProState.customEqualizerID,
      let adjustments = state?.equalizerAdjustments
    {
      AppPreferences.shared.storeCustomEqualizerAdjustments(adjustments)
    }
    mutate(
      {
        $0.equalizerPresetID = preset.id
        $0.equalizerAdjustments = preset.adjustments
      },
      command: {
        SpaceOneProCommands.equalizer(
          presetID: $0.equalizerPresetID,
          adjustments: $0.equalizerAdjustments,
          preserving: $0.hearIDPayload
        )
      })
  }

  func setEqualizerProfile(_ id: UInt16) {
    if id == SpaceOneProState.customEqualizerID {
      setCustomEqualizer(AppPreferences.shared.customEqualizerAdjustments)
      return
    }
    guard let preset = EqualizerPreset.all.first(where: { $0.id == id }) else { return }
    setEqualizerPreset(preset)
  }

  func setCustomEqualizer(_ adjustments: [Int]) {
    AppPreferences.shared.storeCustomEqualizerAdjustments(adjustments)
    mutate(
      {
        $0.equalizerPresetID = SpaceOneProState.customEqualizerID
        $0.equalizerAdjustments = adjustments
      },
      command: {
        SpaceOneProCommands.equalizer(
          presetID: $0.equalizerPresetID,
          adjustments: $0.equalizerAdjustments,
          preserving: $0.hearIDPayload
        )
      })
  }

  private func monitorConnection() async {
    let audioConnected = transport.isAudioConnected
    showMenuBarItem = audioConnected

    if audioConnected, !transport.isControlConnected, !connectionState.isBusy {
      await connectAndRefresh()
    } else if !audioConnected {
      if wasAudioConnected { notifications.disconnected() }
      transport.disconnectControlChannel()
      state = nil
      connectionState = .disconnected
    }

    wasAudioConnected = audioConnected
  }

  private func connectAndRefresh() async {
    guard transport.isAudioConnected else {
      connectionState = .disconnected
      showMenuBarItem = false
      emitDiagnosticError("Space One Pro audio connection was not found.")
      return
    }

    connectionState = .connecting
    showMenuBarItem = true
    do {
      if !transport.isControlConnected {
        try await transport.connect()
      }
      await refreshState()
      if let state, !wasAudioConnected {
        notifications.connected(batteryPercent: state.batteryPercent)
      }
      await runDevelopmentDiagnosticIfNeeded()
    } catch {
      connectionState = .error(error.localizedDescription)
      emitDiagnosticError(error.localizedDescription)
    }
  }

  private func refreshState() async {
    do {
      let response = try await transport.send(SpaceOneProCommands.requestState)
      let newState = try SpaceOneProState(packet: response)
      state = newState
      if newState.equalizerPresetID == SpaceOneProState.customEqualizerID {
        AppPreferences.shared.storeCustomEqualizerAdjustments(newState.equalizerAdjustments)
      }
      connectionState = .connected
      notifications.checkLowBattery(newState.batteryPercent)
      if newState.multipointEnabled {
        await refreshMultipointDevices()
      } else {
        multipointDevices = []
      }
    } catch {
      connectionState = .error(error.localizedDescription)
    }
  }

  private func mutate(
    _ update: @escaping (inout SpaceOneProState) -> Void,
    command: @escaping (SpaceOneProState) -> SoundcorePacket
  ) {
    guard var target = state, !isApplyingChange else { return }
    update(&target)
    let previous = state
    state = target
    isApplyingChange = true

    Task {
      do {
        _ = try await transport.send(command(target))
        await refreshState()
      } catch {
        state = previous
        connectionState = .error(error.localizedDescription)
      }
      isApplyingChange = false
    }
  }

  private func refreshMultipointDevices() async {
    do {
      let response = try await transport.send(SpaceOneProCommands.requestMultipointDevices)
      multipointDevices = MultipointDevice.parse(packet: response)
    } catch {
      // Multipoint device enumeration is supplemental; keep the main control session usable.
      multipointDevices = []
    }
  }

  private func perform(
    _ command: SoundcorePacket, completion: @escaping @MainActor () async -> Void
  ) {
    guard !isApplyingChange else { return }
    isApplyingChange = true
    Task {
      do {
        _ = try await transport.send(command)
        await completion()
      } catch {
        connectionState = .error(error.localizedDescription)
      }
      isApplyingChange = false
    }
  }

  private func runDevelopmentDiagnosticIfNeeded() async {
    guard !hasRunDevelopmentDiagnostic,
      CommandLine.arguments.contains("--diagnose"),
      let originalState = state
    else { return }
    hasRunDevelopmentDiagnostic = true

    var result: [String: Any] = [
      "connected": true,
      "batteryPercent": originalState.batteryPercent,
      "firmwareVersion": originalState.firmwareVersion,
      "ambientMode": originalState.soundModes.ambient.title,
      "multipointEnabled": originalState.multipointEnabled,
      "multipointDeviceCount": multipointDevices.count,
    ]

    if CommandLine.arguments.contains("--test-ambient-round-trip") {
      var changedModes = originalState.soundModes
      changedModes.ambient =
        originalState.soundModes.ambient == .transparency ? .normal : .transparency
      do {
        _ = try await transport.send(SpaceOneProCommands.soundModes(changedModes))
        let changedResponse = try await transport.send(SpaceOneProCommands.requestState)
        let changedState = try SpaceOneProState(packet: changedResponse)

        _ = try await transport.send(SpaceOneProCommands.soundModes(originalState.soundModes))
        let restoredResponse = try await transport.send(SpaceOneProCommands.requestState)
        let restoredState = try SpaceOneProState(packet: restoredResponse)
        state = restoredState

        result["roundTripTarget"] = changedModes.ambient.title
        result["targetConfirmed"] = changedState.soundModes.ambient == changedModes.ambient
        result["restoredMode"] = restoredState.soundModes.ambient.title
        result["restoreConfirmed"] =
          restoredState.soundModes.ambient == originalState.soundModes.ambient
      } catch {
        // Best effort restoration if the confirmation phase fails midway.
        _ = try? await transport.send(SpaceOneProCommands.soundModes(originalState.soundModes))
        result["roundTripError"] = error.localizedDescription
      }
    }

    if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
      let line = String(data: data, encoding: .utf8)
    {
      FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
  }

  private func emitDiagnosticError(_ message: String) {
    guard CommandLine.arguments.contains("--diagnose") else { return }
    let result: [String: Any] = ["connected": false, "error": message]
    guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}
