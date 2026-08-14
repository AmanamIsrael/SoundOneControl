import Foundation
import XCTest

@testable import SoundOneControl

final class SoundcorePacketTests: XCTestCase {
  func testRequestStateMatchesKnownPacket() {
    XCTAssertEqual(
      SpaceOneProCommands.requestState.bytes,
      [0x08, 0xee, 0x00, 0x00, 0x00, 0x01, 0x01, 0x0a, 0x00, 0x02]
    )
  }

  func testParserWaitsForCompletePacket() throws {
    var partial = Data([0x09, 0xff, 0x00, 0x00, 0x01, 0x01, 0x01, 0x0a, 0x00])
    XCTAssertNil(try SoundcorePacket.parse(from: &partial))
    XCTAssertEqual(partial.count, 9)
  }

  func testParserFindsHeaderAndConsumesOnePacket() throws {
    let bytes: [UInt8] = [0x09, 0xff, 0x00, 0x00, 0x01, 0x01, 0x01, 0x0a, 0x00, 0x15]
    var buffer = Data([0xde, 0xad] + bytes + [0xbe, 0xef])

    let packet = try XCTUnwrap(SoundcorePacket.parse(from: &buffer))

    XCTAssertEqual(packet.command, .requestState)
    XCTAssertTrue(packet.body.isEmpty)
    XCTAssertEqual(Array(buffer), [0xbe, 0xef])
  }

  func testParserRejectsBadChecksum() {
    var buffer = Data([0x09, 0xff, 0x00, 0x00, 0x01, 0x01, 0x01, 0x0a, 0x00, 0xff])
    XCTAssertThrowsError(try SoundcorePacket.parse(from: &buffer)) { error in
      XCTAssertEqual(error as? SoundcoreProtocolError, .invalidChecksum)
    }
  }

  func testParserHandlesSequentialPacketsAfterBufferConsumption() throws {
    let first: [UInt8] = [0x09, 0xff, 0x00, 0x00, 0x01, 0x01, 0x01, 0x0a, 0x00, 0x15]
    let second: [UInt8] = [0x09, 0xff, 0x00, 0x00, 0x01, 0x0b, 0x01, 0x0c, 0x00, 0x01, 0x01, 0x23]
    var buffer = Data(first)

    XCTAssertNotNil(try SoundcorePacket.parse(from: &buffer))
    buffer.append(contentsOf: second)
    let packet = try XCTUnwrap(SoundcorePacket.parse(from: &buffer))

    XCTAssertEqual(packet.command, SoundcoreCommand(group: 0x0b, action: 0x01))
    XCTAssertEqual(packet.body, [0x01, 0x01])
    XCTAssertTrue(buffer.isEmpty)
  }
}
