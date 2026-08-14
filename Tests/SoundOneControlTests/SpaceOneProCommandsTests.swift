import XCTest

@testable import SoundOneControl

final class SpaceOneProCommandsTests: XCTestCase {
  func testGroupedSoundModeCommand() {
    let modes = SoundModes(bytes: [2, 0x51, 1, 1, 0, 5][...])
    let packet = SpaceOneProCommands.soundModes(modes)

    XCTAssertEqual(packet.command, .init(group: 0x06, action: 0x81))
    XCTAssertEqual(packet.body, [2, 0x51, 1, 1, 0, 5])
  }

  func testEqualizerCommandDisablesHearIDAndPreservesPayload() {
    var hearID = Array(repeating: UInt8(0xff), count: 28)
    hearID[0] = 1
    hearID[11...15] = [0, 0, 0, 10, 2]
    hearID[26...27] = [3, 4]

    let packet = SpaceOneProCommands.equalizer(
      presetID: 5,
      adjustments: [-30, 20, 40, 40, 30, 20, 0, -20, 0, -120],
      preserving: hearID
    )

    XCTAssertEqual(packet.command, .init(group: 0x03, action: 0x87))
    XCTAssertEqual(packet.body[0...3], [5, 0, 3, 4])
    XCTAssertEqual(packet.body[16], 0)
    XCTAssertEqual(packet.body.count, 53)
  }

  func testVolumeLimitCommandClampsToSupportedRange() {
    XCTAssertEqual(SpaceOneProCommands.volumeLimit(enabled: true, decibels: 120).body, [1, 100])
  }
}
