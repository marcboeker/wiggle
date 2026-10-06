cask "wiggle" do
  version "0.3.0"

  on_arm do
    sha256 "8aa6ba8e12647f489fc6aa64d43734db5e7c3d5e635d729f2637583260b78e54"
    url "https://github.com/marcboeker/wiggle/releases/download/v#{version}/Wiggle-macos-arm64.zip"
  end

  on_intel do
    sha256 "8112dfb2508624bf9661c21d3d34c9abc0f7034913a15e6f214b0175b4779820"
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
