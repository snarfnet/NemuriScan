import StoreKit
import SwiftUI

@MainActor
class SubscriptionManager: ObservableObject {
    @Published var isSubscribed = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let productID = "com.tokyonasu.nemuriscan.monthly"
    private var currentTransaction: StoreKit.Transaction?

    init() {
        Task {
            await checkSubscriptionStatus()
            await listenForTransactions()
        }
    }

    func checkSubscriptionStatus() async {
        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == productID {
                    isSubscribed = !transaction.isUpgraded
                    currentTransaction = transaction
                }
            case .unverified:
                break
            }
        }
    }

    func purchase() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                errorMessage = Locale.current.language.languageCode?.identifier == "ja"
                    ? "商品情報の取得に失敗しました"
                    : "Failed to load product"
                return
            }

            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    isSubscribed = true
                case .unverified:
                    errorMessage = Locale.current.language.languageCode?.identifier == "ja"
                        ? "購入の検証に失敗しました"
                        : "Purchase verification failed"
                }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        try? await AppStore.sync()
        await checkSubscriptionStatus()
    }

    private func listenForTransactions() async {
        for await result in StoreKit.Transaction.updates {
            switch result {
            case .verified(let transaction):
                if transaction.productID == productID {
                    isSubscribed = !transaction.isUpgraded
                    await transaction.finish()
                }
            case .unverified:
                break
            }
        }
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    @StateObject private var subscriptionManager = SubscriptionManager()
    @Environment(\.dismiss) private var dismiss
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

            VStack(spacing: 28) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 56))
                        .foregroundColor(Color(red: 0.91, green: 0.84, blue: 0.64))

                    Text(isJP ? "プレミアムにアップグレード" : "Upgrade to Premium")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(isJP ? "月額100円" : "¥100 / month")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(red: 0.48, green: 0.62, blue: 0.88))
                }
                .padding(.top, 40)

                // Features
                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "chart.bar.fill",    text: isJP ? "詳細な睡眠分析" : "Detailed Sleep Analysis")
                    FeatureRow(icon: "doc.text.fill",     text: isJP ? "PDFレポート生成" : "PDF Report Export")
                    FeatureRow(icon: "xmark.circle.fill", text: isJP ? "広告なし" : "No Ads")
                    FeatureRow(icon: "clock.arrow.circlepath", text: isJP ? "90日間の履歴保存" : "90-Day History")
                }
                .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    if subscriptionManager.isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.4)
                    } else {
                        Button {
                            Task { await subscriptionManager.purchase() }
                        } label: {
                            Text(isJP ? "今すぐ始める" : "Start Now")
                                .font(.system(size: 18, weight: .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
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
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .padding(.horizontal, 24)

                        Button {
                            Task { await subscriptionManager.restore() }
                        } label: {
                            Text(isJP ? "購入を復元" : "Restore Purchases")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }

                    if let error = subscriptionManager.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text(isJP ? "閉じる" : "Close")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onChange(of: subscriptionManager.isSubscribed) { subscribed in
            if subscribed { dismiss() }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(red: 0.48, green: 0.62, blue: 0.88))
                .frame(width: 28)
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}
