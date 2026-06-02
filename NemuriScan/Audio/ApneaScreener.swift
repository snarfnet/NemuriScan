import AVFoundation
import Accelerate

/// Apnea screening using silence detection in breathing audio.
/// Based on Nakano et al. (2004) smartphone-based apnea screening.
class ApneaScreener {
    private let sampleRate: Double = 44100

    // Silence threshold: gaps > 10 seconds indicate possible apnea
    private let apneaMinDuration: TimeInterval = 10.0
    private let hypopneaMinDuration: TimeInterval = 5.0

    // RMS energy below this level = silence
    private let silenceThreshold: Float = 0.005

    // Analysis window: 1 second
    private let windowDuration: TimeInterval = 1.0

    // MARK: - Public

    func detectApneaEvents(
        from buffers: [AVAudioPCMBuffer],
        sessionStart: Date
    ) -> [ApneaEvent] {
        let samples = extractMonoSamples(from: buffers)
        guard !samples.isEmpty else { return [] }

        let windowSize = Int(windowDuration * sampleRate)
        let windowCount = samples.count / windowSize

        var energyProfile = [Float]()
        for i in 0..<windowCount {
            let start = i * windowSize
            let end = start + windowSize
            let window = Array(samples[start..<end])
            var rms: Float = 0
            vDSP_rmsqv(window, 1, &rms, vDSP_Length(window.count))
            energyProfile.append(rms)
        }

        return findSilentGaps(in: energyProfile, sessionStart: sessionStart)
    }

    func calculateAHI(apneaEvents: [ApneaEvent], sessionDurationHours: Double) -> Double {
        guard sessionDurationHours > 0 else { return 0 }
        return Double(apneaEvents.count) / sessionDurationHours
    }

    func riskLevel(for ahi: Double) -> ApneaRisk {
        if ahi < 5 { return .normal }
        if ahi < 15 { return .mild }
        if ahi < 30 { return .moderate }
        return .severe
    }

    // MARK: - Private

    private func findSilentGaps(
        in energyProfile: [Float],
        sessionStart: Date
    ) -> [ApneaEvent] {
        var events = [ApneaEvent]()
        var silenceStart: Int? = nil

        for i in 0..<energyProfile.count {
            let isSilent = energyProfile[i] < silenceThreshold

            if isSilent {
                if silenceStart == nil {
                    silenceStart = i
                }
            } else {
                if let start = silenceStart {
                    let gapDuration = Double(i - start) * windowDuration
                    if gapDuration >= apneaMinDuration {
                        let timestamp = sessionStart.addingTimeInterval(Double(start) * windowDuration)
                        let apneaType = classifyApneaType(
                            energyBefore: start > 0 ? energyProfile[start - 1] : 0,
                            energyAfter: energyProfile[i],
                            duration: gapDuration
                        )
                        events.append(ApneaEvent(
                            timestamp: timestamp,
                            duration: gapDuration,
                            type: apneaType
                        ))
                    }
                    silenceStart = nil
                }
            }
        }

        // Handle silence extending to end of recording
        if let start = silenceStart {
            let gapDuration = Double(energyProfile.count - start) * windowDuration
            if gapDuration >= apneaMinDuration {
                let timestamp = sessionStart.addingTimeInterval(Double(start) * windowDuration)
                events.append(ApneaEvent(
                    timestamp: timestamp,
                    duration: gapDuration,
                    type: .obstructive
                ))
            }
        }

        return events
    }

    private func classifyApneaType(
        energyBefore: Float,
        energyAfter: Float,
        duration: TimeInterval
    ) -> ApneaType {
        // Obstructive: abrupt onset (high energy before silence)
        // Central: gradual fade
        // Mixed: long duration with irregular return
        if energyBefore > 0.05 && energyAfter > 0.03 {
            return duration > 20 ? .mixed : .obstructive
        }
        return .central
    }

    private func extractMonoSamples(from buffers: [AVAudioPCMBuffer]) -> [Float] {
        var all = [Float]()
        for buffer in buffers {
            guard let data = buffer.floatChannelData?[0] else { continue }
            all.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        }
        return all
    }
}
