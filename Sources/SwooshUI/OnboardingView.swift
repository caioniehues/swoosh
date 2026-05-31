import SwiftUI

/// First-launch Accessibility onboarding (SPEC §8). Explains *why* the one permission is needed,
/// opens System Settings, and reflects the granted state (the caller polls and flips `isTrusted`).
public struct OnboardingView: View {
    private let isTrusted: Bool
    private let openSystemSettings: () -> Void

    public init(isTrusted: Bool, openSystemSettings: @escaping () -> Void) {
        self.isTrusted = isTrusted
        self.openSystemSettings = openSystemSettings
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isTrusted ? "checkmark.circle.fill" : "hand.raised.fill")
                .font(.system(size: 44))
                .foregroundStyle(isTrusted ? .green : .accentColor)

            Text("Swoosh needs Accessibility")
                .font(.title2).bold()

            Text("""
            Accessibility is the only permission Swoosh requests. It is needed to detect which \
            window's titlebar your cursor is over and to move that window. Nothing leaves your \
            machine — there is no network or telemetry.
            """)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 380)

            if isTrusted {
                Text("Granted — Swoosh is active.").foregroundStyle(.green)
            } else {
                Button("Open System Settings → Accessibility", action: openSystemSettings)
                    .buttonStyle(.borderedProminent)
                Text("Swoosh starts automatically once you grant it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 460)
    }
}
