import Foundation

enum SpaceOneProCommands {
  static let requestState = SoundcorePacket(command: .requestState)

  static func soundModes(_ modes: SoundModes) -> SoundcorePacket {
    SoundcorePacket(command: .init(group: 0x06, action: 0x81), body: modes.bytes)
  }

  static func ambientCycle(_ cycle: AmbientCycle) -> SoundcorePacket {
    SoundcorePacket(command: .init(group: 0x06, action: 0x82), body: [cycle.byte])
  }

  static func flag(group: UInt8, action: UInt8, enabled: Bool) -> SoundcorePacket {
    SoundcorePacket(command: .init(group: group, action: action), body: [enabled ? 1 : 0])
  }

  static func dolby(_ enabled: Bool) -> SoundcorePacket {
    flag(group: 0x02, action: 0x86, enabled: enabled)
  }

  static func sideTone(_ enabled: Bool) -> SoundcorePacket {
    flag(group: 0x01, action: 0x84, enabled: enabled)
  }

  static func lowBatteryPrompt(_ enabled: Bool) -> SoundcorePacket {
    flag(group: 0x10, action: 0x82, enabled: enabled)
  }

  static func multipoint(_ enabled: Bool) -> SoundcorePacket {
    flag(group: 0x0b, action: 0x84, enabled: enabled)
  }

  static let requestMultipointDevices = SoundcorePacket(command: .init(group: 0x0b, action: 0x01))

  static func setMultipointDevice(_ device: MultipointDevice, connected: Bool) -> SoundcorePacket {
    SoundcorePacket(
      command: .init(group: 0x0b, action: connected ? 0x82 : 0x81),
      body: device.address
    )
  }

  static func forgetMultipointDevice(_ device: MultipointDevice) -> SoundcorePacket {
    SoundcorePacket(command: .init(group: 0x0b, action: 0x83), body: device.address)
  }

  static func autoPowerOff(_ value: AutoPowerOff) -> SoundcorePacket {
    SoundcorePacket(
      command: .init(group: 0x01, action: 0x86),
      body: [value.enabled ? 1 : 0, UInt8(value.durationIndex.clamped(to: 0...9))]
    )
  }

  static func volumeLimit(enabled: Bool, decibels: Int) -> SoundcorePacket {
    SoundcorePacket(
      command: .init(group: 0x20, action: 0x82),
      body: [enabled ? 1 : 0, UInt8(decibels.clamped(to: 75...100))]
    )
  }

  static func volumeRefreshRate(_ rate: DecibelRefreshRate) -> SoundcorePacket {
    SoundcorePacket(command: .init(group: 0x20, action: 0x81), body: [rate.rawValue])
  }

  static func buttonDoublePressBassUp(_ enabled: Bool) -> SoundcorePacket {
    SoundcorePacket(
      command: .init(group: 0x04, action: 0x81),
      body: [0, 0, enabled ? 7 : 0x0f]
    )
  }

  static func equalizer(
    presetID: UInt16,
    adjustments: [Int],
    preserving hearIDPayload: [UInt8]
  ) -> SoundcorePacket {
    let normalizedAdjustments =
      Array(adjustments.prefix(10)) + Array(repeating: 0, count: max(0, 10 - adjustments.count))
    let encodedAdjustments = normalizedAdjustments.prefix(10).map {
      UInt8(($0 + 120).clamped(to: 0...254))
    }

    var preservedHearID = Array(hearIDPayload.prefix(28))
    if preservedHearID.count < 28 {
      preservedHearID += Array(repeating: 0xff, count: 28 - preservedHearID.count)
    }
    preservedHearID[0] = 0  // Custom EQ and HearID are mutually exclusive.

    var body: [UInt8] = [
      UInt8(truncatingIfNeeded: presetID),
      UInt8(truncatingIfNeeded: presetID >> 8),
      preservedHearID[26],
      preservedHearID[27],
    ]
    body += encodedAdjustments
    body += [0, 0]
    body.append(preservedHearID[0])
    body += preservedHearID[1..<11]
    body += preservedHearID[11..<15]
    body.append(preservedHearID[15])
    body += preservedHearID[16..<26]
    body += encodedAdjustments
    body.append(0)

    return SoundcorePacket(command: .init(group: 0x03, action: 0x87), body: body)
  }
}

struct EqualizerPreset: Identifiable, Hashable, Sendable {
  let id: UInt16
  let name: String
  let adjustments: [Int]

  static let all: [EqualizerPreset] = [
    .init(id: 0, name: "Soundcore Signature", adjustments: [0, 0, 0, 0, 0, 0, 0, 0, 0, -120]),
    .init(id: 1, name: "Acoustic", adjustments: [40, 10, 20, 20, 40, 40, 40, 20, 0, -120]),
    .init(id: 3, name: "Bass Reducer", adjustments: [-40, -30, -10, 0, 0, 0, 0, 0, 0, -120]),
    .init(id: 4, name: "Classical", adjustments: [30, 30, -20, -20, 0, 20, 30, 40, 0, -120]),
    .init(id: 5, name: "Podcast", adjustments: [-30, 20, 40, 40, 30, 20, 0, -20, 0, -120]),
    .init(id: 6, name: "Dance", adjustments: [20, -30, -10, 10, 20, 20, 10, -30, 0, -120]),
    .init(id: 7, name: "Deep", adjustments: [20, 10, 30, 30, 20, -20, -40, -50, 0, -120]),
    .init(id: 8, name: "Electronic", adjustments: [30, 20, -20, 20, 10, 20, 30, 30, 0, -120]),
    .init(id: 9, name: "Flat", adjustments: [-20, -20, -10, 0, 0, 0, -20, -20, 0, -120]),
    .init(id: 10, name: "Hip-Hop", adjustments: [20, 30, -10, -10, 20, -10, 20, 30, 0, -120]),
    .init(id: 11, name: "Jazz", adjustments: [20, 20, -20, -20, 0, 20, 30, 40, 0, -120]),
    .init(id: 12, name: "Latin", adjustments: [0, 0, -20, -20, -20, 0, 30, 50, 0, -120]),
    .init(id: 13, name: "Lounge", adjustments: [-10, 20, 40, 30, 0, -20, 20, 10, 0, -120]),
    .init(id: 14, name: "Piano", adjustments: [0, 30, 30, 20, 40, 50, 30, 40, 0, -120]),
    .init(id: 15, name: "Pop", adjustments: [-10, 10, 30, 30, 10, -10, -20, -30, 0, -120]),
    .init(id: 16, name: "R&B", adjustments: [60, 20, -20, -20, 20, 30, 30, 40, 0, -120]),
    .init(id: 17, name: "Rock", adjustments: [30, 20, -10, -10, 10, 30, 40, 50, 0, -120]),
    .init(
      id: 18, name: "Small Speakers", adjustments: [40, 30, 10, 0, -20, -30, -40, -40, 0, -120]),
    .init(id: 19, name: "Spoken Word", adjustments: [-30, -20, 10, 20, 20, 10, 0, -30, 0, -120]),
    .init(
      id: 20, name: "Treble Booster", adjustments: [-20, -20, -20, -10, 10, 20, 20, 40, 0, -120]),
    .init(
      id: 21, name: "Treble Reducer", adjustments: [0, 0, 0, -20, -30, -40, -40, -60, 0, -120]),
    .init(id: 0x7e7e, name: "Bass Booster", adjustments: [40, 30, 10, 0, 0, 0, 0, 0, 0, -120]),
  ]
}
