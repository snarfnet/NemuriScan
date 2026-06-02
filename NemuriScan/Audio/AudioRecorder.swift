import AVFoundation
import Combine

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0  // 0.0 to 1.0 normalized

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioSession = AVAudioSession.sharedInstance()

    private let chunkDuration: TimeInterval = 300  // 5 minutes
    private var chunkStartTime: Date = Date()
    private var audioChunkBuffer: [AVAudioPCMBuffer] = []

    var onChunkReady: (([AVAudioPCMBuffer]) -> Void)?
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    private let sampleRate: Double = 44100
    private let bufferSize: AVAudioFrameCount = 4096

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func startRecording() {
        configureAudioSession()
        setupAudioEngine()
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
        audioLevel = 0.0

        let chunks = audioChunkBuffer
        audioChunkBuffer = []
        if !chunks.isEmpty {
            onChunkReady?(chunks)
        }

        deactivateAudioSession()
    }

    private func configureAudioSession() {
        do {
            try audioSession.setCategory(
                .record,
                mode: .measurement,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try audioSession.setPreferredSampleRate(sampleRate)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("AudioSession configuration error: \(error)")
        }
    }

    private func deactivateAudioSession() {
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) ?? inputFormat

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            let convertedBuffer = self.convert(buffer: buffer, to: targetFormat) ?? buffer
            self.processBuffer(convertedBuffer, at: time)
        }

        do {
            try engine.start()
            DispatchQueue.main.async {
                self.isRecording = true
                self.chunkStartTime = Date()
            }
        } catch {
            print("AudioEngine start error: \(error)")
        }
    }

    private func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format != format,
              let converter = AVAudioConverter(from: buffer.format, to: format) else {
            return buffer
        }
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        var error: NSError?
        var inputDone = false
        converter.convert(to: output, error: &error) { _, outStatus in
            if inputDone {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputDone = true
            return buffer
        }
        return error == nil ? output : nil
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        updateAudioLevel(buffer)
        onAudioBuffer?(buffer, time)
        audioChunkBuffer.append(buffer)

        let elapsed = Date().timeIntervalSince(chunkStartTime)
        if elapsed >= chunkDuration {
            let chunks = audioChunkBuffer
            audioChunkBuffer = []
            chunkStartTime = Date()
            DispatchQueue.global(qos: .utility).async {
                self.onChunkReady?(chunks)
            }
        }
    }

    private func updateAudioLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(frameLength))
        let db = 20 * log10(max(rms, 1e-7))
        let normalized = max(0, min(1, (db + 60) / 60))

        DispatchQueue.main.async {
            self.audioLevel = normalized
        }
    }
}
