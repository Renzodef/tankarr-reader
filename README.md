# Tankarr Reader for iOS

[![Download on the App Store](https://tools.applemarketingtools.com/api/badges/download-on-the-app-store/black/en-us)](https://apps.apple.com/app/tankarr-reader/id6828301550)

**App Store:** [Tankarr Reader](https://apps.apple.com/app/tankarr-reader/id6828301550), for iPhone and iPad, and on Macs with Apple silicon from the same App Store listing. Server: [Renzodef/tankarr](https://github.com/Renzodef/tankarr).

Native SwiftUI client for the Tankarr Reader gateway of the self-hosted stack. iOS 17+,
iPhone and iPad; no external dependencies. Catalogue with search and covers,
list of downloaded books, paged reading with zoom and continuous scrolling,
vertical or horizontal, with a selectable direction. Interface in Italian and English.
The last page read stays on the device; bookmarks are saved on the
Tankarr server. Chapters and volumes can be downloaded to the device for
offline reading. No changes to the library,
no searches/downloads on the server and no administrative key in the app.

The bundled demo uses the same reader screens with three stories and original
images, without network or account. Demo progress is kept separate from that of
the servers. Demo bookmarks are local too. Privacy and support are reachable
from Connection; local reading data can be cleared separately.

## Reading options

The **Reading options** button in the reader lets you choose:

- the format: **Automatic**, **Paged** or **Continuous scrolling**;
- the axis: **Automatic**, **Vertical** or **Horizontal**;
- the horizontal direction: **Automatic**, **Left → right** or **Right → left**.

Automatic direction and format follow the server's hints. The automatic
axis uses vertical in continuous mode and horizontal in paged mode, keeping the
behaviour of build 5. A volume declared as webtoon therefore opens in
vertical continuous mode. In vertical mode the right/left choice is disabled; it
becomes available again when you choose horizontal. Preferences are saved on the device
per volume and server, persist after reopening and are kept separate from those of the
demo. The update keeps the direction and format already chosen; the new axis
starts from Automatic. Switching mode keeps the current page.

**Paged** offers pinch zoom and double tap. Without zoom, swipes
change page along the chosen axis; in vertical mode up/down gestures and up/down
arrows are used, in horizontal mode the chosen reading direction applies. With zoom active,
dragging moves the image without changing page.

The progress bar follows the horizontal direction: with **Right → left**
the first page is at the right end. In vertical mode the bar starts from the left.
At the end of a chapter, forward opens the next one at the first page; at the
first page, back opens the previous one at the last page. In continuous mode you can also
drag past the edge, without changing chapter through inertial scrolling
alone. The adjacent chapters declared by the server are followed: offline, if
the requested one is not downloaded, a notice appears and the page stays open.

**Continuous scrolling** shows all the pages of the chapter in sequence:
from top to bottom in vertical mode, or from left to right or from right to
left in horizontal mode. Images are loaded as they are needed and
those far from the current position are released to limit memory
use. Zoom remains available in the paged format. The visible page that is already
loaded updates the local position and is the one offered by the Bookmark menu;
saving the bookmark remains an explicit action.

## App language

In **Connection → App language** choose **System**, **Italiano** or **English**.
System uses the first supported language among the iOS preferences, with English as
fallback. The change is immediate, stays saved and is included in exported
configurations. Push registration sends the chosen language to the server; offline,
the update happens when you are back online.

When updating from 1.0.1, which forced English, the app returns to System only
once. A later explicit choice is kept. Italian preferences
set before 1.0.1 and the languages in imported files remain valid. Connection,
bookmarks, downloads and reading options are not changed. Titles, books and
demo stories keep the language of the content.

## Followed series

**Follow series** in the series page enables notifications for new chapters of
that series; the bell in the library filters the **Followed series**. The
selection is shared on the same account and separate from bookmarks. The first
Follow asks for the iOS permission; if it is denied, the series page lets you open the
settings. A gateway with push configured and a compatible build are required.
Notifications arrive once the new chapter has been imported into the library,
even with the app closed, without notifying chapters that were already present. Tapping the notification
opens the series. Offline the selection can be viewed, but it is changed online.
The demo tries Follow only on the device and sends no notifications.

Configuration and checks: [Followed series and push](docs/FOLLOWING-NOTIFICATIONS.md).

## Bookmarks and resuming

The **Bookmarks** button in the library shows the bookmarks shared with
Tankarr; **Resume reading** opens the saved page. In the reader, the
**Bookmark** menu saves the displayed page, moves the bookmark or removes it.
Tankarr keeps only one bookmark per series, shared across readers and devices:
saving it in another volume of the series replaces the previous one.

Changing page automatically remembers the last position on the device;
updating the shared bookmark requires an explicit action, as on the
Tankarr website. Opening a volume resumes the local position, if present; otherwise
it uses the server bookmark. Opening it from the Bookmarks list always uses the bookmark's
page, as does **Resume from bookmark** in the series page.
This choice takes precedence over the last local position. If the bookmarked chapter is not
available offline, the button explains this without starting network requests.
Explicit changes are first saved on the device:
if there is no connection they wait and are synced when you are back
online. A sync error is shown without losing the change.

The gateway must declare `reading_state_writable: true` and offer
`GET /v1/bookmarks`, `PUT/DELETE /v1/series/ID/bookmark`. Writes send
`X-Tankarr-Reader: 1`; PUT sends JSON and DELETE has no body.
The administrative endpoints remain inaccessible.
Earlier gateways continue to offer reading and local resuming.

## Downloads to the device

In a series list, the arrow next to a chapter or volume starts the
local download. **Download all** queues the books in series
order. It does not start searches or acquisitions on the server: it only copies pages already
accessible to the reader account, using the same authenticated endpoints.

The **Series downloads** menu at the top offers **Download range…**, with two
inclusive **From/Through** menus in catalogue order, **Download from bookmark to
end** (includes the bookmarked chapter) and **Remove series downloads**. A
missing bookmark, or one no longer present in the catalogue, disables that download;
it is not replaced with a download of the whole series. Complete or already
queued books are skipped. Confirmed removal also cancels the pending
transfers of that series only, keeping those of the others.

The **Downloads** button in the library shows progress, storage used and
copies **Available offline**. You can pause, resume or remove
a download, or remove them all with the trash can that is always visible at the top,
after confirmation. A copy is ready only after all its pages
have been saved; interrupted transfers keep the pages already received and
**Resume** downloads only the missing or damaged ones. If the network or the disk
fail, the queue stays saved, without retrying indefinitely: **Resume
queue**, returning to the app or reconnecting retry the missing pages.

The same indicators appear directly under each chapter in the **series**:
bar and percentage, pages saved out of the total, storage used, queue position,
pause or offline availability and any errors. The controls next to the chapter
pause or resume; swiping sideways allows removal
with confirmation, even for an incomplete download. The series summary shows
complete books and queued books. Both screens observe the same data:
switching screen does not start a second transfer and does not reset the progress.

Real transfers use a background `URLSession`: they continue when you
switch app or lock the screen. The whole selection is saved before
the requests are created, including the books not started yet. Force quitting
cancels the iOS transfers, but on reopening the queue resumes automatically.
Offline mode keeps the queue and suspends it until reconnection.
Timing, network availability and suspensions for power saving remain under
the control of iOS. The demo generates images on the device and does not use the network.
The storage check leaves at least
256 MiB free and reserves space for the temporary page. Pages are limited
to 64 MiB each, validated as images and saved with a checksum; a whole volume is
never loaded into memory.

The **Offline mode** button at the top pauses transfers and shows only the series
with at least one complete book and the bookmarks of those series. It keeps the
download covers and a snapshot of the bookmarks, separated by account and
server, even after a restart. If the bookmarked chapter is not downloaded, the row
explains this and opens the series instead of trying to read over the network. The filter
updates immediately when local copies are deleted.

At the bottom, **Go online** reconnects to the server. Offline chosen manually stays
on even after reopening. With complete copies on the device, a network loss
detected by iOS or a reachability error while reading opens
**Automatically offline** instead: the app retries when the network returns or when it is
brought back to the foreground. There is no reconnection timer. Password,
certificate or server response errors remain visible. Bookmark sync
and the download queue resume only after a successful connection.

**Use offline** in the Downloads screen turns on the same mode;
tapping the button at the top again or **Reconnect to server** returns to the online
library. The refresh gesture in offline mode refreshes only the local
data. Copies can be read even after closing and reopening
the app, in paged or continuous mode and with all the available directions.
The page reached continues to be saved locally. **Bookmark** lets you
save, move or remove a bookmark even offline, once the server
has confirmed at least once the permission to change them. The change is
saved first on the device, in an atomic journal separated by account and
server, and stays visible as **waiting to sync** until the
server confirms it. This also applies to removals: an old server snapshot
does not bring back a bookmark removed offline.

Reconnecting to the server, reopening the app online, bringing it back to the foreground online
or refreshing the bookmarks automatically retries the pending changes. A
network error does not delete them; there is no periodic polling. Offline mode
chosen explicitly stays on until you turn it off. For the
same series, the last explicit change made on this device is sent:
once synced, it replaces the shared bookmark of that series, even
if another reader changed it in the meantime. The other bookmarks remain
unchanged. Changing page on its own still does not change the bookmark.
The demo remains entirely local.
**Back to series** in the reader opens the series page even when coming from
Downloads or Bookmarks; **Close book** instead returns to the previous screen.

Downloads are separated by server identity and username: LAN and HTTPS of the
same server share the copies, other accounts do not. The data lives in
Application Support, protected by the device and excluded from iCloud backups;
no password is written to the manifests. **Disconnect** asks for confirmation and
also removes the account's copies and the unsynced bookmark changes
(shown in the confirmation). Clearing only the downloads instead keeps
the pending changes and does not change
the files, bookmarks or library on the server. Copies are a snapshot of the
books: to update them after a replacement on the server, remove them and download them
again. The demo lets you try the same controls without credentials.

Tests: `OfflineBookmarksTests` checks persistence of changes and removals,
delayed confirmations, account isolation, permissions and preservation during
download removal. A UI test with an HTTP server checks an offline change,
closing and reopening, a 503 error, the subsequent sync and offline removal.
`OfflineDownloadsTests` checks interruption/resume, reopening without
network, insufficient storage, integrity, account isolation, deletion and
late responses. `testOfflineDownloadRelaunchProgressAndRemoval` tests the full
cycle on iPhone and iPad: download, reading exclusively from disk, relaunch,
progress, continuous scrolling and removal. The privacy manifest declares the
disk space check (`E174.1`) for these user-visible operations.

## Connection

In Connection enter the local and/or HTTPS URL, the reader's username and password.
Automatic tries the local one first, then the remote one. A library
refresh re-evaluates the addresses. TLS certificates are always verified;
HTTP is allowed only for explicit local hosts. Interactive requests
reject redirects; background sessions follow them according to iOS rules,
but the client rejects content received from a URL other than the requested one.
The password stays in the Keychain, without iCloud sync, accessible
after the first unlock of the device (`AfterFirstUnlockThisDeviceOnly`). The
offline storage also uses protection until first unlock so that it can receive
pages while the screen is locked. The other connection data is in UserDefaults.

You can import a private JSON from Files, then press Connect:

```json
{
  "localAddress": "https://reader.example.org",
  "remoteAddress": "https://reader.example.org",
  "username": "reader",
  "password": "REPLACE_ON_DEVICE"
}
```

The real file contains a password: do not commit it, do not put it in the app
bundle and delete it from Files after importing. `instanceID` is optional;
when present it prevents accepting a server other than the configured one.

## Build

Open `TankarrReader.xcodeproj` in Xcode. The project is already committed; to
regenerate it after adding Swift files: `python3 generate_project.py`.

```sh
swift test
xcodebuild -project TankarrReader.xcodeproj -scheme 'Tankarr Reader' \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```

For a real iPhone select your own team in Signing & Capabilities and
the device paired with Xcode. Free Personal Team signing requires
a new installation periodically; TestFlight requires Apple Developer
membership. No purchases are needed to build or test on the
simulator. The app does not include passwords, Apple accounts or signing certificates.

## Publishing

`AppStore/metadata.json` contains the Italian/English texts; `REVIEW_NOTES.md`
the instructions for Apple; `SCREENSHOTS.md` the real capture sequence.
The app languages match the listing localizations: Italian and English.
The original demo stays in Italian.
`python3 Tools/check_store_assets.py` checks text limits, the icon and the
privacy manifest included in the target. The privacy screen is also available
offline; the public `/privacy` and `/support` URLs serve static documents,
while the library and API still require authentication.

The client lives in the private repository `Renzodef/tankarr-reader`, with the Xcode
project, sources and tests at the root. `Renzodef/tankarr` contains the server;
`Renzodef/self-hosted` contains the gateway and the stack configuration.
The GitHub Actions workflow
`Tankarr Reader iOS` uses a dedicated runner on the personal ARM64 Mac: it verifies
client updates on `main` and sends them to the internal TestFlight group.
It runs the core, asset and interface tests on iPhone and iPad. It starts
only from relevant pushes to `main` or from a manual run, with no trigger on
pull requests. Only one workflow at a time can run tests and distribution;
a new run does not interrupt the one in progress.
The default manual action `verify` runs all tests without distribution;
`testflight` uploads a new build after the tests.

The Mac must be on, awake and with the user session available. If it is
offline or asleep, the jobs stay queued: there is no fallback to GitHub-hosted
Macs and their minutes are not consumed. Runner requirements and
verification are in [Tools/CI_RUNNER.md](Tools/CI_RUNNER.md).

Submission for App Store review is a separate
manual action, with an explicit version and build: it does not change a version already
in review. Configuration, commands and signing renewal are described in
[BUILD_AND_UPLOAD.md](AppStore/BUILD_AND_UPLOAD.md).

### Queue resume and followed series offline

**Enable offline mode** shows the downloaded copies and pauses downloads.
**Retry downloads** appears only when a queue is actually suspended: it checks
the local/HTTPS connection again and resumes the missing pages. The existing guard against late errors from cancelled transfers
is covered by regression tests.
The followed series screen stays empty offline and invites you to go back online;
it does not filter notifications based on downloaded books.
