cask "otterkeep" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/richardeszes/OtterKeep/releases/download/v#{version}/OtterKeep-#{version}.zip"
  name "OtterKeep"
  desc "Autonomous, APFS-native incremental backup & replication engine for macOS"
  homepage "https://github.com/richardeszes/OtterKeep"

  livecheck do
    url "https://raw.githubusercontent.com/richardeszes/OtterKeep/main/Distribution/appcast.xml"
    strategy :sparkle
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "OtterKeep.app"
  binary "#{appdir}/OtterKeep.app/Contents/MacOS/otterkeep"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-rd", "com.apple.quarantine", "#{appdir}/OtterKeep.app"]
  end

  zap trash: [
    "~/.otterkeep",
    "~/Library/Application Support/OtterKeep",
    "~/Library/Caches/com.otterkeep.app",
    "~/Library/HTTPStorages/com.otterkeep.app",
    "~/Library/Preferences/com.otterkeep.app.plist",
    "~/Library/Saved Application State/com.otterkeep.app.savedState",
    "~/Library/Logs/OtterKeep",
  ]
end
