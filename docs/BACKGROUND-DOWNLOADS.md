# Downloads and persistent queue on iOS

The real download uses a single `URLSessionConfiguration.background` per account,
with a stable identifier, delegate and `sessionSendsLaunchEvents = true`.
`isDiscretionary = false` gives priority to the user-started selection; iOS
remains free to defer it for network, power and requests created in the background.
No silent audio, keepalive timer or improper background mode.

## State and lifecycle

- The complete selection, in catalogue order, is written atomically to
  `.metadata/background-queue.json` before creating tasks. It contains series, books,
  tokens and missing pages, without URLs or credentials.
- Fetching the book metadata is also a background download. Books
  not started yet do not depend on a Swift `Task` kept in memory.
- Batches of up to 64 requests, with two connections per host. This avoids waking
  the app after every single page; admission is reduced if space is short.
- In the background iOS handles the network in another process. The delegate moves
  the temporary files immediately, then validates response, size and image. The store
  checks space and token, saves the page/checksum and finally updates the queue.
- The UIKit completion handler is called on the main actor only after
  the events have been processed, the writes done and any new batch created.
- After a termination the session is reattached to the same tasks and the
  queue is read again. If iOS cancelled the tasks because of a force quit, they are recreated on
  reopening. A page saved before the queue was written is
  recognized through manifest/checksum, without downloading it again.
- An error keeps the selection and stops the attempts; returning to the app,
  reconnecting or «Riprendi la coda» (Resume queue) retry. An initial lack of connectivity
  is handled by `waitsForConnectivity`.
- Offline keeps the queue suspended; explicitly pausing a book keeps the
  pages but removes that book from the active queue. Removing series/everything cancels the
  intents before the tasks, so late callbacks do not recreate the downloads.

## Protection

Password in the Keychain with `AfterFirstUnlockThisDeviceOnly`; offline files and queue
protected until first unlock, private (0700/0600), excluded from backup. This
class allows writes with the screen locked after the first unlock since boot.
Credentials are passed to iOS only in the header of the authenticated request;
they are not saved in our journal. TLS stays verified, cookies/cache disabled.
Apple's background networking follows redirects on its own: the client
rejects a file if the final URL differs from the requested one. The configured
gateway must serve the page endpoints directly, without redirects.

## Verification

`BackgroundDownloadQueueTests` checks the queue after process loss,
chapters not started, batching/deduplication, fencing after removal, interruption between
writing the page and writing the queue, account isolation and requests without
credentials in URLs. `BackgroundDownloadUITests` uses a local HTTP server
in the XCTest runner and the real iOS download service: Home during slow
transfers; closing/reopening halfway through a selection; subsequent offline reading.
The simulator is ad hoc signed to also test the real Keychain, without
Apple certificates or credentials. The tests do not contact the user's server.

Apple sources: [background download](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background),
[suspension and force quit](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)).
