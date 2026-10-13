import SwiftUI

// MARK: - Playlist Importer

struct PlaylistImportView: View {
  @Binding var playlistURL: String
  @Binding var username: String
  @Binding var password: String
  @Binding var epgURL: String
  let isLoading: Bool
  let message: String?
  let loadPlaylist: () async -> Void
  let deletePlaylist: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var isShowingDeleteConfirmation = false
  @State private var isShowingPassword = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Playlist URL") {
          TextField("https://example.com/playlist.m3u", text: $playlistURL)
            .disableAutocapitalization()
            .autocorrectionDisabled()
            .urlKeyboard()
        }

        Section {
          HStack(spacing: 12) {
            Image(systemName: "person")
              .foregroundStyle(.secondary)
              .frame(width: 18)
            TextField("Username (Optional)", text: $username)
              .disableAutocapitalization()
              .autocorrectionDisabled()
          }

          HStack(spacing: 12) {
            Image(systemName: "lock")
              .foregroundStyle(.secondary)
              .frame(width: 18)
            if isShowingPassword {
              TextField("Password (Optional)", text: $password)
                .disableAutocapitalization()
                .autocorrectionDisabled()
            } else {
              SecureField("Password (Optional)", text: $password)
            }

            Button {
              isShowingPassword.toggle()
            } label: {
              Image(systemName: isShowingPassword ? "eye.slash" : "eye")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isShowingPassword ? "Hide password" : "Show password")
          }
        } header: {
          Text("Authentication (Optional)")
        } footer: {
          Text("Provide username and password if your IPTV provider requires authentication.")
        }

        Section {
          HStack(spacing: 12) {
            Image(systemName: "calendar")
              .foregroundStyle(.secondary)
              .frame(width: 18)
            TextField("https://example.com/epg.xml", text: $epgURL)
              .disableAutocapitalization()
              .autocorrectionDisabled()
              .urlKeyboard()
          }
        } header: {
          Text("Programme Guide (Optional)")
        } footer: {
          Text(
            "Enter your provider's XMLTV URL. Xtream playlists will try the provider's standard guide automatically when this is blank."
          )
        }

        Section {
          Text(
            "Use a playlist you are authorized to access. tiptv supports standard M3U, M3U8, and Xtream Codes playlists."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        if let message {
          Section {
            let didLoad = message.contains("loaded")
            Label(
              message, systemImage: didLoad ? "checkmark.circle.fill" : "exclamationmark.circle"
            )
            .foregroundStyle(didLoad ? TipTVTheme.aqua : .red)
          }
        }

        if !playlistURL.isEmpty {
          Section {
            Button(role: .destructive) {
              isShowingDeleteConfirmation = true
            } label: {
              Label("Delete Playlist", systemImage: "trash")
                .foregroundStyle(.red)
            }
          }
        }
      }
      .navigationTitle(playlistURL.isEmpty ? "Add Playlist" : "Manage Playlist")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: dismiss.callAsFunction)
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Load") {
            Task {
              await loadPlaylist()
            }
          }
          .disabled(playlistURL.isEmpty || isLoading)
        }
      }
      .confirmationDialog(
        "Delete Playlist?",
        isPresented: $isShowingDeleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Delete Playlist", role: .destructive) {
          deletePlaylist()
          dismiss()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will remove the saved playlist URL and credentials, and clear all channels.")
      }
      .overlay {
        if isLoading {
          ProgressView("Loading playlist…")
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
      }
      .tint(TipTVTheme.accent)
    }
  }
}

#Preview {
  ContentView()
}
