# Homebrew cask for the self-owned tap (STRATEGY §4.4). Install path for v0.1.0:
#   brew install --cask caioniehues/swoosh/swoosh
#
# This is a TEMPLATE: `version`/`sha256`/`url` are filled when the first release asset
# (Swoosh.app zipped) is published (M6 Phase 3, gated on the M5 app bundle). The `xattr`
# postflight strips the quarantine flag so the unsigned/un-notarized build opens without a
# Gatekeeper prompt — this is why the tap path is $0 and notarization stays deferred until
# traction (~500 downloads/month) justifies $99/yr + a notarize/staple pipeline.
cask "swoosh" do
  version "0.1.0"
  sha256 :no_check # replaced with the real asset checksum at release time

  url "https://github.com/caioniehues/swoosh/releases/download/v#{version}/Swoosh.zip"
  name "Swoosh"
  desc "Window snapping + resize via two-finger trackpad gestures on titlebars"
  homepage "https://github.com/caioniehues/swoosh"

  # macOS 26 (Tahoe) only — Swoosh is latest-macOS-only (scope decision 2026-05-31).
  depends_on macos: ">= :tahoe"

  app "Swoosh.app"

  # Strip the quarantine attribute so the un-notarized build launches without a Gatekeeper block.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Swoosh.app"]
  end

  uninstall quit: "co.swoosh.app"

  zap trash: [
    "~/Library/Preferences/co.swoosh.app.plist",
  ]
end
