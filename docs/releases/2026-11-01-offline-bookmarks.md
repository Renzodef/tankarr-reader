# Offline bookmarks with sync when back online

- Sources: [`d52a3c7`](https://github.com/Renzodef/tankarr-reader/commit/d52a3c76722618eb79e32d374eef78df09c161d3).
- [Verification and TestFlight pipeline](https://github.com/Renzodef/tankarr-reader/actions/runs/41277428250).

## Behaviour

Saving, moving and removing a bookmark also works offline after the server
has confirmed the permission the first time. The reader and the bookmarks list
show the pending changes. The local write comes before the remote one:
closing the app or losing the connection does not lose the change.

Reopening the app online, reconnecting, returning to the foreground online or refreshing
the bookmarks retries the pending items. Offline mode chosen manually
stays on until it is turned off. An error leaves the items
pending: an old remote list cannot make a local removal reappear.

The atomic file `bookmarks-sync.json`, separated by server identity and account,
contains the remote snapshot, the verified permission and the pending changes.
A confirmation can remove only the UUID of the change that was sent, not that
of a later change to the same series. Old `bookmarks.json` files are
read without losing bookmarks. The state is private, protected by the device
and excluded from iCloud backup together with the offline storage.

For each series the last explicit local change is sent when back
online and replaces the shared bookmark of that series. The other series
remain unchanged. Simply changing page still saves only the
local position; the demo still does not contact the server.

Deleting downloads keeps the pending bookmark changes. Disconnecting
the account deletes them after a confirmation that says so. Responses belonging
to the previous session cannot recreate the journal after disconnection.
No polling, additional service or change to the Tankarr backend.

## Verification

- Pre-push: **94 Python tests**, assets and privacy manifest succeeded.
- Mac, core tests: **64 Swift tests** succeeded, including 8 new cases for persistence,
  delayed confirmations, removals, isolation, migration and permissions.
- iPhone 17, test HTTP server: offline bookmark, closing and reopening,
  503 error, reopening online with automatic sync, offline removal
  and subsequent remote confirmation. **1 UI test succeeded in 82.9 seconds**.
- Full iPhone 17 suite: **13 UI tests, zero errors**, finished on 1 November
  2026 at **06:49:40 CET** (Europe/Rome).
- Full iPad suite: **13 UI tests, zero errors**, finished at **07:05:03 CET**.
- Archive and export succeeded; Apple upload completed at **07:06:55 CET**.
- **1.0.0 (11)** distributed to the internal TestFlight group at **07:08:59 CET**.
  Apple status `VALID` / `IN_BETA_TESTING` and Italian/English notes verified via API.

No change to the public version already in review on the App Store.
