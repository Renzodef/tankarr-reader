# Tankarr Reader 1.0.0 (9): background downloads

- Sources: [`0394f4b`](https://github.com/Renzodef/tankarr-reader/commit/0394f4b52e19cc81a52395a314ed0d369c9c58e9).
- [Verification, signing and distribution pipeline](https://github.com/Renzodef/tankarr-reader/actions/runs/41271745463).
- This update removes build 8's limitation of foreground-only downloads.

## Behaviour

The complete selection is saved before transfers start, including
the chapters that have yet to start. Putting Reader in the background does not
cancel the queue: the real downloads are handed to the iOS network service.
On reopening after a termination, Reader recovers the selection and
downloads only the missing pages, without having to choose the chapters again.

Force quitting interrupts the iOS transfers until the app is next
opened. Network, power saving and iOS scheduling can
delay background work; it is not a guarantee of continuous speed.

Offline suspends the queue while keeping it. Explicitly pausing a book keeps
the pages already downloaded but removes it from the active queue. Removing a book,
a series or all downloads cancels the intents before the tasks: late
responses and reopening must not recreate copies deleted on purpose.

The password in the Keychain and private local data use protection until the
first unlock of the device, so they can be used even after the
screen is locked again. No credential is written to the queue.
Details: [BACKGROUND-DOWNLOADS.md](../BACKGROUND-DOWNLOADS.md).

## Verification on the distributed commit

On 1 November 2026, all successful:

- 94 Python tooling, distribution and asset tests.
- 56 Swift core tests: persistence of the whole selection, limited batches,
  deduplication, account isolation, stale responses after deletion and
  interruption between saving a page and updating the queue.
- 11 UI tests on iPhone 17: finished at **05:19:52 CET**, Europe/Rome.
- 11 UI tests on iPad A16: finished at **05:32:53 CET**, Europe/Rome.

Three new tests for each simulator use a local HTTP server with original
pages and slowed-down transfers, the real iOS background session and
the simulator Keychain: continuation after Home, termination and
reopening without reselecting the queue, removal during a download without
reappearing after relaunch. The reopening test also checks that a
page already saved is not requested again. The eight existing tests
cover reading, bookmarks, offline filters, ranges, navigation and covers.

These tests run on iPhone/iPad simulators; they do not prove a session on a
physical iPhone with the screen locked. No user server or content was
used for the tests.

## Distribution

Distributed to the internal TestFlight group on **1 November 2026 at 05:40 CET**
(Europe/Rome). Archive, export and upload succeeded; pipeline completed
successfully. Apple status read back: `VALID`, `IN_BETA_TESTING`. Italian and English
release notes published and verified at **05:41 CET**.

To install it: TestFlight → Tankarr Reader → **Aggiorna** (Update), version **1.0.0 (9)**.
The existing public submission was not replaced by this internal TestFlight
distribution.
