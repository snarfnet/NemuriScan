import SwiftUI

struct RecordView: View {
    @EnvironmentObject private var viewModel: SleepViewModel
    @State private var moonPulse = false
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

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 4) {
                    Text(isJP ? "ネムリスキャン" : "NemuriScan")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(isJP ? "睡眠分析を開始してください" : "Sleep Analysis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.48, green: 0.62, blue: 0.88))
                }
                .padding(.top, 20)
                .padding(.bottom, 24)

                // Moon Button
                ZStack {
                    // Outer glow rings
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(
                                Color(red: 0.48, green: 0.62, blue: 0.88).opacity(0.15 - Double(i) * 0.04),
                                lineWidth: 1
                            )
                            .frame(width: CGFloat(180 + i * 40), height: CGFloat(180 + i * 40))
                            .scaleEffect(viewModel.isRecording && moonPulse ? 1.06 : 1.0)
                            .animation(
                                .easeInOut(duration: 2.0).repeatForever(autoreverses: true).delay(Double(i) * 0.3),
                                value: moonPulse
                            )
                    }

                    Button {
                        if viewModel.isRecording {
                            viewModel.stopRecording()
                        } else {
                            viewModel.startRecording()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(red: 0.18, green: 0.15, blue: 0.42),
                                            Color(red: 0.059, green: 0.043, blue: 0.176)
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 80
                                    )
                                )
                                .frame(width: 160, height: 160)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.48, green: 0.62, blue: 0.88),
                                                    Color(red: 0.91, green: 0.84, blue: 0.64)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2.5
                                        )
                                )
                                .shadow(
                                    color: Color(red: 0.48, green: 0.62, blue: 0.88).opacity(0.4),
                                    radius: viewModel.isRecording ? 24 : 12
                                )

                            VStack(spacing: 8) {
                                Image(systemName: viewModel.isRecording ? "stop.fill" : "moon.stars.fill")
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundColor(
                                        viewModel.isRecording
                                            ? Color(red: 0.95, green: 0.4, blue: 0.3)
                                            : Color(red: 0.91, green: 0.84, blue: 0.64)
                                    )
                                Text(viewModel.isRecording
                                    ? (isJP ? "停止して分析" : "Stop & Analyze")
                                    : (isJP ? "睡眠を開始" : "Start Sleep")
                                )
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                .frame(height: 280)
                .onAppear { moonPulse = true }

                // Timer
                if viewModel.isRecording {
                    Text(viewModel.elapsedTimeString)
                        .font(.system(size: 40, weight: .thin, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.top, 8)
                }

                // Audio level visualizer
                if viewModel.isRecording {
                    AudioLevelView(level: viewModel.audioLevel)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }

                Spacer()

                // Live stats
                if viewModel.isRecording {
                    HStack(spacing: 16) {
                        LiveStatCard(
                            icon: "waveform",
                            value: "\(viewModel.liveSnoreCount)",
                            label: isJP ? "いびき回数" : "Snores"
                        )
                        LiveStatCard(
                            icon: "lungs.fill",
                            value: String(format: "%.0f", viewModel.liveBreathingRate),
                            label: isJP ? "呼吸/分" : "Breaths/min"
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }

                // Banner Ad
                BannerAdView(adUnitID: "ca-app-pub-9404799280370656/1971823720")
                    .frame(height: 50)
                    .background(Color.black.opacity(0.3))
            }
        }
    }
}

struct LiveStatCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(red: 0.48, green: 0.62, blue: 0.88))
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
