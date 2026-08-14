import Foundation
import IOBluetooth

final class BluetoothAgent: NSObject, IOBluetoothRFCOMMChannelDelegate {
  private var channel: IOBluetoothRFCOMMChannel?
  private var receiveBuffer = Data()
  private let outputLock = NSLock()

  func run(address: String) -> Never {
    guard let device = IOBluetoothDevice(addressString: address), device.isConnected() else {
      fail("Space One Pro is not connected.")
    }

    var openedChannel: IOBluetoothRFCOMMChannel?
    let result = device.openRFCOMMChannelSync(&openedChannel, withChannelID: 15, delegate: self)
    guard result == kIOReturnSuccess, let openedChannel else {
      // IOBluetooth can return an error with a partially opened channel after the adapter cycles.
      // Closing it explicitly lets the next automatic connection attempt start cleanly.
      if let openedChannel { _ = openedChannel.close() }
      fail("RFCOMM open failed (\(result)).")
    }
    channel = openedChannel
    emit("READY")

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      while let line = readLine(strippingNewline: true) {
        self?.handle(line)
      }
      DispatchQueue.main.async { exit(0) }
    }
    RunLoop.current.run()
    exit(0)
  }

  func rfcommChannelData(
    _ rfcommChannel: IOBluetoothRFCOMMChannel!,
    data dataPointer: UnsafeMutableRawPointer!,
    length dataLength: Int
  ) {
    receiveBuffer.append(dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength)

    while true {
      let header: [UInt8] = [0x09, 0xff, 0x00, 0x00, 0x01]
      let headerData = Data(header)
      if !receiveBuffer.starts(with: headerData) {
        if let range = receiveBuffer.range(of: headerData) {
          receiveBuffer.removeSubrange(receiveBuffer.startIndex..<range.lowerBound)
        } else {
          receiveBuffer = receiveBuffer.suffix(min(receiveBuffer.count, 4))
          return
        }
      }
      guard receiveBuffer.count >= 9 else { return }
      let start = receiveBuffer.startIndex
      let low = receiveBuffer[receiveBuffer.index(start, offsetBy: 7)]
      let high = receiveBuffer[receiveBuffer.index(start, offsetBy: 8)]
      let length = Int(low) | (Int(high) << 8)
      guard length >= 10, receiveBuffer.count >= length else { return }
      let packet = Array(receiveBuffer.prefix(length))
      receiveBuffer.removeFirst(length)
      emit("PACKET \(packet.hexString)")
    }
  }

  func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
    emit("ERROR RFCOMM channel closed.")
    exit(1)
  }

  private func handle(_ line: String) {
    if line == "QUIT" {
      if let channel { _ = channel.close() }
      exit(0)
    }
    guard line.hasPrefix("SEND "),
      var bytes = [UInt8](hex: String(line.dropFirst(5))),
      let channel
    else {
      emit("ERROR Invalid helper command.")
      return
    }
    let result = bytes.withUnsafeMutableBytes { buffer in
      channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
    }
    if result != kIOReturnSuccess {
      emit("ERROR RFCOMM write failed (\(result)).")
    }
  }

  private func emit(_ line: String) {
    outputLock.lock()
    defer { outputLock.unlock() }
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
  }

  private func fail(_ message: String) -> Never {
    emit("ERROR \(message)")
    exit(1)
  }
}

extension Array where Element == UInt8 {
  fileprivate init?(hex: String) {
    guard hex.count.isMultiple(of: 2) else { return nil }
    self.init()
    reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      append(byte)
      index = next
    }
  }

  fileprivate var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

guard let address = CommandLine.arguments.dropFirst().first else {
  fputs("Missing Bluetooth address.\n", stderr)
  exit(2)
}
BluetoothAgent().run(address: address)
