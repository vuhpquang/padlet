# Homebrew cask for Padlet. Lives in the tap repo vuhpquang/homebrew-tap as Casks/padlet.rb;
# this copy is the source of truth — update version + sha256 after each release
# (shasum -a 256 build/Padlet.dmg).
#
#   brew install --cask vuhpquang/tap/padlet   # the full name also trusts this cask
#
# The fully qualified name matters: the official homebrew/cask already has an unrelated
# "padlet" cask (padlet.com's desktop app).
cask "padlet" do
  version "2.3.2"
  sha256 "ed92c6e2d6b35877aab2ef370bd059ccfcb6d25ab095d822bed7713318ba83ae"

  url "https://github.com/vuhpquang/padlet/releases/download/v#{version}/Padlet.dmg"
  name "Padlet"
  desc "Trackpad edge controls and extra gestures in the menu bar"
  homepage "https://github.com/vuhpquang/padlet"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :ventura

  app "Padlet.app"

  uninstall quit:       "com.vuhpquang.padlet",
            login_item: "Padlet"

  zap trash: "~/Library/Preferences/com.vuhpquang.padlet.plist"

  caveats <<~EOS
    Padlet is not notarized by Apple. On first launch macOS may block it:
    open System Settings → Privacy & Security and click "Open Anyway".
    Then allow Padlet under Privacy & Security → Accessibility.
  EOS
end
