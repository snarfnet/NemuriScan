import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SleepViewModel()

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

            TabView {
                RecordView()
                    .tabItem {
                        Label(
                            Locale.current.language.languageCode?.identifier == "ja" ? "記録" : "Record",
                            systemImage: "moon.fill"
                        )
                    }

                HistoryView()
                    .tabItem {
                        Label(
                            Locale.current.language.languageCode?.identifier == "ja" ? "履歴" : "History",
                            systemImage: "clock.fill"
                        )
                    }

                ReportView()
                    .tabItem {
                        Label(
                            Locale.current.language.languageCode?.identifier == "ja" ? "レポート" : "Report",
                            systemImage: "doc.text.fill"
                        )
                    }
            }
            .tint(Color(red: 0.48, green: 0.62, blue: 0.88))
        }
        .environmentObject(viewModel)
        .sheet(isPresented: $viewModel.showPaywall) {
            PaywallView()
                .environmentObject(viewModel)
        }
    }
}
