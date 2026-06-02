import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var viewModel: SleepViewModel
    @State private var showShareSheet = false
    @State private var pdfData: Data?
    private let isJP = Locale.current.language.languageCode?.identifier == "ja"

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

                if let latest = viewModel.sessions.first {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Disclaimer
                            GlassCard {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow)
                                    Text(isJP
                                        ? "このレポートは医療診断ではありません。参考情報としてご利用ください。"
                                        : "This report is not a medical diagnosis. For informational purposes only."
                                    )
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.75))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                            // Report content
                            ReportSummaryCard(session: latest)
                                .padding(.horizontal, 16)

                            // Export button
                            Button {
                                generateAndSharePDF(for: latest)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text(isJP ? "PDFをエクスポート" : "Export PDF")
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
                    .sheet(isPresented: $showShareSheet) {
                        if let data = pdfData {
                            ShareSheet(items: [data])
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 64))
                            .foregroundColor(Color(red: 0.48, green: 0.62, blue: 0.88).opacity(0.5))
                        Text(isJP ? "レポートがありません" : "No report available")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .navigationTitle(isJP ? "レポート" : "Report")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func generateAndSharePDF(for session: SleepSession) {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let title = isJP ? "ネムリスキャン 睡眠分析レポート" : "NemuriScan Sleep Analysis Report"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.black
            ]
            title.draw(at: CGPoint(x: 40, y: 40), withAttributes: attrs)

            let dateStr = session.startTime.formatted(date: .complete, time: .shortened)
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.darkGray
            ]
            var y: CGFloat = 80

            func drawLine(_ text: String) {
                text.draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttrs)
                y += 22
            }

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
            disclaimer.draw(
                in: CGRect(x: 40, y: y, width: 515, height: 60),
                withAttributes: smallAttrs
            )
        }
        pdfData = data
        showShareSheet = true
    }
}

struct ReportSummaryCard: View {
    let session: SleepSession
    private let isJP = Locale.current.language.languageCode?.identifier == "ja"

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(icon: "doc.text.fill", title: isJP ? "最新セッション" : "Latest Session")

                HStack {
                    ScoreGaugeView(score: session.overallScore)
                        .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 8) {
                        ReportRow(label: isJP ? "日付" : "Date", value: session.startTime.formatted(date: .abbreviated, time: .shortened))
                        ReportRow(label: isJP ? "時間" : "Duration", value: session.durationString)
                        ReportRow(label: isJP ? "いびき" : "Snores", value: "\(session.snoreEvents.count)")
                        ReportRow(label: isJP ? "無呼吸リスク" : "Apnea Risk", value: session.apneaRisk.localizedName)
                        ReportRow(label: "AHI", value: String(format: "%.1f/hr", session.ahiEstimate))
                    }
                    .padding(.leading, 12)
                }
            }
        }
    }
}

struct ReportRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
