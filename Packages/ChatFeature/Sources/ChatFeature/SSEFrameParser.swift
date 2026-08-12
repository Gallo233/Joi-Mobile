import Foundation

/// Incremental server-sent-events framer.
///
/// This exists because `AsyncSequence.lines` cannot parse SSE: it does not emit
/// empty lines, and a blank line is precisely what terminates an SSE frame. Using
/// it silently concatenates consecutive events into one invalid payload.
struct SSEFrameParser {
    /// A frame line longer than this is treated as a malformed stream rather than
    /// being buffered without bound.
    static let maximumLineBytes = 512 * 1024

    private var lineBytes: [UInt8] = []
    private var dataLines: [String] = []

    init() {}

    /// Feeds one byte. Returns the accumulated `data:` payload when a blank line
    /// closes a frame, otherwise nil.
    mutating func consume(_ byte: UInt8) throws -> String? {
        guard byte != UInt8(ascii: "\n") else {
            return closeLine()
        }
        lineBytes.append(byte)
        guard lineBytes.count <= Self.maximumLineBytes else {
            throw ChatTransportError.malformedStream
        }
        return nil
    }

    /// Flushes a stream that ended without a terminating blank line. A complete
    /// final frame is still delivered; a partial one yields nil.
    mutating func finish() -> String? {
        if !lineBytes.isEmpty, let payload = closeLine() {
            return payload
        }
        return closeFrame()
    }

    private mutating func closeLine() -> String? {
        // Tolerate CRLF: the CR belongs to the delimiter, not the payload.
        if lineBytes.last == UInt8(ascii: "\r") {
            lineBytes.removeLast()
        }
        let line = String(decoding: lineBytes, as: UTF8.self)
        lineBytes.removeAll(keepingCapacity: true)

        guard !line.isEmpty else {
            return closeFrame()
        }
        // `id:` and `event:` are not retained: the event payload itself carries
        // the authoritative request/thread/event identity.
        if let value = Self.fieldValue(line, prefix: "data:") {
            dataLines.append(value)
        }
        return nil
    }

    private mutating func closeFrame() -> String? {
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true)
        return payload.isEmpty ? nil : payload
    }

    /// Returns the value after an SSE field prefix. Exactly one leading space is
    /// structural per the SSE grammar; any further space belongs to the payload.
    static func fieldValue(_ line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        var value = line.dropFirst(prefix.count)
        if value.hasPrefix(" ") { value = value.dropFirst() }
        return String(value)
    }
}
