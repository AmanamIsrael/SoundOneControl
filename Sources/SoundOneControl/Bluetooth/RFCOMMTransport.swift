import Foundation
@preconcurrency import IOBluetooth

/// Owns the lifecycle and typed IPC for the bundled RFCOMM helper.
///
/// IOBluetooth's channel-open APIs can deadlock after AppKit owns the main run loop on recent
/// macOS releases. The helper is a short-lived child process—not a daemon—and opens RFCOMM before
/// starting its run loop, then forwards complete packets over private pipes.
@MainActor
final class RFCOMMTransport {
  static let supportedName = "soundcore Space One Pro"

  enum TransportError: LocalizedError {
    case deviceNotFound
    case deviceDisconnected
    case helperMissing
    case helperLaunchFailed(String)
    case helperFailed(String)
    case writeFailed
    case requestAlreadyPending
    case responseTimedOut
    case channelClosed

    var errorDescription: String? {
      switch self {
      case .deviceNotFound: "Space One Pro is not paired with this Mac."
      case .deviceDisconnected: "Space One Pro is not connected."
      case .helperMissing: "The bundled Bluetooth helper is missing. Rebuild SoundOne Control."
      case .helperLaunchFailed(let message): "Could not start Bluetooth control: \(message)"
      case .helperFailed(let message): "Bluetooth control failed: \(message)"
      case .writeFailed: "Could not send a command to the Bluetooth helper."
      case .requestAlreadyPending: "Another headphone command is still pending."
      case .responseTimedOut: "The headphones did not respond in time."
      case .channelClosed: "The Soundcore control channel closed."
      }
    }
  }

  private var device: IOBluetoothDevice?
  private var process: Process?
  private var inputPipe: Pipe?
  private var outputPipe: Pipe?
  private var outputBuffer = ""
  private var launchContinuation: CheckedContinuation<Void, Error>?
  private var responseContinuation: CheckedContinuation<SoundcorePacket, Error>?
  private var timeoutTask: Task<Void, Never>?
  private var isClosingIntentionally = false
  private var generation = 0

  var onChannelClosed: (() -> Void)?

  var isAudioConnected: Bool {
    findDevice()?.isConnected() == true
  }

  var isControlConnected: Bool {
    process?.isRunning == true && launchContinuation == nil
  }

  func connect() async throws {
    if isControlConnected { return }
    guard launchContinuation == nil else { throw TransportError.requestAlreadyPending }
    guard let device = findDevice() else { throw TransportError.deviceNotFound }
    guard device.isConnected() else { throw TransportError.deviceDisconnected }
    guard let helperURL = helperExecutableURL() else { throw TransportError.helperMissing }

    if process?.isRunning == true {
      isClosingIntentionally = true
      try? writeLine("QUIT")
      process?.terminate()
    }
    cleanUpProcess()

    self.device = device
    isClosingIntentionally = false
    outputBuffer = ""
    generation += 1
    let myGeneration = generation

    let process = Process()
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = helperURL
    process.arguments = [device.addressString]
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    self.process = process
    self.inputPipe = inputPipe
    self.outputPipe = outputPipe

    outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      let chunk = String(decoding: data, as: UTF8.self)
      Task { @MainActor in self?.consumeOutput(chunk) }
    }
    process.terminationHandler = { [weak self] _ in
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorText = String(decoding: errorData, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines)
      Task { @MainActor in self?.helperTerminated(errorText: errorText, generation: myGeneration) }
    }

    do {
      try process.run()
    } catch {
      cleanUpProcess()
      throw TransportError.helperLaunchFailed(error.localizedDescription)
    }

    try await withCheckedThrowingContinuation { continuation in
      launchContinuation = continuation
      timeoutTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(90))
        guard !Task.isCancelled else { return }
        self?.timeOutLaunch()
      }
    }
  }

  func connectWithRetry(maxAttempts: Int = 2, baseDelay: Duration = .seconds(2)) async throws {
    var lastError: Error?
    for attempt in 0..<maxAttempts {
      do {
        try await connect()
        return
      } catch {
        lastError = error
        if attempt < maxAttempts - 1 {
          if let device = findDevice() {
            device.closeConnection()
            for _ in 0..<20 {
              if device.isConnected() { break }
              try await Task.sleep(for: .seconds(1))
            }
          }
          try await Task.sleep(for: baseDelay)
        }
      }
    }
    throw lastError ?? TransportError.channelClosed
  }

  func disconnectControlChannel() {
    isClosingIntentionally = true
    generation += 1
    timeoutTask?.cancel()
    timeoutTask = nil
    launchContinuation?.resume(throwing: TransportError.channelClosed)
    launchContinuation = nil
    responseContinuation?.resume(throwing: TransportError.channelClosed)
    responseContinuation = nil
    if process?.isRunning == true {
      try? writeLine("QUIT")
      process?.terminate()
    }
    cleanUpProcess()
  }

  func disconnectHeadphones() {
    disconnectControlChannel()
    device?.closeConnection()
  }

  func send(_ packet: SoundcorePacket, timeout: Duration = .seconds(4)) async throws
    -> SoundcorePacket
  {
    guard responseContinuation == nil else { throw TransportError.requestAlreadyPending }
    if !isControlConnected { try await connectWithRetry() }

    return try await withCheckedThrowingContinuation { continuation in
      responseContinuation = continuation
      do {
        try writeLine("SEND \(packet.bytes.hexString)")
      } catch {
        responseContinuation = nil
        continuation.resume(throwing: error)
        return
      }

      timeoutTask = Task { [weak self] in
        try? await Task.sleep(for: timeout)
        guard !Task.isCancelled else { return }
        self?.timeOutRequest()
      }
    }
  }

  private func consumeOutput(_ chunk: String) {
    outputBuffer += chunk
    while let newline = outputBuffer.firstIndex(of: "\n") {
      let line = String(outputBuffer[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
      outputBuffer.removeSubrange(...newline)
      handleLine(line)
    }
  }

  private func handleLine(_ line: String) {
    if line == "READY" {
      timeoutTask?.cancel()
      timeoutTask = nil
      let continuation = launchContinuation
      launchContinuation = nil
      continuation?.resume()
      return
    }

    if line.hasPrefix("PACKET ") {
      let hex = String(line.dropFirst("PACKET ".count))
      guard let data = Data(hex: hex) else {
        finishResponse(.failure(TransportError.helperFailed("Invalid packet from helper.")))
        return
      }
      var buffer = data
      do {
        guard let packet = try SoundcorePacket.parse(from: &buffer) else {
          throw TransportError.helperFailed("Incomplete packet from helper.")
        }
        finishResponse(.success(packet))
      } catch {
        finishResponse(.failure(error))
      }
      return
    }

    if line.hasPrefix("ERROR ") {
      let message = String(line.dropFirst("ERROR ".count))
      let error = TransportError.helperFailed(message)
      timeoutTask?.cancel()
      timeoutTask = nil
      if let continuation = launchContinuation {
        launchContinuation = nil
        continuation.resume(throwing: error)
      } else {
        finishResponse(.failure(error))
      }
    }
  }

  private func finishResponse(_ result: Result<SoundcorePacket, Error>) {
    timeoutTask?.cancel()
    timeoutTask = nil
    let continuation = responseContinuation
    responseContinuation = nil
    switch result {
    case .success(let packet): continuation?.resume(returning: packet)
    case .failure(let error): continuation?.resume(throwing: error)
    }
  }

  private func helperTerminated(errorText: String, generation terminatedGeneration: Int) {
    guard terminatedGeneration == generation else { return }
    let intentional = isClosingIntentionally
    timeoutTask?.cancel()
    timeoutTask = nil
    let error: TransportError = errorText.isEmpty ? .channelClosed : .helperFailed(errorText)
    launchContinuation?.resume(throwing: error)
    launchContinuation = nil
    responseContinuation?.resume(throwing: error)
    responseContinuation = nil
    cleanUpProcess()
    if !intentional { onChannelClosed?() }
  }

  private func timeOutLaunch() {
    let continuation = launchContinuation
    launchContinuation = nil
    timeoutTask = nil
    continuation?.resume(throwing: TransportError.responseTimedOut)
    process?.terminate()
  }

  private func timeOutRequest() {
    let continuation = responseContinuation
    responseContinuation = nil
    timeoutTask = nil
    continuation?.resume(throwing: TransportError.responseTimedOut)
  }

  private func writeLine(_ line: String) throws {
    guard let data = (line + "\n").data(using: .utf8),
      let handle = inputPipe?.fileHandleForWriting
    else {
      throw TransportError.writeFailed
    }
    do {
      try handle.write(contentsOf: data)
    } catch {
      throw TransportError.writeFailed
    }
  }

  private func cleanUpProcess() {
    outputPipe?.fileHandleForReading.readabilityHandler = nil
    try? inputPipe?.fileHandleForWriting.close()
    try? outputPipe?.fileHandleForReading.close()
    process = nil
    inputPipe = nil
    outputPipe = nil
  }

  private func findDevice() -> IOBluetoothDevice? {
    let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?
      .first(where: { $0.name == Self.supportedName })
    if let paired, paired.isConnected() { return paired }
    if let device, device.name == Self.supportedName, device.isConnected() { return device }
    return paired
  }

  private func helperExecutableURL() -> URL? {
    let bundled = Bundle.main.bundleURL
      .appendingPathComponent("Contents/Helpers/SoundOneBluetoothAgent")
    if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }

    let sibling = URL(fileURLWithPath: CommandLine.arguments[0])
      .deletingLastPathComponent()
      .appendingPathComponent("SoundOneBluetoothAgent")
    return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
  }
}

extension Array where Element == UInt8 {
  fileprivate var hexString: String { map { String(format: "%02x", $0) }.joined() }
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
