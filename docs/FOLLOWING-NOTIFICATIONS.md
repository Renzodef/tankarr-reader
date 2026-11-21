# Followed series and new-chapter notifications

In a series page, **Follow series** saves the choice on the server for
the reader account. Tapping **Following series** again stops the notifications.
The bell in the library filters the followed series; the filter combines with
search and offline mode. The choice is shared across the devices of the
same account and separate from bookmarks, monitoring and automatic downloads.
The demo keeps a local selection and does not register devices with Apple.

The first Follow asks for the iOS permission when the server has configured push.
If it is denied, the series stays followed and the series page offers **Open
notification settings**. iOS handles delivery even with Reader in the background or closed;
no polling, watchers or timers are created in the app. A push cannot be received
before installing a compatible build, opening the app and allowing
notifications on the device.

A notification opens the series page. The payload must match the current server
and account; it cannot contain commands or URLs to open. Saving
the bookmark remains explicit and does not change as a result of a notification.

## Gateway and protocol

The opt-in gateway of the self-hosted stack declares `following_writable` and
`push_notifications_available` in `GET /v1/status`. Old servers continue
to work without these fields. `GET /v1/follows` returns the selection;
`PUT/DELETE /v1/series/ID/follow` changes it; `PUT/DELETE
/v1/notifications/devices/UUID` registers or removes only the device.
Writes require authentication and `X-Tankarr-Reader: 1`, reject browser
Origin and do not allow administrative changes. The proxy overwrites
`X-Tankarr-Reader-User` with the actually authenticated account.

On the server, Tankarr sends the `chapter_imported` event to the internal receiver,
protected by a dedicated token. The series is snapshotted at the moment of Follow:
chapters already present, backfill, replacements and duplicate imports do not trigger
notifications. A chapter is available when the import into the library has succeeded;
an online announcement without a readable file does not generate a push.

The database keeps selections per account, devices and a persistent outbox.
Temporary Apple errors are retried with backoff and a limit; revoked
tokens are removed. No download or bookmark is changed. The
backend does not poll the catalogue periodically: the event wakes the outbox.

Offline you can view the saved selection, but changing it requires the
server. Going back online reloads the choices. Disconnecting the account removes the
device's push registration when reachable and disables the
local registration with APNs; the other devices remain independent.

## Apple configuration

The bundle stays `app.tankarr.reader`. Enable **Push Notifications** for
the App ID and regenerate the App Store profile with `aps-environment=production`.
The signing check rejects profiles without this capability. The project
uses the sandbox environment in Debug and production in Release/TestFlight/App Store.

The gateway requires an **APNs** `.p8` key, its Key ID and the Team ID.
An App Store Connect key for publishing builds is not an APNs key.
The key stays in the server's credential store, never in the app, in Git, in
logs or in command arguments. Without configuration Follow works,
but the app states explicitly that push is not configured yet.

Before public distribution update the privacy information: the server chosen
by the reader receives account, series selections, APNs token, language and notification
environment, exclusively for this feature. No tracking
or advertising is used. Page files and passwords never go into notifications.

## Verification and rollback

The core tests verify compatibility with earlier servers, restricted routes and
isolation of notifications between accounts/servers; the UI test tries Follow, filter,
reopening and removal on iPhone/iPad. The gateway tests verify the authenticated
webhook, baseline, deduplication, persistent outbox and token rotation.
Real delivery on iPhone requires a token obtained from a signed build and
the iOS permission granted: a simulation does not prove APNs delivery.

To disable push remove the gateway's APNs configuration and
restart only the gateway. To also withdraw Follow disable its
configuration, keeping the database for restoring; clients will see the
capability turned off. Bookmarks and library do not depend on this database.
