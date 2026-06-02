import AVFoundation
import Accelerate

/// Snore detection using spectral analysis and MFCC features.
/// Based on Cavusoglu et al. (2007) spectral feature approach and
/// Lim et al. (2018) MFCC-based classification.
class SnoreDetector {
    private let sampleRate: Double = 44100
    private let fftSize = 4096
    private let hopSize = 2048

    // Snoring frequency band: 100–800 Hz
    private let snoreFreqLow: Double = 100
    private let snoreFreqHigh: Double = 800

    // Energy threshold for snore detection (empirically tuned)
    private let snoreEnergyThreshold: Float = 0.15
    private let minSnoreDuration: TimeInterval = 0.3

    private var vDSPSetup: vDSP_DFT_Setup?
    private let numMFCC = 13
    private let numMelFilters = 26

    init() {
        vDSPSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
    }

    deinit {
        if let setup = vDSPSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    // MARK: - Public

    func detectSnores(in buffers: [AVAudioPCMBuffer], sessionStart: Date) -> [SnoreEvent] {
        var events: [SnoreEvent] = []
        var currentSnoreStart: Date?
        var currentIntensity: Double = 0
        var frameOffset: Double = 0

        for buffer in buffers {
            guard let channelData = buffer.floatChannelData?[0] else { continue }
            let frameCount = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
            let hopCount = max(1, (frameCount - fftSize) / hopSize)

            for hop in 0..<hopCount {
                let start = hop * hopSize
                let end = min(start + fftSize, frameCount)
                guard end - start == fftSize else { continue }

                let frame = Array(samples[start..<end])
                let windowed = applyHannWindow(frame)
                let spectrum = computeFFTMagnitude(windowed)
                let snoreEnergy = snoreBandEnergy(spectrum)
                let spectralCentroid = computeSpectralCentroid(spectrum)

                let timeOffset = frameOffset + Double(start) / sampleRate
                let timestamp = sessionStart.addingTimeInterval(timeOffset)

                if snoreEnergy > snoreEnergyThreshold {
                    if currentSnoreStart == nil {
                        currentSnoreStart = timestamp
                        currentIntensity = Double(snoreEnergy)
                    } else {
                        currentIntensity = max(currentIntensity, Double(snoreEnergy))
                    }
                } else {
                    if let snoreStart = currentSnoreStart {
                        let duration = timestamp.timeIntervalSince(snoreStart)
                        if duration >= minSnoreDuration {
                            let type = classifySnoreType(
                                centroid: spectralCentroid,
                                energy: Float(currentIntensity)
                            )
                            let dbLevel = energyToDecibels(Float(currentIntensity))
                            events.append(SnoreEvent(
                                timestamp: snoreStart,
                                duration: duration,
                                intensity: Double(dbLevel),
                                type: type
                            ))
                        }
                        currentSnoreStart = nil
                        currentIntensity = 0
                    }
                }
            }
            frameOffset += Double(frameCount) / sampleRate
        }

        return events
    }

    // MARK: - MFCC

    func extractMFCC(from frame: [Float]) -> [Float] {
        let windowed = applyHannWindow(frame)
        let spectrum = computeFFTMagnitude(windowed)
        let melEnergies = applyMelFilterBank(spectrum)
        let logMel = melEnergies.map { logf(max($0, 1e-10)) }
        return dct(logMel, count: numMFCC)
    }

    // MARK: - Private DSP

    private func applyHannWindow(_ samples: [Float]) -> [Float] {
        var windowed = samples
        var window = [Float](repeating: 0, count: samples.count)
        vDSP_hann_window(&window, vDSP_Length(samples.count), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(samples.count))
        return windowed
    }

    private func computeFFTMagnitude(_ samples: [Float]) -> [Float] {
        let n = samples.count
        let log2n = vDSP_Length(log2(Float(n)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: n / 2)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Split samples into even/odd for split complex
        var realp = [Float](repeating: 0, count: n / 2)
        var imagp = [Float](repeating: 0, count: n / 2)
        samples.withUnsafeBufferPointer { samplesPtr in
            var dspInput = DSPSplitComplex(realp: &realp, imagp: &imagp)
            samplesPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexPtr in
                vDSP_ctoz(complexPtr, 2, &dspInput, 1, vDSP_Length(n / 2))
            }
        }

        // Perform FFT
        var splitComplex = DSPSplitComplex(realp: &realp, imagp: &imagp)
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

        // Compute magnitudes
        var magnitudes = [Float](repeating: 0, count: n / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n / 2))

        // Square root for actual magnitude
        var output = [Float](repeating: 0, count: n / 2)
        vvsqrtf(&output, &magnitudes, [Int32(n / 2)])
        return output
    }

    private func snoreBandEnergy(_ spectrum: [Float]) -> Float {
        let binResolution = sampleRate / Double(fftSize)
        let lowBin = Int(snoreFreqLow / binResolution)
        let highBin = min(Int(snoreFreqHigh / binResolution), spectrum.count - 1)
        guard lowBin < highBin else { return 0 }

        let bandSlice = Array(spectrum[lowBin...highBin])
        var totalEnergy: Float = 0
        var bandEnergy: Float = 0
        vDSP_sve(spectrum, 1, &totalEnergy, vDSP_Length(spectrum.count))
        vDSP_sve(bandSlice, 1, &bandEnergy, vDSP_Length(bandSlice.count))

        guard totalEnergy > 0 else { return 0 }
        return bandEnergy / totalEnergy
    }

    private func computeSpectralCentroid(_ spectrum: [Float]) -> Double {
        let binResolution = sampleRate / Double(fftSize)
        var weightedSum: Double = 0
        var totalMag: Double = 0
        for (i, mag) in spectrum.enumerated() {
            let freq = Double(i) * binResolution
            weightedSum += freq * Double(mag)
            totalMag += Double(mag)
        }
        return totalMag > 0 ? weightedSum / totalMag : 0
    }

    private func classifySnoreType(centroid: Double, energy: Float) -> SnoreType {
        // Low centroid (<300Hz) + high energy → obstructive
        // High centroid (>500Hz) → mixed
        // Otherwise simple
        if centroid < 300 && energy > 0.3 {
            return .obstructive
        } else if centroid > 500 {
            return .mixed
        }
        return .simple
    }

    private func energyToDecibels(_ energy: Float) -> Float {
        return 20 * log10(max(energy, 1e-7)) + 94  // approximate SPL
    }

    private func applyMelFilterBank(_ spectrum: [Float]) -> [Float] {
        let nyquist = sampleRate / 2
        let melLow = hzToMel(0)
        let melHigh = hzToMel(nyquist)
        let melStep = (melHigh - melLow) / Double(numMelFilters + 1)

        var filterBankOutput = [Float](repeating: 0, count: numMelFilters)
        let binResolution = sampleRate / Double(fftSize)

        for m in 0..<numMelFilters {
            let melCenter = melLow + Double(m + 1) * melStep
            let melLeft = melCenter - melStep
            let melRight = melCenter + melStep

            let fLeft = melToHz(melLeft)
            let fCenter = melToHz(melCenter)
            let fRight = melToHz(melRight)

            var energy: Float = 0
            for k in 0..<spectrum.count {
                let freq = Double(k) * binResolution
                var weight: Double = 0
                if freq >= fLeft && freq <= fCenter {
                    weight = (freq - fLeft) / (fCenter - fLeft)
                } else if freq > fCenter && freq <= fRight {
                    weight = (fRight - freq) / (fRight - fCenter)
                }
                energy += spectrum[k] * Float(weight)
            }
            filterBankOutput[m] = energy
        }
        return filterBankOutput
    }

    private func dct(_ input: [Float], count: Int) -> [Float] {
        let n = input.count
        var output = [Float](repeating: 0, count: count)
        for k in 0..<count {
            var sum: Float = 0
            for n_i in 0..<n {
                sum += input[n_i] * cos(Float.pi * Float(k) * (Float(n_i) + 0.5) / Float(n))
            }
            output[k] = sum
        }
        return output
    }

    private func hzToMel(_ hz: Double) -> Double {
        return 2595 * log10(1 + hz / 700)
    }

    private func melToHz(_ mel: Double) -> Double {
        return 700 * (pow(10, mel / 2595) - 1)
    }
}
