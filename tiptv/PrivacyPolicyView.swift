//
//  PrivacyPolicyView.swift
//  tiptv
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(tiptvTheme.aqua)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your Privacy Matters")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)

                            Text("tiptv is designed from the ground up to respect your privacy. We collect zero personal data.")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .listRowBackground(tiptvTheme.cardBackground)

            Section("Data Collection") {
                PrivacyPolicyItem(
                    icon: "hand.raised.slash.fill",
                    title: "No Data Collection",
                    description: "tiptv does not collect, track, transmit, or sell any personal information, usage analytics, advertising identifiers, or browsing habits. We have no user accounts or tracking servers."
                )

                PrivacyPolicyItem(
                    icon: "internaldrive.fill",
                    title: "Local Storage Only",
                    description: "All your playlists, Xtream Codes credentials, channel favorites, watch history, and app preferences are stored exclusively on your device. Your data never leaves your device unless you explicitly export it."
                )

                PrivacyPolicyItem(
                    icon: "network",
                    title: "Direct Streaming Connections",
                    description: "When streaming video or fetching EPG data, the app connects directly to the IPTV provider or server specified by you. No media traffic or credentials pass through any intermediate servers operated by tiptv."
                )
            }
            .listRowBackground(tiptvTheme.cardBackground)

            Section("Purchases & Security") {
                PrivacyPolicyItem(
                    icon: "creditcard.fill",
                    title: "In-App Purchases",
                    description: "All purchases and subscriptions are handled securely through Apple's App Store and StoreKit. tiptv never receives, processes, or stores your credit card or billing details."
                )

                PrivacyPolicyItem(
                    icon: "shield.lefthalf.filled",
                    title: "No Third-Party Analytics",
                    description: "tiptv contains no third-party tracking libraries, advertising SDKs, or remote analytics frameworks. We respect your network bandwidth and battery life."
                )
            }
            .listRowBackground(tiptvTheme.cardBackground)

            Section("Content Responsibility") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("tiptv is strictly a media player application. It does not provide, distribute, host, or sell any streams, channels, or media content. Users are solely responsible for ensuring they possess the appropriate rights to any playlists or content they access.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineSpacing(3)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(tiptvTheme.cardBackground)

            Section("Contact") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("If you have questions or feedback regarding this privacy policy, please contact support via the repository or support channels.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))

                    Text("Last updated: September 2026")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(tiptvTheme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(tiptvTheme.contentBackground.ignoresSafeArea())
        .navigationTitle("Privacy Policy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(tiptvTheme.accent)
            }
        }
    }
}

private struct PrivacyPolicyItem: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tiptvTheme.aqua)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)

                Text(description)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(2)
            }
        }
        .padding(.vertical, 4)
    }
}
