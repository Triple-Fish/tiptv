//
//  SettingsView.swift
//  tiptv
//

import SwiftUI

struct SettingsView: View {
    @Binding var playlistURL: String
    @Binding var username: String
    let totalChannels: Int
    let allChannels: [Channel]
    let onReload: () -> Void
    let onDelete: () -> Void
    let onOpenImporter: () -> Void
    var onDismiss: (() -> Void)? = nil

    @ObservedObject private var hiddenManager = HiddenChannelsManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var licenseManager = LicenseManager.shared
    @ObservedObject private var playerEngine = PlayerEngineManager.shared
    @State private var showingDeleteConfirmation = false
    @State private var showingRestoreAllConfirmation = false
    @State private var showingPaywall = false

    private var hiddenChannels: [Channel] {
        hiddenManager.filterHidden(from: allChannels)
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                licenseSection
                playlistSection
                hiddenChannelsSection
                appearanceSection
                playbackEngineSection
                appInfoSection
                legalSection
            }
            .scrollContentBackground(.hidden)
            .background(tiptvTheme.contentBackground.ignoresSafeArea())
            .navigationTitle("More")
            .confirmationDialog(
                "Delete Playlist?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Playlist", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove your saved playlist URL, credentials, and all channels.")
            }
            .confirmationDialog(
                "Restore All Hidden Channels?",
                isPresented: $showingRestoreAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restore All (\(hiddenChannels.count))") {
                    Haptics.medium()
                    withAnimation {
                        hiddenManager.unhideAll()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All hidden channels will be restored to your channel list and TV guide.")
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .toolbar {
                if let onDismiss {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDismiss)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(themeManager.accent)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: tiptvTheme.accent.opacity(0.3), radius: 8, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("tiptv")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)

                    Text("Your TV. Anywhere.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(tiptvTheme.cardBackground)
        }
    }

    @ViewBuilder
    private var licenseSection: some View {
        Section {
            if licenseManager.hasPurchasedLicense {
                HStack {
                    Label("Full Lifetime License", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(tiptvTheme.aqua)
                    Spacer()
                    Text("Active")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(tiptvTheme.aqua)
                }
            } else if licenseManager.isTrialActive {
                HStack {
                    Label("1-Day Free Trial", systemImage: "clock.badge.checkmark")
                        .foregroundStyle(.white)
                    Spacer()
                    Text(licenseManager.trialTimeRemainingString)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(tiptvTheme.aqua)
                }

                Button {
                    showingPaywall = true
                } label: {
                    Label("Upgrade to Lifetime License", systemImage: "sparkles")
                        .foregroundStyle(tiptvTheme.aqua)
                }
            } else {
                HStack {
                    Label("1-Day Free Trial", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(tiptvTheme.liveRed)
                    Spacer()
                    Text("Expired")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(tiptvTheme.liveRed)
                }

                Button {
                    showingPaywall = true
                } label: {
                    Label("Unlock Full Lifetime License", systemImage: "sparkles")
                        .foregroundStyle(tiptvTheme.aqua)
                }
            }

            Button {
                Task {
                    await licenseManager.restorePurchases()
                }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
                    .foregroundStyle(.white.opacity(0.85))
            }
        } header: {
            Text("License & Subscription")
        } footer: {
            Text(licenseManager.hasPurchasedLicense ? "Thank you for supporting tiptv! You have permanent unlimited access." : "Every new user gets 24 hours of free unlimited streaming. After the trial, a one-time purchase unlocks lifetime access.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(tiptvTheme.cardBackground)
    }

    @ViewBuilder
    private var playlistSection: some View {
        Section("Playlist Information") {
            if playlistURL.isEmpty {
                Text("No playlist added yet.")
                    .foregroundStyle(.secondary)

                Button(action: onOpenImporter) {
                    Label("Add Playlist", systemImage: "plus.circle")
                        .foregroundStyle(tiptvTheme.aqua)
                }
            } else {
                LabeledContent("URL", value: playlistURL)
                    .lineLimit(1)

                if !username.isEmpty {
                    LabeledContent("Username", value: username)
                }

                LabeledContent("Total Channels", value: "\(totalChannels)")

                Button(action: onReload) {
                    Label("Reload Playlist", systemImage: "arrow.clockwise")
                        .foregroundStyle(tiptvTheme.aqua)
                }

                Button(action: onOpenImporter) {
                    Label("Edit Playlist Credentials", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Playlist", systemImage: "trash")
                        .foregroundStyle(tiptvTheme.liveRed)
                }
            }
        }
        .listRowBackground(tiptvTheme.cardBackground)
    }

    @ViewBuilder
    private var hiddenChannelsSection: some View {
        Section {
            if hiddenChannels.isEmpty {
                HStack {
                    Label("Hidden Channels", systemImage: "eye")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("None")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                NavigationLink {
                    HiddenChannelsListView(allChannels: allChannels)
                } label: {
                    HStack {
                        Label("Hidden Channels", systemImage: "eye.slash")
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(hiddenChannels.count)")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(tiptvTheme.aqua)
                    }
                }

                Button {
                    showingRestoreAllConfirmation = true
                } label: {
                    Label("Restore All Hidden Channels", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(tiptvTheme.aqua)
                }
            }
        } header: {
            Text("Hidden Channels")
        } footer: {
            Text("To hide a channel, tap and hold on any channel in the TV Guide list or Home screen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(tiptvTheme.cardBackground)
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    Haptics.medium()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        themeManager.setTheme(theme)
                    }
                } label: {
                    HStack(spacing: 14) {
                        HStack(spacing: -6) {
                            ForEach(0..<theme.previewColors.count, id: \.self) { idx in
                                Circle()
                                    .fill(theme.previewColors[idx])
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                            }
                        }
                        .padding(4)
                        .background(Color.white.opacity(0.06), in: Capsule())

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(theme.rawValue)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundStyle(.white)

                                if theme == .pureOLED {
                                    Text("REAL DARK")
                                        .font(.system(size: 9, weight: .black, design: .rounded))
                                        .tracking(0.6)
                                        .foregroundStyle(theme.accent)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(theme.accent.opacity(0.15), in: Capsule())
                                }
                            }

                            Text(theme.subtitle)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }

                        Spacer()

                        if themeManager.currentTheme == theme {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Appearance & Themes")
        } footer: {
            Text("Choose from 5 cinematic colour palettes. Pure OLED Dark provides a true pitch black experience.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(tiptvTheme.cardBackground)
    }

    @ViewBuilder
    private var playbackEngineSection: some View {
        Section {
            ForEach(PlayerEngineManager.EnginePreference.allCases) { engine in
                Button {
                    Haptics.selection()
                    playerEngine.enginePreference = engine
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: engine == .auto ? "wand.and.stars" : (engine == .ffmpeg ? "film.stack" : "play.tv"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(playerEngine.enginePreference == engine ? themeManager.accent : .secondary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.title)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundStyle(.white)

                            Text(engine.description)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        if playerEngine.enginePreference == engine {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(themeManager.accent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            if !playerEngine.channelsRequiringFFmpeg.isEmpty {
                Button {
                    Haptics.light()
                    playerEngine.clearFFmpegCache()
                } label: {
                    Label("Reset Sound-Only Channel Cache (\(playerEngine.channelsRequiringFFmpeg.count))", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(themeManager.accent)
                }
            }
        } header: {
            Text("Playback Engine & Codecs")
        } footer: {
            Text("Auto mode plays native streams with Apple AVPlayer, and automatically transitions to FFmpeg if a live TV channel has unsupported broadcast video (such as MPEG-2 video or interlaced transport streams).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(tiptvTheme.cardBackground)
    }

    @ViewBuilder
    private var appInfoSection: some View {
        Section("App Information") {
            LabeledContent("App", value: "tiptv")
            LabeledContent("Version", value: "1.0")
            LabeledContent("Playback Engine", value: playerEngine.enginePreference.title)
            LabeledContent("Theme", value: themeManager.currentTheme.rawValue)
        }
        .listRowBackground(tiptvTheme.cardBackground)
    }

    @ViewBuilder
    private var legalSection: some View {
        Section {
            Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                HStack {
                    Label("Terms of Use (EULA)", systemImage: "doc.text")
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
                    .foregroundStyle(.white)
            }

            NavigationLink {
                AcknowledgementsView()
            } label: {
                Label("Open Source Acknowledgements", systemImage: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(.white)
            }
        } header: {
            Text("Legal & Privacy")
        } footer: {
            Text("tiptv is a media player client and does not provide, host, or bundle any stream content. Users are responsible for supplying their own legally acquired playlists.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(tiptvTheme.cardBackground)
    }
}

// MARK: - Hidden Channels List View

struct HiddenChannelsListView: View {
    let allChannels: [Channel]
    @ObservedObject private var hiddenManager = HiddenChannelsManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    private var hiddenList: [Channel] {
        hiddenManager.filterHidden(from: allChannels)
    }

    var body: some View {
        List {
            if hiddenList.isEmpty {
                Text("No hidden channels.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(tiptvTheme.cardBackground)
            } else {
                ForEach(hiddenList) { channel in
                    HStack(spacing: 12) {
                        Text(channel.uniformName)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.white)

                        Spacer()

                        Button("Unhide") {
                            Haptics.light()
                            withAnimation {
                                hiddenManager.unhideChannel(channel)
                            }
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(themeManager.accent)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(tiptvTheme.cardBackground)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(tiptvTheme.contentBackground.ignoresSafeArea())
        .navigationTitle("Hidden Channels")
    }
}
