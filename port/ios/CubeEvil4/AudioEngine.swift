import AVFoundation

/// Pulls interleaved PCM from the core and feeds AVAudioEngine.
///
/// It is idle while only the stub is linked (`re4_core_read_audio` returns 0),
/// but the graph, the audio session and the planar deinterleaving are already
/// the ones the core will use.
final class AudioEngine {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var interleaved: UnsafeMutablePointer<Float>?
    private let maxFrames = 4096
    private let channels = 2
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: AVAudioChannelCount(channels)
        ) else { return }

        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames * channels)
        buffer.initialize(repeating: 0, count: maxFrames * channels)
        interleaved = buffer

        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return 0 }
            let frames = min(Int(frameCount), self.maxFrames)
            buffer.update(repeating: 0, count: frames * self.channels)

            let got = Int(re4_core_read_audio(
                buffer,
                UInt32(frames),
                UInt32(self.channels)
            ))
            let usable = min(max(got, 0), frames)

            let list = UnsafeMutableAudioBufferListPointer(audioBufferList)
            if usable > 0 {
                for (channel, audioBuffer) in list.enumerated() {
                    guard let data = audioBuffer.mData?.assumingMemoryBound(to: Float.self) else {
                        continue
                    }
                    let capacity = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
                    let count = min(capacity, frames)
                    let sourceChannel = channel % self.channels
                    for frame in 0..<count {
                        data[frame] = buffer[frame * self.channels + sourceChannel]
                    }
                }
            } else {
                for audioBuffer in list {
                    if let data = audioBuffer.mData {
                        memset(data, 0, Int(audioBuffer.mDataByteSize))
                    }
                }
            }
            return 0
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            try engine.start()
            sourceNode = node
            isRunning = true
        } catch {
            engine.detach(node)
            buffer.deallocate()
            interleaved = nil
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
        }
        sourceNode = nil
        interleaved?.deallocate()
        interleaved = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    deinit {
        if isRunning {
            engine.stop()
        }
        interleaved?.deallocate()
    }
}
