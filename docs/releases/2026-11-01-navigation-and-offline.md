# Chapter navigation, bookmarks and automatic offline

- Sources: [`2f5494c`](https://github.com/Renzodef/tankarr-reader/commit/2f5494caf6b0f9d28e3e346dbd89620c82016a40).
- iPad fixes: [`e23f29c`](https://github.com/Renzodef/tankarr-reader/commit/e23f29c0c6c9aafe1bf82e2ed22a0d30771a9252).
- [iPhone/iPad and TestFlight pipeline](https://github.com/Renzodef/tankarr-reader/actions/runs/41333905579).

## Behaviour

The page bar follows the chosen horizontal direction: RTL starts from the right,
LTR from the left; vertical reading keeps the bar starting from the left.
Forward from the last page opens the next chapter at the first page;
back from the first opens the previous one at the last page, regardless of the
previous local position. Each chapter gets new tasks, images and preferences.

The adjacent chapters are those indicated by the server, even offline: the downloads
filter must not skip a missing chapter. An incomplete copy is not
readable offline. When the download is missing or the start/end of the
series is reached, a notice appears and the current chapter stays open.
In continuous mode a drag started at the edge and released past the edge
triggers the same navigation; reaching the edge through inertia is not enough.

In the series page **Resume from bookmark** uses the explicitly saved page,
even if the local position is different. If the bookmarked chapter is missing offline,
a notice appears without network requests. When there is no bookmark the series page
explains where to create it: Bookmark icon in the reader, then Save bookmark.

With complete copies available, a network loss or a reachability error
turns on **Automatically offline**. The app retries when the network returns or when brought to the
foreground; there are no reconnection timers. The network check uses the events
of [NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor).
Offline chosen manually instead stays on until you press **Go online** or
the crossed-out Wi-Fi button. Authentication, TLS or server errors remain
visible. The download queue and bookmark changes remain persistent.

## Checks and distribution

- Pre-push: **94 Python tests**, assets and privacy manifest succeeded.
- Core: **68 Swift tests**, zero errors.
- iPhone simulator: online chapter change, resume from the bookmark taking precedence
  over the local position, chapter/bookmark not downloaded without requests to the
  server, adjacent chapters offline, socket error with automatic return
  online, manual offline preserved, physical drag of the
  RTL/LTR/vertical bar and drag past the edge in continuous mode: succeeded.
- Full iPhone 17 suite: **16 UI tests, zero errors**, finished on 1 November
  2026 at **19:15:47 CET** (Europe/Rome).
- Targeted iPad A16 tests (also in a narrow window): RTL/LTR/vertical slider,
  continuous mode, chapters, bookmarks, automatic/manual offline and reconnection: succeeded.
  The foreground test uses a real switch to Settings: Home alone
  can leave the reader in the foreground in windowed mode.
- Full iPad A16 suite: **16 UI tests, zero errors**, finished on 1 November
  2026 at **19:35:29 CET**. The verification job ended successfully at
  **19:35:36 CET**.
- Distribution: **1.0.0 (12)** uploaded without errors at **19:37:30 CET**;
  internal TestFlight group updated at **19:39:38 CET**. The pipeline
  completed successfully at **19:39:44 CET**.
- Independent check on App Store Connect: valid build, status
  **IN_BETA_TESTING**, `it` and `en-US` notes saved and read back on 1 November
  2026 at **19:40 CET**.

The first pipeline was stopped before distribution: the new tests
on iPad detected interference between the window controls and the top
bar and the slider. The controls now use the native bar; the title stays
visible even in narrow windows and the slider is above the page buttons,
away from the resize corner. The slider test also verifies
that the window width stays unchanged while dragging.

The Tankarr backend requires no changes. The push publishes to the internal
TestFlight group after the tests, without replacing the public version in review.
