cask "wiggle" do
  version "0.2.0"

  on_arm do
    sha256 "117a5a3ecffb149acd2f423a69559ec503bb818115c3ea1fc9e761ad234ee251"
    url "https://github.com/marcboeker/wiggle/releases/download/v#{version}/Wiggle-macos-arm64.zip"
  end

  on_intel do
    sha256 "fefa0e02ba0a58554b7ad9e93dd127a492d6538ed10f1fc5c84e32395f0c90e0"
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
