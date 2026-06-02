import SwiftUI
import UIKit

struct ResultView: View {
    let session: SleepSession
    @EnvironmentObject private var viewModel: SleepViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var pdfData: Data?
    private let isJP = Locale.current.language.languageCode?.identifier == "ja"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.059, green: 0.043, blue: 0.176),
                    Color(red: 0.102, green: 0.067, blue: 0.271)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Score Gauge
                    ScoreGaugeView(score: session.overallScore)
                        .padding(.top, 24)

                    // Duration / Date
                    HStack(spacing: 20) {
                        InfoChip(
                            icon: "clock.fill",
                            text: session.durationString
                        )
                        InfoChip(
                            icon: "calendar",
                            text: session.startTime.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    .padding(.horizontal, 24)

                    // Sleep Stage Timeline
                    if !session.stages.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(
                                    icon: "moon.zzz.fill",
                                    title: isJP ? "睡眠ステージ" : "Sleep Stages"
                                )
                                SleepStageTimeline(
                                    stages: session.stages,
                                    totalDuration: session.duration
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Snoring Summary
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(icon: "waveform", title: isJP ? "いびき" : "Snoring")
                            HStack(spacing: 16) {
                                SnoreStat(
                                    label: isJP ? "回数" : "Events",
                                    value: "\(session.snoreEvents.count)"
                                )
                                SnoreStat(
                                    label: isJP ? "合計時間" : "Total Time",
                                    value: formatDuration(session.totalSnoreTime)
                                )
                                SnoreStat(
                                    label: isJP ? "平均強度" : "Avg dB",
                                    value: session.snoreEvents.isEmpty ? "—" :
                                        String(format: "%.0f dB",
                                               session.snoreEvents.map { $0.intensity }.reduce(0, +) / Double(session.snoreEvents.count))
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Apnea Risk
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(icon: "lungs.fill", title: isJP ? "無呼吸リスク" : "Apnea Risk")
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.apneaRisk.localizedName)
                                        .font(.system(size: 24, weight: .black, design: .rounded))
                                        .foregroundColor(apneaRiskColor(session.apneaRisk))
                                    Text(isJP
                                        ? "推定AHI: \(String(format: "%.1f", session.ahiEstimate)) 回/時"
                                        : "Est. AHI: \(String(format: "%.1f", session.ahiEstimate))/hr"
                                    )
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.65))
                                }
                                Spacer()
                                ApneaRiskBadge(risk: session.apneaRisk)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Breathing Rate chart
                    if !session.breathingPatterns.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(icon: "chart.line.uptrend.xyaxis", title: isJP ? "呼吸数" : "Breathing Rate")
                                BreathingRateChart(patterns: session.breathingPatterns)
                                    .frame(height: 80)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Posture Advice
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(icon: "lightbulb.fill", title: isJP ? "アドバイス" : "Advice")
                            ForEach(adviceItems(for: session), id: \.self) { advice in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(red: 0.91, green: 0.84, blue: 0.64))
                                        .padding(.top, 3)
                                    Text(advice)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }

                            // Amazon affiliate pillow link
                            Link(destination: URL(string: "https://www.amazon.co.jp/s?k=%E3%81%84%E3%81%B3%E3%81%8D%E6%9E%95&tag=kixyouhueizou-22")!) {
                                HStack(spacing: 6) {
                                    Image(systemName: "cart.fill")
                                    Text(isJP ? "おすすめのいびき対策枕を見る" : "Browse Recommended Pillows")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(Color(red: 0.48, green: 0.62, blue: 0.88))
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // PDF Report button
                    Button {
                        viewModel.showRewardedForPDF { rewarded in
                            if rewarded {
                                generateAndSharePDF()
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: viewModel.isSubscribed ? "doc.text.fill" : "play.circle.fill")
                            Text(isJP ? "PDFレポート" : "PDF Report")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.27, green: 0.27, blue: 0.78),
                                    Color(red: 0.48, green: 0.62, blue: 0.88)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(isJP ? "睡眠レポート" : "Sleep Report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.showInterstitialBeforeResult()
        }
        .sheet(isPresented: $showShareSheet) {
            if let data = pdfData {
                ShareSheet(items: [data])
            }
        }
    }

    // MARK: - Helpers

    private func generateAndSharePDF() {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let title = isJP ? "ネムリスキャン 睡眠分析レポート" : "NemuriScan Sleep Analysis Report"
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.black
            ]
            title.draw(at: CGPoint(x: 40, y: 40), withAttributes: titleAttrs)

            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.darkGray
            ]
            var y: CGFloat = 80

            func drawLine(_ text: String) {
                text.draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttrs)
                y += 22
            }

            let dateStr = session.startTime.formatted(date: .complete, time: .shortened)
            drawLine(isJP ? "日付: \(dateStr)" : "Date: \(dateStr)")
            drawLine(isJP ? "睡眠時間: \(session.durationString)" : "Duration: \(session.durationString)")
            drawLine(isJP ? "睡眠スコア: \(session.overallScore)/100" : "Sleep Score: \(session.overallScore)/100")
            drawLine(isJP ? "いびき回数: \(session.snoreEvents.count)" : "Snore Events: \(session.snoreEvents.count)")
            drawLine(isJP ? "無呼吸リスク: \(session.apneaRisk.localizedName)" : "Apnea Risk: \(session.apneaRisk.localizedName)")
            drawLine(isJP ? "推定AHI: \(String(format: "%.1f", session.ahiEstimate)) 回/時" : "Est. AHI: \(String(format: "%.1f", session.ahiEstimate))/hr")

            y += 20
            let disclaimer = isJP
                ? "※このレポートは医療診断ではありません。症状が気になる場合は医師に相談してください。"
                : "Disclaimer: This report is not a medical diagnosis. Consult a doctor if you have concerns."
            let smallAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 10),
                .foregroundColor: UIColor.gray
            ]
            disclaimer.draw(in: CGRect(x: 40, y: y, width: 515, height: 60), withAttributes: smallAttrs)
        }
        pdfData = data
        showShareSheet = true
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    private func apneaRiskColor(_ risk: ApneaRisk) -> Color {
        switch risk {
        case .normal: return .green
        case .mild: return .yellow
        case .moderate: return Color(red: 1, green: 0.6, blue: 0)
        case .severe: return .red
        }
    }

    private func adviceItems(for session: SleepSession) -> [String] {
        var items = [String]()
        if session.snoreEvents.count > 10 {
            items.append(isJP ? "横向き寝がいびきを軽減します" : "Try sleeping on your side to reduce snoring")
        }
        if session.apneaRisk == .moderate || session.apneaRisk == .severe {
            items.append(isJP ? "医師に相談することをおすすめします" : "Consider consulting a doctor about sleep apnea")
        }
        if session.duration < 6 * 3600 {
            items.append(isJP ? "7〜8時間の睡眠を目指しましょう" : "Aim for 7–8 hours of sleep")
        }
        if items.isEmpty {
            items.append(isJP ? "良い睡眠が取れています。この調子を続けましょう！" : "Great sleep! Keep it up.")
        }
        return items
    }
}

// MARK: - Sub-components

struct ScoreGaugeView: View {
    let score: Int
    private let isJP = Locale.current.language.languageCode?.identifier == "ja"

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 14)
                .frame(width: 160, height: 160)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.27, green: 0.27, blue: 0.78),
                            Color(red: 0.48, green: 0.62, blue: 0.88),
                            Color(red: 0.91, green: 0.84, blue: 0.64)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text("\(score)")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(isJP ? "睡眠スコア" : "Sleep Score")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(Color(red: 0.48, green: 0.62, blue: 0.88))
    }
}

struct InfoChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

struct SnoreStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }
}

struct ApneaRiskBadge: View {
    let risk: ApneaRisk

    var body: some View {
        Text(risk.localizedName)
            .font(.system(size: 13, weight: .black))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch risk {
        case .normal: return .green.opacity(0.8)
        case .mild: return .yellow.opacity(0.8)
        case .moderate: return Color(red: 1, green: 0.6, blue: 0).opacity(0.8)
        case .severe: return .red.opacity(0.8)
        }
    }
}

struct BreathingRateChart: View {
    let patterns: [BreathingPattern]

    var body: some View {
        GeometryReader { geo in
            let rates = patterns.map { $0.rate }
            let minRate = rates.min() ?? 10
            let maxRate = rates.max() ?? 20
            let range = max(1, maxRate - minRate)

            Path { path in
                guard !patterns.isEmpty else { return }
                let stepX = geo.size.width / CGFloat(max(1, patterns.count - 1))
                for (i, pattern) in patterns.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height * (1 - CGFloat((pattern.rate - minRate) / range))
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                Color(red: 0.48, green: 0.62, blue: 0.88),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
