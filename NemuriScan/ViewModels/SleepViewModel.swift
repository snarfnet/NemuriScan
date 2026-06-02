import AVFoundation
import Combine
import SwiftUI

@MainActor
class SleepViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var currentSession: SleepSession?
    @Published var sessions: [SleepSession] = []
    @Published var audioLevel: Float = 0.0
    @Published var elapsedTime: TimeInterval = 0
    @Published var liveSnoreCount = 0
    @Published var liveBreathingRate: Double = 0
    @Published var selectedSession: SleepSession?
    @Published var showPaywall = false

    let interstitialManager = InterstitialAdManager()
    let rewardedManager = RewardedAdManager()

    private let subscriptionManager = SubscriptionManager()
    private let recorder = AudioRecorder()
    private let snoreDetector = SnoreDetector()
    private let stageEstimator = SleepStageEstimator()
    private let apneaScreener = ApneaScreener()

    private var timer: Timer?
    private var recordingStartTime: Date?
    private var collectedBuffers: [AVAudioPCMBuffer] = []

    private let sessionsKey = "nemuriscan.sessions"

    init() {
        loadSessions()
        setupRecorderCallbacks()
    }

    var isSubscribed: Bool { subscriptionManager.isSubscribed }

    // MARK: - Ad helpers

    func showInterstitialBeforeResult() {
        guard !subscriptionManager.isSubscribed else { return }
        interstitialManager.showIfReady()
    }

    func showRewardedForPDF(completion: @escaping (Bool) -> Void) {
        guard !subscriptionManager.isSubscribed else {
            completion(true)
            return
        }
        rewardedManager.show(completion: completion)
    }

    // MARK: - Recording

    func startRecording() {
        recorder.requestPermission { [weak self] granted in
            guard let self, granted else { return }
            Task { @MainActor in
                self.currentSession = SleepSession.empty()
                self.collectedBuffers = []
                self.liveSnoreCount = 0
                self.liveBreathingRate = 0
                self.elapsedTime = 0
                self.recordingStartTime = Date()
                self.recorder.startRecording()
                self.isRecording = true
                self.startTimer()
            }
        }
    }

    func stopRecording() {
        recorder.stopRecording()
        isRecording = false
        timer?.invalidate()
        timer = nil

        guard var session = currentSession else { return }
        session.endTime = Date()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let buffers = await MainActor.run { self.collectedBuffers }
            let start = session.startTime
            let (stages, breathing) = self.stageEstimator.estimateStages(from: buffers, sessionStart: start)
            let snores = self.snoreDetector.detectSnores(in: buffers, sessionStart: start)
            let apneas = self.apneaScreener.detectApneaEvents(from: buffers, sessionStart: start)
            let score = self.calculateScore(stages: stages, snores: snores, apneas: apneas, duration: session.duration)

            await MainActor.run {
                session.stages = stages
                session.breathingPatterns = breathing
                session.snoreEvents = snores
                session.apneaEvents = apneas
                session.overallScore = score
                self.currentSession = session
                self.sessions.insert(session, at: 0)
                self.saveSessions()
            }
        }
    }

    // MARK: - Score Calculation

    nonisolated private func calculateScore(
        stages: [SleepStage],
        snores: [SnoreEvent],
        apneas: [ApneaEvent],
        duration: TimeInterval
    ) -> Int {
        var score = 100

        // Penalize for low deep sleep ratio
        let deepTime = stages.filter { $0.type == .deep }.reduce(0) { $0 + $1.duration }
        let deepRatio = duration > 0 ? deepTime / duration : 0
        if deepRatio < 0.15 { score -= 15 }
        else if deepRatio < 0.20 { score -= 8 }

        // Penalize for snoring
        let totalSnoreTime = snores.reduce(0) { $0 + $1.duration }
        let snoreRatio = duration > 0 ? totalSnoreTime / duration : 0
        score -= Int(snoreRatio * 30)

        // Penalize for apnea risk
        let hours = duration / 3600
        let ahi = hours > 0 ? Double(apneas.count) / hours : 0
        if ahi >= 30 { score -= 30 }
        else if ahi >= 15 { score -= 20 }
        else if ahi >= 5 { score -= 10 }

        // Penalize for short sleep
        if duration < 6 * 3600 { score -= 10 }

        return max(0, min(100, score))
    }

    // MARK: - Session Persistence

    func deleteSession(_ session: SleepSession) {
        sessions.removeAll { $0.id == session.id }
        saveSessions()
    }

    private func saveSessions() {
        let limited = Array(sessions.prefix(90))
        if let data = try? JSONEncoder().encode(limited) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }

    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let loaded = try? JSONDecoder().decode([SleepSession].self, from: data) else { return }
        sessions = loaded
    }

    // MARK: - Helpers

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            Task { @MainActor in
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func setupRecorderCallbacks() {
        recorder.onAudioBuffer = { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in
                self.collectedBuffers.append(buffer)
                self.audioLevel = self.recorder.audioLevel
            }
        }

        recorder.onChunkReady = { [weak self] chunks in
            guard let self else { return }
            Task { @MainActor in
                // Update live stats from latest chunk
                if let session = self.currentSession {
                    let snores = self.snoreDetector.detectSnores(in: chunks, sessionStart: session.startTime)
                    self.liveSnoreCount += snores.count
                    let (_, breathing) = self.stageEstimator.estimateStages(from: chunks, sessionStart: session.startTime)
                    if let last = breathing.last {
                        self.liveBreathingRate = last.rate
                    }
                }
            }
        }
    }

    var elapsedTimeString: String {
        let total = Int(elapsedTime)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
