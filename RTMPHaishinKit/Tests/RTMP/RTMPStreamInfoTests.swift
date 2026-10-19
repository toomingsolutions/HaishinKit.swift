import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import HaishinKit
@testable import RTMPHaishinKit

@Suite struct RTMPStreamInfoTests {
    /// Builds a one-sample compressed H.264 buffer. `isKeyFrame == false` sets the
    /// `kCMSampleAttachmentKey_NotSync` attachment the way VideoToolbox does for P/B frames.
    private func makeCompressedBuffer(isKeyFrame: Bool, presentationTimeStamp: CMTime) -> CMSampleBuffer {
        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: 1280,
            height: 720,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        precondition(formatStatus == noErr && formatDescription != nil)
        var blockBuffer: CMBlockBuffer?
        let payload: [UInt8] = [0x00, 0x00, 0x00, 0x04, 0x65, 0x88, 0x84, 0x00]
        let blockStatus = payload.withUnsafeBytes { raw -> OSStatus in
            var buffer: CMBlockBuffer?
            let status = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: payload.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: payload.count,
                flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &buffer
            )
            guard status == noErr, let buffer else {
                return status
            }
            let copyStatus = CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!,
                blockBuffer: buffer,
                offsetIntoDestination: 0,
                dataLength: payload.count
            )
            blockBuffer = buffer
            return copyStatus
        }
        precondition(blockStatus == noErr && blockBuffer != nil)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: presentationTimeStamp,
            decodeTimeStamp: .invalid
        )
        var sampleSize = payload.count
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        precondition(sampleStatus == noErr && sampleBuffer != nil)
        let result = sampleBuffer!
        result.isNotSync = !isKeyFrame
        return result
    }

    @Test func infoStartsEmpty() {
        let info = RTMPStreamInfo()
        #expect(info.keyFrameCount == 0)
        #expect(info.lastKeyFrameUptime == nil)
    }

    @Test func recordKeyFrameThenClear() {
        var info = RTMPStreamInfo()
        info.recordKeyFrame(uptime: 10)
        info.recordKeyFrame(uptime: 12.5)
        #expect(info.keyFrameCount == 2)
        #expect(info.lastKeyFrameUptime == 12.5)
        info.clear()
        #expect(info.keyFrameCount == 0)
        #expect(info.lastKeyFrameUptime == nil)
    }

    @Test func appendCountsOnlyCompressedKeyFrames() async {
        let stream = RTMPStream(connection: RTMPConnection())
        #expect(await stream.info.keyFrameCount == 0)
        #expect(await stream.info.lastKeyFrameUptime == nil)

        // IDR, then three non-key frames, then another IDR: two key frames out of five.
        // Timestamps start above zero because RTMPTimestamp rejects a non-increasing sequence.
        let pattern = [true, false, false, false, true]
        let before = ProcessInfo.processInfo.systemUptime
        for (index, isKeyFrame) in pattern.enumerated() {
            let buffer = makeCompressedBuffer(
                isKeyFrame: isKeyFrame,
                presentationTimeStamp: CMTime(value: CMTimeValue(index + 1), timescale: 30)
            )
            await stream.append(buffer)
        }
        let after = ProcessInfo.processInfo.systemUptime

        let info = await stream.info
        #expect(info.keyFrameCount == 2)
        #expect(info.lastKeyFrameUptime != nil)
        if let lastKeyFrameUptime = info.lastKeyFrameUptime {
            #expect(lastKeyFrameUptime >= before)
            #expect(lastKeyFrameUptime <= after)
        }
    }

    @Test func nonKeyFramesDoNotMoveTheKeyFrameClock() async {
        let stream = RTMPStream(connection: RTMPConnection())
        await stream.append(makeCompressedBuffer(isKeyFrame: true, presentationTimeStamp: CMTime(value: 1, timescale: 30)))
        let first = await stream.info.lastKeyFrameUptime
        #expect(first != nil)
        try? await Task.sleep(nanoseconds: 20_000_000)
        await stream.append(makeCompressedBuffer(isKeyFrame: false, presentationTimeStamp: CMTime(value: 2, timescale: 30)))
        let second = await stream.info.lastKeyFrameUptime
        #expect(second == first)
        #expect(await stream.info.keyFrameCount == 1)
    }
}
