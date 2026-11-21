# Followed series and new-chapter notifications

- Follow button in the series page, choice shared on the same account and filter
  of the followed series in the library.
- Native APNs registration and permission request at the first Follow, with
  a link to the settings if denied. No watcher or polling in the app.
- Notifications open the series only for the matching server/account;
  no URL or command from the payload is executed.
- Gateway with persistent outbox, authenticated Tankarr webhook, catalogue
  baseline at the moment of Follow and deduplication of imported chapters.
- Support for provider identifiers containing dots, while keeping the
  rejection of paths, queries and traversal; these IDs also apply to bookmarks.
- Privacy updated for device registration and series selection.

The Push Notifications capability requires an updated App Store profile; the
server requires an APNs key separate from the App Store Connect key.
Without it Follow works and the missing push configuration is
reported: an unverified delivery is not claimed. For the first real
notification a signed build on the phone and the iOS permission are also needed.

Distribution: the relevant push to main triggers the full verification and the
TestFlight upload on the Mac runner. It does not select or withdraw App Store versions
in review. Before a new public submission update the App Store Connect privacy
answers for the identifiers and the reading content sent to the
configured server, used only for app functionality and without tracking.
