# Interactive downloads in the series

- Sources: [`c82486e`](https://github.com/Renzodef/tankarr-reader/commit/c82486ecb80c77c1f0e5ebabf82ec15f0c30356a).
- [Verification and TestFlight pipeline](https://github.com/Renzodef/tankarr-reader/actions/runs/41274526121).

## Change

The series page shows under each chapter the same indicators as the
global Downloads screen: bar, percentage, pages saved out of the total,
storage used, position in the selection, pause, completion and errors.
A summary shows how many books are complete and how many are still queued.
Even a book still waiting for its metadata shows its queued status.

The button next to the chapter pauses or resumes; after completion
it lets you remove the local copy. Swiping sideways offers removal
with confirmation, even for incomplete downloads. Pause and resume have distinct
accessibility labels and Italian/English texts.

`DownloadBookProgress` is shared by the two screens and observes
`DownloadManager` directly. Switching screen does not create another queue, does not reset the
count and does not start a second transfer. The new manager methods
read order and number of items without changing the background download
engine or the format of the persistent journal.

## Verification

Before the push: 94 Python and 56 Swift tests succeeded. The targeted UI test on
iPhone 17 simulates slow pages from a local server and checks progress
in the series, pause, the same count in the global list, return to the series,
resume, completion and removal of a single chapter while keeping the other.
The screen captured during the download was also checked.

The full suite on iPhone 17 completed **12 tests with zero errors** on
1 November 2026 at **06:03:41 CET** (Europe/Rome).

The iPad suite completed **12 tests with zero errors** at **06:17:30 CET**.
Archive, export and upload succeeded. **1.0.0 (10)** distributed to the internal
TestFlight group at **06:25:39 CET**; Apple status `VALID` / `IN_BETA_TESTING`
and Italian/English notes verified via API. No change to the Tankarr
server or to the existing App Store submission.
