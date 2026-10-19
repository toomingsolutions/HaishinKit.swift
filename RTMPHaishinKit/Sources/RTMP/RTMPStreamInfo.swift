import Foundation

/// A structor that provides the statistics related to the RTMPStream.
public struct RTMPStreamInfo: Sendable {
    /// The number of bytes received by the RTMPStream.
    public internal(set) var byteCount = 0
    /// The resource name of a stream.
    public internal(set) var resourceName: String?
    /// The number of bytes received per second by the RTMPStream.
    public internal(set) var currentBytesPerSecond = 0
    /// The number of compressed key frames (sync samples) handed to the RTMPStream for publishing.
    public internal(set) var keyFrameCount = 0
    /// The `ProcessInfo.systemUptime` at which the latest compressed key frame was handed to the
    /// RTMPStream, or nil before the first one.
    public internal(set) var lastKeyFrameUptime: TimeInterval?
    private var previousByteCount = 0

    mutating func update() {
        currentBytesPerSecond = byteCount - previousByteCount
        previousByteCount = byteCount
    }

    mutating func recordKeyFrame(uptime: TimeInterval) {
        keyFrameCount += 1
        lastKeyFrameUptime = uptime
    }

    mutating func clear() {
        byteCount = 0
        currentBytesPerSecond = 0
        previousByteCount = 0
        keyFrameCount = 0
        lastKeyFrameUptime = nil
    }
}

extension RTMPStreamInfo: CustomDebugStringConvertible {
    // MARK: CustomDebugStringConvertible
    public var debugDescription: String {
        Mirror(reflecting: self).debugDescription
    }
}
