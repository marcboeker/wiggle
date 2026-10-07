cask "wiggle" do
  version "0.4.0"

  on_arm do
    sha256 "ecc70065dd795ea7d800c6c3190fcbcb9f321ceddb57c7868d63fb50ca346250"
    url "https://github.com/marcboeker/wiggle/releases/download/v#{version}/Wiggle-macos-arm64.zip"
  end

  on_intel do
    sha256 "8ed3b08a991236ae3d36ca87868f171b2b37ef5fc1b2fcf843b4c20fe96263a5"
    url "https://github.com/marcboeker/wiggle/releases/download/v#{version}/Wiggle-macos-amd64.zip"
  end

  name "Wiggle"
  desc "Dock-less accessory app that opens a wheel of shortcut slots around the pointer"
  homepage "https://github.com/marcboeker/wiggle"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Wiggle.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Wiggle.app"]
  end

  # Quit the running app before Homebrew replaces the bundle on upgrade/uninstall — otherwise
  # the update clobbers a live process.
  uninstall quit: "one.m8n.wiggle"

  zap trash: [
    "~/.config/wiggle",
    "~/Library/Preferences/one.m8n.wiggle.plist",
  ]
end
