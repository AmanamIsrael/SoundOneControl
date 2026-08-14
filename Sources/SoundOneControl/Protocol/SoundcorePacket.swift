import Foundation

struct SoundcoreCommand: Hashable, Sendable {
  let group: UInt8
  let action: UInt8

  static let requestState = Self(group: 0x01, action: 0x01)
}

struct SoundcorePacket: Equatable, Sendable {
  enum Direction: Sendable {
    case outbound
    case inbound

    var header: [UInt8] {
      switch self {
      case .outbound: [0x08, 0xee, 0x00, 0x00, 0x00]
      case .inbound: [0x09, 0xff, 0x00, 0x00, 0x01]
      }
    }
  }

  let direction: Direction
  let command: SoundcoreCommand
  let body: [UInt8]

  init(direction: Direction = .outbound, command: SoundcoreCommand, body: [UInt8] = []) {
    self.direction = direction
    self.command = command
    self.body = body
  }

  var bytes: [UInt8] {
    let length = UInt16(direction.header.count + 2 + 2 + body.count + 1)
    var result = direction.header
    result.append(contentsOf: [command.group, command.action])
    result.append(contentsOf: length.littleEndianBytes)
    result.append(contentsOf: body)
    result.append(result.reduce(0, &+))
    return result
  }

  static func parse(from buffer: inout Data) throws -> SoundcorePacket? {
    let header = Direction.inbound.header
    let headerData = Data(header)
    if !buffer.starts(with: headerData) {
      if let range = buffer.range(of: headerData) {
        buffer.removeSubrange(buffer.startIndex..<range.lowerBound)
      } else {
        // Retain enough trailing bytes to complete a header split across callbacks.
        let retainedCount = min(buffer.count, header.count - 1)
        buffer = buffer.suffix(retainedCount)
        return nil
      }
    }

    guard buffer.count >= 9 else { return nil }
    let start = buffer.startIndex
    let lengthLowIndex = buffer.index(start, offsetBy: 7)
    let lengthHighIndex = buffer.index(start, offsetBy: 8)
    let length = Int(buffer[lengthLowIndex]) | (Int(buffer[lengthHighIndex]) << 8)
    guard length >= 10 else { throw SoundcoreProtocolError.invalidPacketLength(length) }
    guard buffer.count >= length else { return nil }

    // Own the packet bytes before consuming the receive buffer. A Data.SubSequence keeps
    // the parent's indices and becomes invalid when the parent is mutated in optimized builds.
    let packetBytes = Array(buffer.prefix(length))
    buffer.removeFirst(length)
    let expectedChecksum = packetBytes.dropLast().reduce(0, &+)
    guard packetBytes.last == expectedChecksum else {
      throw SoundcoreProtocolError.invalidChecksum
    }

    return SoundcorePacket(
      direction: .inbound,
      command: SoundcoreCommand(group: packetBytes[5], action: packetBytes[6]),
      body: Array(packetBytes[9..<(length - 1)])
    )
  }
}

enum SoundcoreProtocolError: LocalizedError, Equatable {
  case invalidPacketLength(Int)
  case invalidChecksum
  case invalidStateLength(Int)
  case invalidFirmware
  case invalidSerialNumber

  var errorDescription: String? {
    switch self {
    case .invalidPacketLength(let length): "Invalid Soundcore packet length: \(length)."
    case .invalidChecksum: "The headphones returned a packet with an invalid checksum."
    case .invalidStateLength(let length):
      "The headphones returned an incomplete state (\(length) bytes)."
    case .invalidFirmware: "The headphones returned an invalid firmware version."
    case .invalidSerialNumber: "The headphones returned an invalid serial number."
    }
  }
}

extension UInt16 {
  fileprivate var littleEndianBytes: [UInt8] {
    [UInt8(truncatingIfNeeded: self), UInt8(truncatingIfNeeded: self >> 8)]
  }
}
