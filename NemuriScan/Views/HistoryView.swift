import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject private var viewModel: SleepViewModel
    @State private var selectedRange: TrendRange = .weekly
    private let isJP = Locale.current.language.languageCode?.identifier == "ja"

    enum TrendRange: String, CaseIterable {
        case weekly = "7D"
        case monthly = "30D"
    }

    var body: some View {
        NavigationStack {
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

                if viewModel.sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 64))
                            .foregroundColor(Color(red: 0.48, green: 0.62, blue: 0.88).opacity(0.5))
                        Text(isJP ? "まだ記録がありません" : "No recordings yet")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Trend picker
                            Picker("", selection: $selectedRange) {
                                ForEach(TrendRange.allCases, id: \.self) { range in
                                    Text(range.rawValue).tag(range)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            // Score trend chart
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionHeader(icon: "chart.bar.fill", title: isJP ? "スコア推移" : "Score Trend")
                                    ScoreTrendChart(sessions: trendSessions)
                                        .frame(height: 120)
                                }
                            }
                            .padding(.horizontal, 16)

                            // Session list
                            VStack(spacing: 10) {
                                ForEach(viewModel.sessions) { session in
                                    NavigationLink {
                                        ResultView(session: session)
                                            .environmentObject(viewModel)
                                    } label: {
                                        SessionRowView(session: session)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .navigationTitle(isJP ? "履歴" : "History")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var trendSessions: [SleepSession] {
        let days = selectedRange == .weekly ? 7 : 30
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return viewModel.sessions.filter { $0.startTime >= cutoff }
    }
}

struct SessionRowView: View {
    let session: SleepSession
    private let isJP = Locale.current.language.languageCode?.identifier == "ja"

    var body: some View {
        HStack(spacing: 14) {
            // Score circle
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.3), lineWidth: 3)
                    .frame(width: 52, height: 52)
                Circle()
                    .trim(from: 0, to: CGFloat(session.overallScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(-90))
                Text("\(session.overallScore)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.startTime.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Label(session.durationString, systemImage: "clock")
                    Label("\(session.snoreEvents.count)", systemImage: "waveform")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var scoreColor: Color {
        switch session.overallScore {
        case 80...: return .green
        case 60..<80: return Color(red: 0.48, green: 0.62, blue: 0.88)
        case 40..<60: return .yellow
        default: return .red
        }
    }
}

struct ScoreTrendChart: View {
    let sessions: [SleepSession]

    var body: some View {
        if #available(iOS 16.0, *) {
            Chart {
                ForEach(sessions) { session in
                    LineMark(
                        x: .value("Date", session.startTime),
                        y: .value("Score", session.overallScore)
                    )
                    .foregroundStyle(Color(red: 0.48, green: 0.62, blue: 0.88))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", session.startTime),
                        y: .value("Score", session.overallScore)
                    )
                    .foregroundStyle(Color(red: 0.91, green: 0.84, blue: 0.64))
                    .symbolSize(30)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel(format: .dateTime.day())
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel()
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
        }
    }
}
