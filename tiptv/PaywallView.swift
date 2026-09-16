//
//  PaywallView.swift
//  tiptv
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    var onDismiss: (() -> Void)? = nil

    @ObservedObject private var licenseManager = LicenseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingPrivacyPolicy = false

    private var purchaseButtonTitle: String {
        if let price = licenseManager.lifetimeProduct?.displayPrice {
            return "Unlock Lifetime License • \(price)"
        }
        return "Unlock Lifetime License"
    }

    var body: some View {
        ZStack {
            tiptvTheme.contentBackground.ignoresSafeArea()

            // Ambient background glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tiptvTheme.accent.opacity(0.35), tiptvTheme.aqua.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 260
                    )
                )
                .frame(width: 380, height: 380)
                .offset(y: -220)
                .blur(radius: 40)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Top dismiss button (only if user can still access the app)
                    HStack {
                        Spacer()
                        if licenseManager.canAccessApp || onDismiss != nil {
                            Button {
                                if let onDismiss {
                                    onDismiss()
                                } else {
                                    dismiss()
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    // App Logo & Header
                    VStack(spacing: 12) {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: tiptvTheme.accent.opacity(0.4), radius: 14, y: 4)

                        HStack(spacing: 6) {
                            Text("tiptv")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundStyle(.white)

                            Text("PRO")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(tiptvTheme.artworkGradient, in: Capsule())
                        }

                        // Trial status announcement
                        if licenseManager.hasPurchasedLicense {
                            Text("Lifetime License Activated")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(tiptvTheme.aqua)
                        } else if licenseManager.isTrialActive {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.badge.checkmark")
                                    .font(.system(size: 14))
                                    .foregroundStyle(tiptvTheme.aqua)

                                Text("1-Day Free Trial: \(licenseManager.trialTimeRemainingString)")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(tiptvTheme.aqua)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(tiptvTheme.aqua.opacity(0.14), in: Capsule())
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(tiptvTheme.liveRed)

                                Text("Free Trial Expired")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(tiptvTheme.liveRed)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(tiptvTheme.liveRed.opacity(0.14), in: Capsule())
                        }

                        Text("Unlock permanent unlimited access to all channels, live TV, EPG, themes, and premium features.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // Feature highlights list
                    VStack(spacing: 14) {
                        FeatureRow(
                            icon: "tv.fill",
                            title: "Unlimited Streaming",
                            subtitle: "Smooth, low-latency live TV playback without interruptions"
                        )

                        FeatureRow(
                            icon: "list.bullet.rectangle.portrait.fill",
                            title: "Custom Playlists & Xtream",
                            subtitle: "Import M3U, M3U8, or username/password IPTV credentials"
                        )

                        FeatureRow(
                            icon: "paintpalette.fill",
                            title: "5 Cinematic Themes",
                            subtitle: "Includes Pure OLED Dark, Midnight Emerald, and Cyber Sunset"
                        )

                        FeatureRow(
                            icon: "eye.slash.fill",
                            title: "Channel Organization",
                            subtitle: "Hide unwanted channels and organize your favorite streams"
                        )

                        FeatureRow(
                            icon: "infinity",
                            title: "Pay Once, Keep Forever",
                            subtitle: "One-time lifetime purchase. No monthly recurring subscriptions"
                        )
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(tiptvTheme.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(tiptvTheme.cardBorder, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)

                    // Purchase action area
                    VStack(spacing: 12) {
                        if let error = licenseManager.purchaseErrorMessage {
                            Text(error)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(tiptvTheme.liveRed)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        if licenseManager.hasPurchasedLicense {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                Text("Full License Owned")
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(tiptvTheme.aqua, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.horizontal, 20)
                        } else {
                            Button {
                                Haptics.medium()
                                Task {
                                    let success = await licenseManager.purchaseLicense()
                                    if success {
                                        dismiss()
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if licenseManager.isPurchasing {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text(purchaseButtonTitle)
                                            .font(.system(.headline, design: .rounded).weight(.bold))
                                    }
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(tiptvTheme.artworkGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: tiptvTheme.accent.opacity(0.45), radius: 14, y: 4)
                            }
                            .disabled(licenseManager.isPurchasing)
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                        }

                        // Restore button
                        Button {
                            Haptics.light()
                            Task {
                                await licenseManager.restorePurchases()
                            }
                        } label: {
                            Text("Restore Previous Purchase")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        .disabled(licenseManager.isPurchasing)
                        .buttonStyle(.plain)
                        .padding(.top, 4)

                        #if DEBUG
                        // Debug testing controls for trial
                        VStack(spacing: 8) {
                            Divider().background(Color.white.opacity(0.1))
                            Text("DEBUG TESTING CONTROLS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button("Reset Trial (24h)") {
                                    licenseManager.debugResetTrial()
                                }
                                .font(.caption2)
                                .buttonStyle(.bordered)

                                Button("Expire Trial Now") {
                                    licenseManager.debugExpireTrial()
                                }
                                .font(.caption2)
                                .buttonStyle(.bordered)
                                .tint(.red)

                                Button("Grant License") {
                                    licenseManager.debugGrantLicense()
                                }
                                .font(.caption2)
                                .buttonStyle(.bordered)
                                .tint(.green)
                            }
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 20)
                        #endif
                    }

                    // Disclaimer & Terms
                    Text("Payment will be charged to your Apple ID account at confirmation of purchase. This is a one-time purchase with no recurring fees.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)

                    // Mandatory Legal Links (App Store Guidelines 3.1.2 & 5.1.1)
                    HStack(spacing: 16) {
                        Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                        Button("Privacy Policy") {
                            showingPrivacyPolicy = true
                        }
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingPrivacyPolicy) {
            NavigationStack {
                PrivacyPolicyView()
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tiptvTheme.accent.opacity(0.18))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tiptvTheme.aqua)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()
        }
    }
}
