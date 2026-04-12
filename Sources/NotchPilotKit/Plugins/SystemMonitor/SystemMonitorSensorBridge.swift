import Foundation
import IOKit

struct SystemMonitorSMCSensorBridge: Sendable {
    private static let intelCPUTemperatureKeys = ["TC0D", "TC0E", "TC0F", "TC0P", "TC0H"]
    private static let appleSiliconCPUTemperatureKeys = Array(Set([
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",
        "Te05", "Te0L", "Te0P", "Te0S",
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
        "Te09", "Te0H", "Tp0V", "Tp0Y", "Tp0e",
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0a", "Tp0d", "Tp0g", "Tp0m", "Tp0p", "Tp0u", "Tp0y",
    ])).sorted()

    private let smc: SystemMonitorSMCConnection?

    init(smc: SystemMonitorSMCConnection? = SystemMonitorSMCConnection()) {
        self.smc = smc
    }

    func cpuTemperatureCelsius() -> Double? {
        guard let smc else {
            return nil
        }

        for key in Self.intelCPUTemperatureKeys {
            if let temperature = smc.value(forKey: key), Self.isValidTemperature(temperature) {
                return temperature
            }
        }

        let appleSiliconTemperatures = Self.appleSiliconCPUTemperatureKeys.compactMap { key in
            smc.value(forKey: key)
        }
        if let average = Self.averageTemperature(from: appleSiliconTemperatures) {
            return average
        }

        let discoveredTemperatures = smc
            .allKeys()
            .filter { $0.hasPrefix("T") }
            .compactMap { key in smc.value(forKey: key) }
        return Self.averageTemperature(from: discoveredTemperatures)
    }

    static func averageTemperature(from values: [Double]) -> Double? {
        let validValues = values.filter(isValidTemperature)
        guard validValues.isEmpty == false else {
            return nil
        }

        return validValues.reduce(0, +) / Double(validValues.count)
    }

    static func decodedValue(dataType: String, bytes: [UInt8]) -> Double? {
        let paddedBytes = Array(bytes.prefix(32)) + Array(repeating: 0, count: max(0, 32 - bytes.count))

        switch dataType {
        case "ui8 ":
            return Double(paddedBytes[0])
        case "ui16":
            return Double(UInt16(bigEndianBytes: (paddedBytes[0], paddedBytes[1])))
        case "ui32":
            return Double(UInt32(bigEndianBytes: (paddedBytes[0], paddedBytes[1], paddedBytes[2], paddedBytes[3])))
        case "sp1e":
            return Double(UInt16(bigEndianBytes: (paddedBytes[0], paddedBytes[1]))) / 16_384
        case "sp3c":
            return Double(UInt16(bigEndianBytes: (paddedBytes[0], paddedBytes[1]))) / 4_096
        case "sp4b":
            return Double(UInt16(bigEndianBytes: (paddedBytes[0], paddedBytes[1]))) / 2_048
        case "sp5a":
            return Double(UInt16(bigEndianBytes: (paddedBytes[0], paddedBytes[1]))) / 1_024
        case "sp69":
            return Double(UInt16(bigEndianBytes: (paddedBytes[0], paddedBytes[1]))) / 512
        case "sp78":
            return Double(Int(paddedBytes[0]) * 256 + Int(paddedBytes[1])) / 256
        case "sp87":
            return Double(Int(paddedBytes[0]) * 256 + Int(paddedBytes[1])) / 128
        case "sp96":
            return Double(Int(paddedBytes[0]) * 256 + Int(paddedBytes[1])) / 64
        case "spa5":
            return Double(UInt16(bigEndianBytes: (paddedBytes[0], paddedBytes[1]))) / 32
        case "spb4":
            return Double(Int(paddedBytes[0]) * 256 + Int(paddedBytes[1])) / 16
        case "spf0":
            return Double(Int(paddedBytes[0]) * 256 + Int(paddedBytes[1]))
        case "flt ":
            let bitPattern = UInt32(littleEndianBytes: (paddedBytes[0], paddedBytes[1], paddedBytes[2], paddedBytes[3]))
            return Double(Float(bitPattern: bitPattern))
        case "fpe2":
            return Double((Int(paddedBytes[0]) << 6) + (Int(paddedBytes[1]) >> 2))
        default:
            return nil
        }
    }

    private static func isValidTemperature(_ value: Double) -> Bool {
        value > 0 && value < 121
    }
}

final class SystemMonitorSMCConnection: @unchecked Sendable {
    private var connection: io_connect_t = 0
    private let lock = NSLock()

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            return nil
        }
        defer {
            IOObjectRelease(service)
        }

        var openedConnection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &openedConnection) == kIOReturnSuccess else {
            return nil
        }

        connection = openedConnection
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func value(forKey key: String) -> Double? {
        guard let rawValue = read(key: key),
              rawValue.dataSize > 0,
              rawValue.bytes.contains(where: { $0 != 0 })
        else {
            return nil
        }

        return SystemMonitorSMCSensorBridge.decodedValue(
            dataType: rawValue.dataType,
            bytes: rawValue.bytes
        )
    }

    func allKeys() -> [String] {
        guard let keyCount = value(forKey: "#KEY"), keyCount > 0 else {
            return []
        }

        return (0..<Int(keyCount)).compactMap { index in
            key(at: UInt32(index))
        }
    }

    private func key(at index: UInt32) -> String? {
        var input = SystemMonitorSMCKeyData()
        var output = SystemMonitorSMCKeyData()
        input.data8 = SystemMonitorSMCSelector.readIndex.rawValue
        input.data32 = index

        guard call(input: &input, output: &output) == kIOReturnSuccess else {
            return nil
        }

        return String(fourCharacterCode: output.key)
    }

    private func read(key: String) -> SystemMonitorSMCValue? {
        guard let keyCode = UInt32(smcKey: key) else {
            return nil
        }

        var input = SystemMonitorSMCKeyData()
        var output = SystemMonitorSMCKeyData()
        input.key = keyCode
        input.data8 = SystemMonitorSMCSelector.readKeyInfo.rawValue

        guard call(input: &input, output: &output) == kIOReturnSuccess else {
            return nil
        }

        var value = SystemMonitorSMCValue(key: key)
        value.dataSize = UInt32(output.keyInfo.dataSize)
        value.dataType = String(fourCharacterCode: output.keyInfo.dataType)

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SystemMonitorSMCSelector.readBytes.rawValue

        guard call(input: &input, output: &output) == kIOReturnSuccess else {
            return nil
        }

        value.bytes = withUnsafeBytes(of: output.bytes) { rawBuffer in
            Array(rawBuffer.prefix(Int(value.dataSize)))
        }
        return value
    }

    private func call(input: inout SystemMonitorSMCKeyData, output: inout SystemMonitorSMCKeyData) -> kern_return_t {
        let inputSize = MemoryLayout<SystemMonitorSMCKeyData>.stride
        var outputSize = MemoryLayout<SystemMonitorSMCKeyData>.stride

        lock.lock()
        defer {
            lock.unlock()
        }

        return IOConnectCallStructMethod(
            connection,
            UInt32(SystemMonitorSMCSelector.kernelIndex.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }
}

private enum SystemMonitorSMCSelector: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case readIndex = 8
    case readKeyInfo = 9
}

private struct SystemMonitorSMCValue {
    let key: String
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = []
}

private struct SystemMonitorSMCKeyData {
    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var limitData = LimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

private extension UInt16 {
    init(bigEndianBytes bytes: (UInt8, UInt8)) {
        self = UInt16(bytes.0) << 8 | UInt16(bytes.1)
    }
}

private extension UInt32 {
    init?(smcKey: String) {
        guard smcKey.utf8.count == 4 else {
            return nil
        }

        self = smcKey.utf8.reduce(0) { result, byte in
            result << 8 | UInt32(byte)
        }
    }

    init(bigEndianBytes bytes: (UInt8, UInt8, UInt8, UInt8)) {
        self = UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3)
    }

    init(littleEndianBytes bytes: (UInt8, UInt8, UInt8, UInt8)) {
        self = UInt32(bytes.0) | UInt32(bytes.1) << 8 | UInt32(bytes.2) << 16 | UInt32(bytes.3) << 24
    }
}

private extension String {
    init(fourCharacterCode code: UInt32) {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        self = String(decoding: bytes, as: UTF8.self)
    }
}
