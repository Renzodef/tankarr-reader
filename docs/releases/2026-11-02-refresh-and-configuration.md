# Refresh, configuration and chapter continuity

- Connection: **Refresh Tankarr** button with progress status and result.
- Library refresh in the existing session; iOS cancellations
  ignored without showing false connection errors.
- JSON export/import of connection, language, reading options and followed series;
  passwords and tokens are not exported. Restoring preferences is tied
  to the identity of account and server.
- Gateway: shared order between catalogue and chapter boundaries, with prologues
  before the numbered chapters and no return to the prologues after the last one.
- The explicit refresh invalidates the gateway's short metadata cache;
  it does not start filesystem scans or searches for new downloads.

Reader shows only the chapters already imported on the server. The number of
chapters present in the sources is not the same as the number of readable files.
This version does not enable administrative downloads from the read-only client.
