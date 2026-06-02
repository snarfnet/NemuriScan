import AVFoundation
import Accelerate

/// Sleep stage estimation from audio.
/// Based on Nakano et al. (2014) breathing rate estimation and
/// Beattie et al. (2017) cardiac/accelerometer stage classification rules.
class SleepStageEstimator {
    private let sampleRate: Double = 44100
    private let segmentDuration: TimeInterval = 30  // 30-second epochs

    // Breathing rate band: 0.1–0.6 Hz (6–36 breaths/min)
    private let breathingLow: Double = 0.1
    private let breathingHigh: Double = 0.6

    // MARK: - Public

    func estimateStages(
        from buffers: [AVAudioPCMBuffer],
        sessionStart: Date
    ) -> ([SleepStage], [BreathingPattern]) {
        let samples = extractMonoSamples(from: buffers)
        guard !samples.isEmpty else { return ([], []) }

        let samplesPerSegment = Int(segmentDuration * sampleRate)
        let segmentCount = max(1, samples.count / samplesPerSegment)

        var stages: [SleepStage] = []
        var breathingPatterns: [BreathingPattern] = []

        for i in 0..<segmentCount {
            let start = i * samplesPerSegment
            let end = min(start + samplesPerSegment, samples.count)
            let segment = Array(samples[start..<end])

            let timestamp = sessionStart.addingTimeInterval(Double(i) * segmentDuration)
            let breathingRate = estimateBreathingRate(segment)
            let regularity = estimateBreathingRegularity(segment)
            let movementLevel = estimateMovementLevel(segment)

            let stage = classifyStage(
                breathingRate: breathingRate,
                regularity: regularity,
                movementLevel: movementLevel,
                isFirstSegment: i < 2
            )

            stages.append(SleepStage(
                type: stage,
                timestamp: timestamp,
                duration: segmentDuration
            ))

            breathingPatterns.append(BreathingPattern(
                timestamp: timestamp,
                rate: breathingRate,
                regularity: regularity
            ))
        }

        return (mergeConsecutiveStages(stages), breathingPatterns)
    }

    // MARK: - Breathing Rate Estimation

    private func estimateBreathingRate(_ samples: [Float]) -> Double {
        // Downsample to 100 Hz for breathing analysis
        let targetRate: Double = 100
        let decimationFactor = Int(sampleRate / targetRate)
        var decimated = [Float]()
        var i = 0
        while i < samples.count {
            decimated.append(samples[i])
            i += decimationFactor
        }

        // Low-pass filter to isolate breathing envelope
        let envelope = computeEnvelope(decimated)

        // Count zero crossings of mean-subtracted envelope
        var mean: Float = 0
        vDSP_meanv(envelope, 1, &mean, vDSP_Length(envelope.count))
        let centered = envelope.map { $0 - mean }

        var crossings = 0
        for j in 1..<centered.count {
            if centered[j - 1] < 0 && centered[j] >= 0 {
                crossings += 1
            }
        }

        let durationSeconds = Double(samples.count) / sampleRate
        let breathsPerMinute = durationSeconds > 0 ? Double(crossings) / durationSeconds * 60 : 15
        return max(4, min(40, breathsPerMinute))
    }

    private func estimateBreathingRegularity(_ samples: [Float]) -> Double {
        // CV (coefficient of variation) of inter-breath intervals
        // Lower CV = more regular
        let targetRate: Double = 100
        let decimationFactor = max(1, Int(sampleRate / targetRate))
        var decimated = [Float]()
        var i = 0
        while i < samples.count {
            decimated.append(samples[i])
            i += decimationFactor
        }

        let envelope = computeEnvelope(decimated)
        var mean: Float = 0
        vDSP_meanv(envelope, 1, &mean, vDSP_Length(envelope.count))
        let centered = envelope.map { $0 - mean }

        var peakTimes = [Double]()
        for j in 1..<(centered.count - 1) {
            if centered[j] > centered[j - 1] && centered[j] > centered[j + 1] && centered[j] > 0 {
                peakTimes.append(Double(j) / targetRate)
            }
        }

        guard peakTimes.count > 2 else { return 0.5 }

        var intervals = [Double]()
        for j in 1..<peakTimes.count {
            intervals.append(peakTimes[j] - peakTimes[j - 1])
        }

        let meanInterval = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { pow($0 - meanInterval, 2) }.reduce(0, +) / Double(intervals.count)
        let stdDev = sqrt(variance)
        let cv = meanInterval > 0 ? stdDev / meanInterval : 1.0

        // Convert CV to regularity score: CV=0 → 1.0, CV=1 → 0.0
        return max(0, min(1, 1 - cv))
    }

    private func estimateMovementLevel(_ samples: [Float]) -> Double {
        // High-frequency transients indicate body movement
        let hiPassCutoff: Double = 2000
        let binResolution = sampleRate / Double(samples.count)
        let cutoffBin = Int(hiPassCutoff / binResolution)

        let fftSize = min(samples.count, 4096)
        let paddedSamples = Array(samples.prefix(fftSize)) + [Float](
            repeating: 0,
            count: max(0, fftSize - samples.count)
        )

        var real = paddedSamples
        var imag = [Float](repeating: 0, count: fftSize)
        var hiEnergy: Float = 0
        var totalEnergy: Float = 0

        for k in 0..<(fftSize / 2) {
            let mag = sqrt(real[k] * real[k] + imag[k] * imag[k])
            totalEnergy += mag
            if k > cutoffBin {
                hiEnergy += mag
            }
        }

        return totalEnergy > 0 ? Double(hiEnergy / totalEnergy) : 0
    }

    // MARK: - Stage Classification

    private func classifyStage(
        breathingRate: Double,
        regularity: Double,
        movementLevel: Double,
        isFirstSegment: Bool
    ) -> SleepStageType {
        // Rule-based classification (Beattie et al. 2017 simplified)
        if movementLevel > 0.4 || isFirstSegment {
            return .awake
        }

        // Deep sleep: slow (12-16 bpm), regular, low movement
        if breathingRate >= 12 && breathingRate <= 16 && regularity > 0.7 && movementLevel < 0.15 {
            return .deep
        }

        // REM: irregular breathing, low movement
        if regularity < 0.4 && movementLevel < 0.2 {
            return .rem
        }

        // Light sleep: moderate regularity
        if regularity >= 0.4 {
            return .light
        }

        return .awake
    }

    // MARK: - Helpers

    private func computeEnvelope(_ samples: [Float]) -> [Float] {
        // Rectify and low-pass smooth
        let rectified = samples.map { abs($0) }
        let windowSize = 50
        var smoothed = [Float](repeating: 0, count: rectified.count)
        for i in 0..<rectified.count {
            let lo = max(0, i - windowSize / 2)
            let hi = min(rectified.count, i + windowSize / 2)
            var avg: Float = 0
            vDSP_meanv(Array(rectified[lo..<hi]), 1, &avg, vDSP_Length(hi - lo))
            smoothed[i] = avg
        }
        return smoothed
    }

    private func extractMonoSamples(from buffers: [AVAudioPCMBuffer]) -> [Float] {
        var all = [Float]()
        for buffer in buffers {
            guard let data = buffer.floatChannelData?[0] else { continue }
            all.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        }
        return all
    }

    private func mergeConsecutiveStages(_ stages: [SleepStage]) -> [SleepStage] {
        guard !stages.isEmpty else { return [] }
        var merged = [SleepStage]()
        var current = stages[0]
        var accumulatedDuration = current.duration

        for i in 1..<stages.count {
            let next = stages[i]
            if next.type == current.type {
                accumulatedDuration += next.duration
            } else {
                merged.append(SleepStage(type: current.type, timestamp: current.timestamp, duration: accumulatedDuration))
                current = next
                accumulatedDuration = next.duration
            }
        }
        merged.append(SleepStage(type: current.type, timestamp: current.timestamp, duration: accumulatedDuration))
        return merged
    }
}
