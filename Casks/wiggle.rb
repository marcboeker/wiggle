cask "wiggle" do
  version "0.1.0"

  on_arm do
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    url "https://github.com/marcboeker/wiggle/releases/download/v#{version}/Wiggle-macos-arm64.zip"
  end

  on_intel do
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
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

  zap trash: [
    "~/.config/wiggle",
    "~/Library/Preferences/com.marcboeker.wiggle.plist",
  ]
end
