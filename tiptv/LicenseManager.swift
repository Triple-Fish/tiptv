//
//  LicenseManager.swift
//  tiptv
//

import Combine
import Foundation
import StoreKit
import SwiftUI

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // 24-Hour Free Trial
    static let trialDurationSeconds: TimeInterval = 24 * 60 * 60 // 24 hours

    // In-App Purchase Product Identifier
    static let lifetimeProductID = "com.graham.tiptv.lifetime"

    private let trialStartDateKey = "tiptv_trial_start_date"
    private let hasPurchasedLicenseKey = "tiptv_has_purchased_license"

    @Published private(set) var trialStartDate: Date
    @Published private(set) var hasPurchasedLicense: Bool = false
    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var purchaseErrorMessage: String?

    private var transactionListenerTask: Task<Void, Never>?

    init() {
        if let storedDate = (UserDefaults.standard.object(forKey: trialStartDateKey) ?? UserDefaults.standard.object(forKey: "tivvy_trial_start_date")) as? Date {
            self.trialStartDate = storedDate
        } else {
            let now = Date()
            UserDefaults.standard.set(now, forKey: trialStartDateKey)
            self.trialStartDate = now
        }

        self.hasPurchasedLicense = UserDefaults.standard.bool(forKey: hasPurchasedLicenseKey) || UserDefaults.standard.bool(forKey: "tivvy_has_purchased_license")

        transactionListenerTask = listenForTransactions()

        Task {
            await fetchProducts()
            await checkCurrentEntitlements()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Trial Status Computations

    var trialTimeElapsed: TimeInterval {
        max(0, Date().timeIntervalSince(trialStartDate))
    }

    var trialTimeRemaining: TimeInterval {
        max(0, Self.trialDurationSeconds - trialTimeElapsed)
    }

    var isTrialActive: Bool {
        trialTimeRemaining > 0
    }

    var canAccessApp: Bool {
        hasPurchasedLicense || isTrialActive
    }

    var trialTimeRemainingString: String {
        if hasPurchasedLicense {
            return "Lifetime License Active"
        }
        let remaining = trialTimeRemaining
        if remaining <= 0 {
            return "Trial Expired"
        }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        } else {
            return "\(minutes)m left"
        }
    }

    // MARK: - StoreKit 2 Logic

    func fetchProducts() async {
        do {
            let products = try await Product.products(for: [Self.lifetimeProductID])
            if let first = products.first {
                self.lifetimeProduct = first
            }
        } catch {
            print("Failed to fetch StoreKit products: \(error)")
        }
    }

    func purchaseLicense() async -> Bool {
        var productToBuy = lifetimeProduct
        if productToBuy == nil {
            productToBuy = try? await Product.products(for: [Self.lifetimeProductID]).first
        }
        guard let product = productToBuy else {
            purchaseErrorMessage = "Unable to connect to the App Store. Please check your internet connection."
            return false
        }

        isPurchasing = true
        purchaseErrorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                self.hasPurchasedLicense = true
                UserDefaults.standard.set(true, forKey: hasPurchasedLicenseKey)
                self.isPurchasing = false
                return true

            case .userCancelled:
                self.isPurchasing = false
                return false

            case .pending:
                self.isPurchasing = false
                return false

            @unknown default:
                self.isPurchasing = false
                return false
            }
        } catch {
            self.purchaseErrorMessage = error.localizedDescription
            self.isPurchasing = false
            return false
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        purchaseErrorMessage = nil
        do {
            try await AppStore.sync()
            await checkCurrentEntitlements()
            isPurchasing = false
        } catch {
            purchaseErrorMessage = "Restore failed: \(error.localizedDescription)"
            isPurchasing = false
        }
    }

    func checkCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.lifetimeProductID && transaction.revocationDate == nil {
                    self.hasPurchasedLicense = true
                    UserDefaults.standard.set(true, forKey: hasPurchasedLicenseKey)
                    return
                }
            }
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await MainActor.run {
                        if transaction.productID == Self.lifetimeProductID && transaction.revocationDate == nil {
                            self.hasPurchasedLicense = true
                            UserDefaults.standard.set(true, forKey: self.hasPurchasedLicenseKey)
                        }
                    }
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Debug / Testing Utilities

    #if DEBUG
    func debugResetTrial() {
        let now = Date()
        UserDefaults.standard.set(now, forKey: trialStartDateKey)
        UserDefaults.standard.removeObject(forKey: hasPurchasedLicenseKey)
        self.trialStartDate = now
        self.hasPurchasedLicense = false
    }

    func debugExpireTrial() {
        let expired = Date().addingTimeInterval(-Self.trialDurationSeconds - 100)
        UserDefaults.standard.set(expired, forKey: trialStartDateKey)
        UserDefaults.standard.removeObject(forKey: hasPurchasedLicenseKey)
        self.trialStartDate = expired
        self.hasPurchasedLicense = false
    }

    func debugGrantLicense() {
        self.hasPurchasedLicense = true
        UserDefaults.standard.set(true, forKey: hasPurchasedLicenseKey)
    }
    #endif
}
