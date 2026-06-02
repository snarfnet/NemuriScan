import Foundation

// MARK: - Enums

enum SleepStageType: String, Codable, CaseIterable {
    case awake = "awake"
    case light = "light"
    case deep = "deep"
    case rem = "rem"

    var localizedName: String {
        let isJP = Locale.current.language.languageCode?.identifier == "ja"
        switch self {
        case .awake: return isJP ? "覚醒" : "Awake"
        case .light: return isJP ? "浅い眠り" : "Light"
        case .deep: return isJP ? "深い眠り" : "Deep"
        case .rem: return isJP ? "レム睡眠" : "REM"
        }
    }
}

enum SnoreType: String, Codable {
    case simple = "simple"
    case obstructive = "obstructive"
    case mixed = "mixed"

    var localizedName: String {
        let isJP = Locale.current.language.languageCode?.identifier == "ja"
        switch self {
        case .simple: return isJP ? "単純いびき" : "Simple"
        case .obstructive: return isJP ? "閉塞性" : "Obstructive"
        case .mixed: return isJP ? "混合型" : "Mixed"
        }
    }
}

enum ApneaType: String, Codable {
    case obstructive = "obstructive"
    case central = "central"
    case mixed = "mixed"
}

enum ApneaRisk: String, Codable {
    case normal = "normal"
    case mild = "mild"
    case moderate = "moderate"
    case severe = "severe"

    var localizedName: String {
        let isJP = Locale.current.language.languageCode?.identifier == "ja"
        switch self {
        case .normal: return isJP ? "正常" : "Normal"
        case .mild: return isJP ? "軽度" : "Mild"
        case .moderate: return isJP ? "中等度" : "Moderate"
        case .severe: return isJP ? "重度" : "Severe"
        }
    }

    var color: String {
        switch self {
        case .normal: return "green"
        case .mild: return "yellow"
        case .moderate: return "orange"
        case .severe: return "red"
        }
    }
}

// MARK: - Value Types

struct SleepStage: Codable, Identifiable {
    var id = UUID()
    let type: SleepStageType
    let timestamp: Date
    let duration: TimeInterval
}

struct SnoreEvent: Codable, Identifiable {
    var id = UUID()
    let timestamp: Date
    let duration: TimeInterval
    let intensity: Double  // dB
    let type: SnoreType
}

struct ApneaEvent: Codable, Identifiable {
    var id = UUID()
    let timestamp: Date
    let duration: TimeInterval
    let type: ApneaType
}

struct BreathingPattern: Codable, Identifiable {
    var id = UUID()
    let timestamp: Date
    let rate: Double        // breaths per minute
    let regularity: Double  // 0.0 (irregular) to 1.0 (regular)
}

// MARK: - SleepSession

struct SleepSession: Codable, Identifiable {
    var id = UUID()
    let startTime: Date
    var endTime: Date?
    var stages: [SleepStage]
    var snoreEvents: [SnoreEvent]
    var apneaEvents: [ApneaEvent]
    var breathingPatterns: [BreathingPattern]
    var overallScore: Int  // 0-100

    var duration: TimeInterval {
        guard let end = endTime else { return 0 }
        return end.timeIntervalSince(startTime)
    }

    var durationString: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let isJP = Locale.current.language.languageCode?.identifier == "ja"
        if isJP {
            return "\(hours)時間\(minutes)分"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }

    var totalSnoreTime: TimeInterval {
        snoreEvents.reduce(0) { $0 + $1.duration }
    }

    var ahiEstimate: Double {
        guard duration > 0 else { return 0 }
        let hours = duration / 3600
        return Double(apneaEvents.count) / hours
    }

    var apneaRisk: ApneaRisk {
        let ahi = ahiEstimate
        if ahi < 5 { return .normal }
        if ahi < 15 { return .mild }
        if ahi < 30 { return .moderate }
        return .severe
    }

    static func empty() -> SleepSession {
        SleepSession(
            startTime: Date(),
            endTime: nil,
            stages: [],
            snoreEvents: [],
            apneaEvents: [],
            breathingPatterns: [],
            overallScore: 0
        )
    }
}
