import Foundation
import XCTest

@testable import SoundOneControl

final class SpaceOneProStateTests: XCTestCase {
  private let liveStateHex =
    "09ff0000010101690007ff30332e333933303632333136343845313345393743fefe818194a2abafaca000001eff00ffffffffffffffff00000000000000ffffffffffffffff0000000004040f0702500100000531010000010100005a0000010001000000000000d6"

  func testParsesLiveSpaceOneProState() throws {
    var data = Data(try XCTUnwrap(Data(hex: liveStateHex)))
    let packet = try XCTUnwrap(SoundcorePacket.parse(from: &data))

    let state = try SpaceOneProState(packet: packet)

    XCTAssertEqual(state.batteryPercent, 80)
    XCTAssertFalse(state.isCharging)
    XCTAssertEqual(state.firmwareVersion, "03.39")
    XCTAssertEqual(state.serialNumber, "306231648E13E97C")
    XCTAssertEqual(state.equalizerPresetID, SpaceOneProState.customEqualizerID)
    XCTAssertEqual(state.equalizerAdjustments, [9, 9, 28, 42, 51, 55, 52, 40, -120, -120])
    XCTAssertEqual(state.soundModes.ambient, .normal)
    XCTAssertEqual(state.soundModes.noiseCancelingMode, .custom)
    XCTAssertEqual(state.soundModes.customNoiseCancelingLevel, 5)
    XCTAssertEqual(state.soundModes.adaptiveNoiseCancelingLevel, 1)
    XCTAssertEqual(state.soundModes.transparencyLevel, 5)
    XCTAssertTrue(state.multipointEnabled)
    XCTAssertEqual(state.autoPowerOff.minutes, 30)
    XCTAssertEqual(state.volumeLimit.decibels, 90)
  }

  func testSoundModesPreserveGroupedFields() {
    var modes = SoundModes(bytes: [0, 0x51, 1, 1, 0, 5][...])
    modes.ambient = .transparency
    modes.windNoiseReduction = true

    XCTAssertEqual(modes.bytes, [1, 0x51, 1, 1, 1, 5])
  }

  func testMultipointDevicePacket() {
    let deviceBody: [UInt8] = [
      1, 1,
      0x0f, 1,
      0x78, 0xfb, 0xd8, 0xd5, 0x4f, 0x31,
      0x69, 0x50, 0x68, 0x6f, 0x6e, 0x65, 0x00,
    ]
    let packet = SoundcorePacket(
      direction: .inbound,
      command: .init(group: 0x0b, action: 0x01),
      body: deviceBody
    )

    let devices = MultipointDevice.parse(packet: packet)

    XCTAssertEqual(devices.count, 1)
    XCTAssertEqual(devices[0].name, "iPhone")
    XCTAssertTrue(devices[0].isConnected)
    XCTAssertEqual(devices[0].addressString, "31:4F:D5:D8:FB:78")
  }
}

extension Data {
  fileprivate init?(hex: String) {
    guard hex.count.isMultiple(of: 2) else { return nil }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      bytes.append(byte)
      index = next
    }
    self.init(bytes)
  }
}
