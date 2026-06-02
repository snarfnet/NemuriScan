import GoogleMobileAds
import UIKit

@MainActor
class RewardedAdManager: NSObject, ObservableObject {
    private let adUnitID = "ca-app-pub-9404799280370656/8660521007"
    private var rewardedAd: GADRewardedAd?
    private var completion: ((Bool) -> Void)?

    override init() {
        super.init()
        loadAd()
    }

    func loadAd() {
        let request = GADRequest()
        GADRewardedAd.load(withAdUnitID: adUnitID, request: request) { [weak self] ad, error in
            guard let self else { return }
            if let error {
                print("RewardedAdManager: failed to load – \(error.localizedDescription)")
                return
            }
            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
        }
    }

    /// Show a rewarded ad. Calls `completion(true)` if the user earns the reward,
    /// `completion(false)` if the ad is not ready or the user skips.
    func show(completion: @escaping (Bool) -> Void) {
        guard let rewardedAd, let vc = rootViewController() else {
            loadAd()
            completion(false)
            return
        }
        self.completion = completion
        rewardedAd.present(fromRootViewController: vc) { [weak self] in
            self?.completion?(true)
            self?.completion = nil
        }
    }

    private func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

extension RewardedAdManager: GADFullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in
            // If completion was not called (user skipped), report false
            self.completion?(false)
            self.completion = nil
            self.rewardedAd = nil
            self.loadAd()
        }
    }

    nonisolated func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in
            self.completion?(false)
            self.completion = nil
            self.rewardedAd = nil
            self.loadAd()
        }
    }
}
