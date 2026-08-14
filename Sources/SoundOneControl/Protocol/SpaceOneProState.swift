import Foundation

enum AmbientMode: UInt8, CaseIterable, Identifiable, Sendable {
  case noiseCanceling = 0
  case transparency = 1
  case normal = 2

  var id: Self { self }

  var title: String {
    switch self {
    case .noiseCanceling: "Noise Canceling"
    case .transparency: "Transparency"
    case .normal: "Normal"
    }
  }

  var shortTitle: String {
    switch self {
    case .noiseCanceling: "ANC"
    case .transparency: "Transparency"
    case .normal: "Normal"
    }
  }

  var symbol: String {
    switch self {
    case .noiseCanceling: "ear.badge.waveform"
    case .transparency: "waveform"
    case .normal: "ear"
    }
  }
}

enum NoiseCancelingMode: UInt8, CaseIterable, Identifiable, Sendable {
  case custom = 0
  case adaptive = 1

  var id: Self { self }
  var title: String { self == .adaptive ? "Adaptive" : "Custom" }
}

enum DecibelRefreshRate: UInt8, CaseIterable, Identifiable, Sendable {
  case realTime = 0
  case tenSeconds = 1
  case oneMinute = 2

  var id: Self { self }
  var title: String {
    switch self {
    case .realTime: "Real time"
    case .tenSeconds: "Every 10 seconds"
    case .oneMinute: "Every minute"
    }
  }
}

struct AmbientCycle: Equatable, Sendable {
  var noiseCanceling: Bool
  var transparency: Bool
  var normal: Bool

  init(byte: UInt8) {
    noiseCanceling = byte & 0x01 != 0
    transparency = byte & 0x02 != 0
    normal = byte & 0x04 != 0
  }

  var byte: UInt8 {
    (noiseCanceling ? 0x01 : 0) | (transparency ? 0x02 : 0) | (normal ? 0x04 : 0)
  }
}

struct SoundModes: Equatable, Sendable {
  var ambient: AmbientMode
  var noiseCancelingMode: NoiseCancelingMode
  var customNoiseCancelingLevel: Int
  var adaptiveNoiseCancelingLevel: Int
  var transparencyLevel: Int
  var windNoiseReduction: Bool

  init(bytes: ArraySlice<UInt8>) {
    ambient = AmbientMode(rawValue: bytes[bytes.startIndex]) ?? .normal
    let combinedLevels = bytes[bytes.startIndex + 1]
    customNoiseCancelingLevel = Int(combinedLevels >> 4).clamped(to: 1...5)
    adaptiveNoiseCancelingLevel = Int(combinedLevels & 0x0f).clamped(to: 1...5)
    noiseCancelingMode = NoiseCancelingMode(rawValue: bytes[bytes.startIndex + 3]) ?? .custom
    windNoiseReduction = bytes[bytes.startIndex + 4] == 1
    transparencyLevel = Int(bytes[bytes.startIndex + 5]).clamped(to: 1...5)
  }

  var bytes: [UInt8] {
    [
      ambient.rawValue,
      UInt8(customNoiseCancelingLevel << 4 | adaptiveNoiseCancelingLevel),
      1,
      noiseCancelingMode.rawValue,
      windNoiseReduction ? 1 : 0,
      UInt8(transparencyLevel),
    ]
  }
}

struct AutoPowerOff: Equatable, Sendable {
  var enabled: Bool
  var durationIndex: Int

  var minutes: Int { (durationIndex + 1) * 30 }
}

struct VolumeLimit: Equatable, Sendable {
  var enabled: Bool
  var decibels: Int
  var refreshRate: DecibelRefreshRate
}

struct MultipointDevice: Identifiable, Equatable, Sendable {
  var id: [UInt8] { address }
  let isConnected: Bool
  let address: [UInt8]
  let name: String

  var addressString: String {
    address.reversed().map { String(format: "%02X", $0) }.joined(separator: ":")
  }

  static func parse(packet: SoundcorePacket) -> [MultipointDevice] {
    guard packet.command == SoundcoreCommand(group: 0x0b, action: 0x01), packet.body.count >= 2
    else {
      return []
    }
    var devices: [MultipointDevice] = []
    var index = 2
    while index < packet.body.count {
      let length = Int(packet.body[index])
      guard length >= 8, index + length <= packet.body.count else { break }
      let isConnected = packet.body[index + 1] == 1
      let address = Array(packet.body[(index + 2)..<(index + 8)])
      let nameBytes = packet.body[(index + 8)..<(index + length)]
      let trimmed = nameBytes.prefix { $0 != 0 }
      let name = String(bytes: trimmed, encoding: .utf8) ?? "Unknown device"
      devices.append(MultipointDevice(isConnected: isConnected, address: address, name: name))
      index += length
    }
    return devices
  }
}

struct SpaceOneProState: Equatable, Sendable {
  static let customEqualizerID: UInt16 = 0xfefe

  var batteryPercent: Int
  var isCharging: Bool
  var firmwareVersion: String
  var serialNumber: String
  var equalizerPresetID: UInt16
  var equalizerAdjustments: [Int]
  var hearIDPayload: [UInt8]
  var buttonDoublePressBassUp: Bool
  var ambientCycle: AmbientCycle
  var soundModes: SoundModes
  var lowBatteryPrompt: Bool
  var dolbyAudio: Bool
  var ldac: Bool
  var multipointEnabled: Bool
  var autoPowerOff: AutoPowerOff
  var volumeLimit: VolumeLimit
  var sideTone: Bool

  init(packet: SoundcorePacket) throws {
    let body = packet.body
    guard body.count >= 87 else { throw SoundcoreProtocolError.invalidStateLength(body.count) }

    // A3062 reports levels 0–9, where zero means 10% and nine means 100%.
    batteryPercent = min((Int(body[0]) + 1) * 10, 100)
    isCharging = body[1] == 1

    guard let firmware = String(bytes: body[2..<7], encoding: .ascii) else {
      throw SoundcoreProtocolError.invalidFirmware
    }
    firmwareVersion = firmware

    guard let serial = String(bytes: body[7..<23], encoding: .ascii) else {
      throw SoundcoreProtocolError.invalidSerialNumber
    }
    serialNumber = serial

    equalizerPresetID = UInt16(body[23]) | (UInt16(body[24]) << 8)
    equalizerAdjustments = body[25..<35].map { Int($0) - 120 }
    hearIDPayload = Array(body[37..<65])
    buttonDoublePressBassUp = body[67] == 7
    ambientCycle = AmbientCycle(byte: body[68])
    soundModes = SoundModes(bytes: body[69..<75])
    lowBatteryPrompt = body[76] == 1
    dolbyAudio = body[77] == 1
    ldac = body[78] == 1
    multipointEnabled = body[79] == 1
    autoPowerOff = AutoPowerOff(enabled: body[80] == 1, durationIndex: Int(body[81]))
    volumeLimit = VolumeLimit(
      enabled: body[82] == 1,
      decibels: Int(body[83]),
      refreshRate: DecibelRefreshRate(rawValue: body[84]) ?? .realTime
    )
    sideTone = body[85] == 1
  }
}

extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
