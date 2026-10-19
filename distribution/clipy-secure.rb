# Ready-to-use Homebrew cask for the jeremym/homebrew-tap repo.
# Copy this to  jeremym/homebrew-tap:Casks/clipy-secure.rb  (see docs/release-setup.md).
# scripts/update-tap.sh rewrites the `version` and `sha256` lines on each release,
# so keep those two lines in this exact shape.
cask "clipy-secure" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/jeremym/clipy-secure/releases/download/v#{version}/ClipySecure-#{version}.zip"
  name "ClipySecure"
  desc "Privacy-first clipboard manager with encrypted history"
  homepage "https://jeremym.github.io/clipy-secure/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: :sonoma

  app "ClipySecure.app"

  # Not notarized (no Apple Developer ID, by choice). Gatekeeper would block the
  # first launch, so drop the quarantine flag that Homebrew sets on downloads.
  # Integrity is covered by the sha256 above and by the certificate leaf hash in
  # the release notes (codesign -d -r- ClipySecure.app).
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/ClipySecure.app"], must_succeed: false
  end

  uninstall quit: "com.clipysecure.app"

  zap trash: [
    "~/Library/Application Support/com.clipysecure.app",
    "~/Library/Preferences/com.clipysecure.app.plist",
  ]

  caveats <<~EOS
    ClipySecure is signed with the project's own certificate, not an Apple
    Developer ID, and is not notarized. The quarantine flag is removed on
    install so it launches without a Gatekeeper prompt.

    The encryption key stays in your login Keychain after uninstall; delete
    the "ClipySecure" item in Keychain Access if you want it gone.
  EOS
end
