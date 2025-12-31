cask "kaset" do
  version "main"
  sha256 "8c88d42517e9e3465e9dc6e5dd56204cbf3772dc98c730b70d11fdc1abe53843"

  url "https://github.com/cangzhang/kaset/releases/download/main/kaset-main.dmg"
  name "Kaset"
  desc "Native macOS YouTube Music client"
  homepage "https://github.com/cangzhang/kaset"

  auto_updates true
  depends_on macos: ">= :sequoia"

  app "Kaset.app"

  zap trash: [
    "~/Library/Application Support/Kaset",
    "~/Library/Caches/com.sertacozercan.Kaset",
    "~/Library/Preferences/com.sertacozercan.Kaset.plist",
    "~/Library/Saved Application State/com.sertacozercan.Kaset.savedState",
    "~/Library/WebKit/com.sertacozercan.Kaset",
  ]
end
