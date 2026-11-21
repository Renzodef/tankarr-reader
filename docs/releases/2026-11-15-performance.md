# Covers and reading

Covers have a cancellable queue with two active requests and a
network session separate from catalogue, bookmarks and pages. Scrolling away from
a cell cancels its wait before the HTTP timeout starts. Temporary
429/502/503/504 errors and timeouts are retried at most twice.
Authentication errors, missing resources and redirects remain errors.

The cover cache keeps up to 64 MiB on disk, separated by
server/account identity and with a five-minute expiry. Decoded
thumbnails use the existing 32 MiB in-memory cache. Refreshing the
catalogue keeps the valid images and retries the failed ones. Disconnecting
deletes the account's cache and late responses do not recreate it.
ImageIO prepares the thumbnails off the main thread without decoding
the full-resolution cover in memory.

The three recently viewed pages can be reused in memory,
with a 64 MiB limit and reset on session change. Preparing
pages for display is asynchronous. The slider debounce
goes from 150 to 40 ms. A whole volume is never preloaded.

The privacy manifest declares access to the dates of the cache files only
in the app container, according to the
[Apple documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

Automatic verification: concurrency limits, cancellation in the queue, persistent cache,
account isolation, expiry, maximum space, transient errors, authentication
and redirects. The same iOS app is available on Apple Silicon Macs as an app
designed for iPad/iPhone. Smoothness, background downloads and navigation
must be verified on the new TestFlight build on real devices.
