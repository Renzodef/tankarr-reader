# Real screenshots for the store

The captures of 29 October 2026 are in `screenshots/iphone-6.9/` and
`screenshots/ipad-13/`: four original PNGs per device, exported from the
passed UI tests on iPhone 18 Pro Max and iPad Pro 13" (M5). They show only
the bundled demo and were checked visually, without retouching.

Use the bundled demo. The original icon is in `App/Assets.xcassets`:
1024 × 1024, opaque. Do not use screenshots with accounts, private server
addresses, notifications from other apps or personal libraries.

For each device capture:

1. **Library** — the three original covers, search and the Demo label.
2. **Volumes** — “Segnali dal faro”, list of books.
3. **Reader** — first page of the story, navigation controls visible.
4. **Webtoon** — “Atlante delle nuvole”, vertical page.

Formats chosen from the Apple table: iPhone 1320 × 2868 (portrait), iPad
2064 × 2752 (portrait). RGB PNG without alpha. If the installed runtime offers
another device, choose a resolution allowed by the Apple table;
do not distort the interface to reach the required dimensions.

The `TankarrReaderUITests` target verifies search, reading and page resume
and attaches four real screenshots to the XCTest result. Run it on iPhone Pro
Max and iPad Pro 13", then export the attachments with `xcresulttool` and inspect them:

```sh
xcodebuild -project TankarrReader.xcodeproj -scheme 'Tankarr Reader' \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -resultBundlePath build/ReaderUI.xcresult CODE_SIGNING_ALLOWED=NO test
xcrun xcresulttool export attachments --path build/ReaderUI.xcresult \
  --output-path build/screenshots
```

From a simulator that is already configured and booted:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl status_bar "$SIMULATOR_UDID" override --time '9:41' \
  --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl launch "$SIMULATOR_UDID" app.tankarr.reader --demo
# Navigate to the intended screen, then:
xcrun simctl io "$SIMULATOR_UDID" screenshot --type=png --mask=ignored library.png
# When finished:
xcrun simctl status_bar "$SIMULATOR_UDID" clear
```

Check the images visually before submitting. The project can be
built without signing for the simulator; the first Xcode setup must
still be completed.

https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
