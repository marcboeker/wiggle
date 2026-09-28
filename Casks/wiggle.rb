cask "wiggle" do
  version "0.1.0"

  on_arm do
    sha256 "816556d888f9bfdd126fc566b9cbd58356ba9aedccae08d3016dfc164570eca6"
    url "https://github.com/marcboeker/wiggle/releases/download/v#{version}/Wiggle-macos-arm64.zip"
  end

  on_intel do
    sha256 "1be9c5867e856885d56cc093cc92ad3706c7a88fe5228eef51bff4240166a145"
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
  uninstall quit: "net.at6.wiggle"

  zap trash: [
    "~/.config/wiggle",
    "~/Library/Preferences/net.at6.wiggle.plist",
  ]
end
