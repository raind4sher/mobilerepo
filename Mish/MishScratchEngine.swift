import AVFoundation

/// Plays the current song at any speed, forwards or backwards, for vinyl scratching.
///
/// It decodes a ~60 second window of the song around the playhead into memory, then a
/// custom audio source reads through it at a speed you set: 1 is normal, 2 is double (higher
/// pitch), negative plays backwards, 0 is silence. The speed eases toward whatever you set
/// and falls back to 0 if you stop updating it, like a hand holding the record still.
final class MishScratchEngine {
    private let state = MishScratchState()
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?

    private let windowSeconds: Double = 60

    /// Starts scratch playback at `seconds`. Returns false if the song couldn't be opened.
    func begin(url: URL, at seconds: TimeInterval) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }

        let format = file.processingFormat
        let rate = format.sampleRate
        guard rate > 0, format.channelCount > 0 else { return false }

        self.file = file
        state.configure(
            sampleRate: rate,
            channels: Int(format.channelCount),
            totalFrames: Double(file.length)
        )

        guard loadWindow(centeredOn: seconds) else {
            self.file = nil
            return false
        }

        let state = self.state
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            state.render(into: buffers, frames: Int(frameCount))
            return noErr
        }

        let engine = AVAudioEngine()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            print("Mish scratch engine failed to start:", error)
            self.file = nil
            state.clear()
            return false
        }

        self.engine = engine
        return true
    }

    /// Playback speed in "song seconds per real second". Negative = backwards.
    func setSpeed(_ speed: Double) {
        state.setTarget(speed)
    }

    /// Where the playhead is in the song, in seconds.
    var currentSeconds: TimeInterval {
        state.currentSeconds
    }

    /// Call every so often; loads a fresh window if the playhead is getting near an edge.
    func recenterIfNeeded() {
        guard state.needsRecenter else { return }
        loadWindow(centeredOn: state.currentSeconds)
    }

    /// Stops everything and returns where the playhead ended up, in seconds.
    @discardableResult
    func end() -> TimeInterval {
        let seconds = state.currentSeconds
        engine?.stop()
        engine = nil
        file = nil
        state.clear()
        return seconds
    }

    // MARK: Window loading

    @discardableResult
    private func loadWindow(centeredOn seconds: Double) -> Bool {
        guard let file else { return false }

        let format = file.processingFormat
        let rate = format.sampleRate
        let total = file.length
        guard total > 8 else { return false }

        let wanted = Int64(rate * windowSeconds)
        let half = wanted / 2

        var start = Int64(seconds * rate) - half
        start = max(0, min(start, total - 8))

        let count = min(wanted, total - start)
        guard count > 8,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(count)
              ) else {
            return false
        }

        do {
            file.framePosition = start
            try file.read(into: buffer, frameCount: AVAudioFrameCount(count))
        } catch {
            print("Mish scratch window load failed:", error)
            return false
        }

        guard buffer.frameLength > 8 else { return false }

        state.install(
            buffer: buffer,
            start: Double(start),
            fallbackAbsolute: seconds * rate
        )
        return true
    }
}

// MARK: - Shared state (touched by the audio thread, so everything is behind a lock)

private final class MishScratchState {
    private let lock = NSLock()

    private var buffer: AVAudioPCMBuffer?
    private var sampleRate: Double = 44100
    private var channels: Int = 2
    private var totalFrames: Double = 0

    /// Frames from the start of the loaded window.
    private var position: Double = 0
    /// Frames of the whole song where the window begins.
    private var windowStart: Double = 0
    private var windowFrames: Int = 0

    private var velocity: Double = 0
    private var target: Double = 0
    private var framesSinceTarget: Int = 0

    private var smoothing: Double = 0.002
    private var holdFrames: Int = 3000

    func configure(sampleRate: Double, channels: Int, totalFrames: Double) {
        lock.lock()
        defer { lock.unlock() }

        self.sampleRate = sampleRate
        self.channels = max(1, channels)
        self.totalFrames = totalFrames

        // Speed eases toward the target over about 12 ms; it drops to 0 if not refreshed for 80 ms.
        smoothing = 1.0 - exp(-1.0 / (0.012 * sampleRate))
        holdFrames = Int(sampleRate * 0.08)

        position = 0
        windowStart = 0
        windowFrames = 0
        velocity = 0
        target = 0
        framesSinceTarget = 0
        buffer = nil
    }

    func install(buffer newBuffer: AVAudioPCMBuffer, start: Double, fallbackAbsolute: Double) {
        lock.lock()
        defer { lock.unlock() }

        // Keep the playhead exactly where it was in the song.
        let absolute = buffer == nil ? fallbackAbsolute : windowStart + position

        buffer = newBuffer
        windowStart = start
        windowFrames = Int(newBuffer.frameLength)

        let relative = absolute - start
        position = min(max(relative, 0), Double(max(windowFrames - 2, 0)))
    }

    func setTarget(_ speed: Double) {
        lock.lock()
        defer { lock.unlock() }

        target = min(max(speed, -8), 8)
        framesSinceTarget = 0
    }

    var currentSeconds: Double {
        lock.lock()
        defer { lock.unlock() }

        guard sampleRate > 0 else { return 0 }
        return (windowStart + position) / sampleRate
    }

    /// True when the playhead is within ~3 seconds of an edge that isn't the song's start or end.
    var needsRecenter: Bool {
        lock.lock()
        defer { lock.unlock() }

        guard windowFrames > 0 else { return false }

        let margin = sampleRate * 3
        let nearStart = position < margin && windowStart > 0
        let windowEnd = windowStart + Double(windowFrames)
        let nearEnd = (Double(windowFrames) - position) < margin && windowEnd < totalFrames
        return nearStart || nearEnd
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }

        buffer = nil
        windowFrames = 0
        position = 0
        velocity = 0
        target = 0
    }

    // MARK: Audio thread

    func render(into buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard let channelData = buffer?.floatChannelData, windowFrames > 4 else {
            silence(buffers)
            return
        }

        framesSinceTarget += frames
        if framesSinceTarget > holdFrames {
            target = 0
        }

        let lastPosition = Double(windowFrames - 2)
        let goal = target
        let lastChannel = channels - 1
        var pos = position
        var vel = velocity

        for frame in 0..<frames {
            vel += (goal - vel) * smoothing
            pos += vel

            if pos < 0 {
                pos = 0
                vel = 0
            } else if pos > lastPosition {
                pos = lastPosition
                vel = 0
            }

            let index = Int(pos)
            let fraction = Float(pos - Double(index))

            // Quiet when nearly still, so holding the record doesn't hum or click.
            let loudness = Float(min(1.0, abs(vel) / 0.12)) * 0.9

            for channel in 0..<buffers.count {
                guard let out = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }
                let source = channelData[min(channel, lastChannel)]
                let a = source[index]
                let b = source[index + 1]
                out[frame] = (a + (b - a) * fraction) * loudness
            }
        }

        position = pos
        velocity = vel
    }

    private func silence(_ buffers: UnsafeMutableAudioBufferListPointer) {
        for index in 0..<buffers.count {
            if let data = buffers[index].mData {
                memset(data, 0, Int(buffers[index].mDataByteSize))
            }
        }
    }
}
