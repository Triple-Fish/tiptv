import Foundation

enum PlaybackRecoveryAction: Equatable, Sendable {
  case recovered
  case retryNative
  case reloadNative
  case switchToBackup
  case showError
}

enum PlaybackRecoveryPolicy {
  nonisolated static func delay(forAttempt attempt: Int) -> Duration {
    attempt == 1 ? .milliseconds(750) : .milliseconds(1_500)
  }

  nonisolated static func statusMessage(forAttempt attempt: Int) -> String {
    attempt == 1 ? "Reconnecting stream…" : "Trying backup player…"
  }

  nonisolated static func action(
    forAttempt attempt: Int,
    isPlaying: Bool,
    isVOD: Bool,
    backupPlayerAllowed: Bool
  ) -> PlaybackRecoveryAction {
    if isPlaying {
      return .recovered
    }
    if attempt == 1 {
      return isVOD ? .showError : .reloadNative
    }
    return backupPlayerAllowed ? .switchToBackup : .showError
  }
}
