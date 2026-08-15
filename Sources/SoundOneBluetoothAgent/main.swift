import Foundation
import IOBluetooth

final class BluetoothAgent: NSObject, IOBluetoothRFCOMMChannelDelegate {
  private var channel: IOBluetoothRFCOMMChannel?
  private var receiveBuffer = Data()
  private let outputLock = NSLock()

  func run(address: String) -> Never {
    guard let device = IOBluetoothDevice(addressString: address) else {
      fail("Space One Pro not found.")
    }

    channel = openChannelWithRecovery(device: device)
    guard channel != nil else { fail("RFCOMM channel could not be opened after recovery.") }
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

  private func openChannelWithRecovery(device: IOBluetoothDevice) -> IOBluetoothRFCOMMChannel? {
    for cycle in 0..<3 {
      if cycle > 0 {
        emit("STATUS Retrying RFCOMM open (cycle \(cycle + 1)).")
      }

      if !device.isConnected() {
        if !waitForReconnect(device: device, timeout: 15) {
          emit("STATUS Device did not reconnect within 15s.")
          continue
        }
      }

      for attempt in 0..<4 {
        if attempt > 0 { Thread.sleep(forTimeInterval: 1.5) }

        var openedChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelSync(&openedChannel, withChannelID: 15, delegate: self)
        if result == kIOReturnSuccess, let ch = openedChannel {
          if cycle > 0 || attempt > 0 {
            emit("RECOVERED after \(cycle) cycles, \(attempt) retries")
          }
          return ch
        }

        if let openedChannel { _ = openedChannel.close() }
        emit("STATUS RFCOMM open failed (attempt \(attempt + 1), code \(result)).")
      }

      // The audio profiles share this Bluetooth device connection. Give macOS a moment before
      // another RFCOMM cycle instead of forcing a device reconnect that interrupts playback.
      if cycle < 2 { Thread.sleep(forTimeInterval: 1) }
    }

    return nil
  }

  private func waitForReconnect(device: IOBluetoothDevice, timeout: Int) -> Bool {
    for _ in 0..<timeout {
      if device.isConnected() { return true }
      Thread.sleep(forTimeInterval: 1)
    }
    return device.isConnected()
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
