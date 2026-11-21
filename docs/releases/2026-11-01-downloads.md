# Tankarr Reader 1.0.0 (8)

Distributed to the internal TestFlight group on **1 November 2026 at 02:00 CET**
(Europe/Rome). Apple: `VALID`, `IN_BETA_TESTING`. Italian and English notes
published and read back to verify their content.

- Sources: [`e9c971d`](https://github.com/Renzodef/tankarr-reader/commit/e9c971d9efea0a402345f0ee318a79da77415188).
- [Verification, signing and distribution pipeline](https://github.com/Renzodef/tankarr-reader/actions/runs/41257363683): succeeded on the dedicated Mac.
- 93 Python tests, 50 Swift tests and 8 UI tests on each family, iPhone and iPad: all successful.
- Before the push: three targeted UI tests on iPhone and a visual check of the covers and offline bookmarks.

## Added controls

- **Offline mode**, crossed-out Wi-Fi icon at the top: shows only series with
  at least one complete book and the bookmarks of those series. The bookmark
  copies and the covers persist in the private storage per account/server.
  A bookmark pointing to a chapter that is not downloaded opens the series, with an
  explanation, instead of starting a network read.
- **Series downloads**: **Download range…** menu, with inclusive From/Through
  pickers in catalogue order, **Download from bookmark to end** and
  **Remove series downloads**. The bookmarked chapter is included; a missing
  bookmark, or one no longer present in the catalogue, does not start a full download.
- **Downloads**: trash can at the top to delete all local copies and the account's
  queue, with confirmation. Deleting one series keeps the others.
- **Back to series** in the reader, even when coming from Downloads or Bookmarks.
- Covers with fixed proportions and top alignment; uniform space
  for one- or two-line titles.

The tests cover inverted/nonexistent ranges, special chapters, stale bookmarks
or bookmarks of other series, isolation between accounts, persistence after reopening,
filters on complete downloads and late responses after deletion.

Downloads require the app to be open. Turning Offline on pauses
transfers; changing shared bookmarks requires a connection.
Deletions act on the local copies. No changes to the server or
to the Tankarr queues, no replacement of the existing App Store submission.
