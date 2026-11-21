# Portable configuration and refresh

In **Connection → Refresh Tankarr** the catalogue, covers,
bookmarks and followed series are reloaded. It does not start scans, downloads, restarts or searches
on the server. The library refresh gesture also uses this path:
a valid session stays active, without resetting downloads or pending writes.
A request cancelled by iOS does not become a connection error. Only
a real change in reachability requires selecting LAN/HTTPS again.
The gesture in offline mode refreshes only the copies on the device.

**Export configuration…**, next to **Import configuration…**, saves a
version 1 JSON at the location chosen through Files. It contains:

- local/HTTPS addresses, username, connection mode and server identity;
- interface language and reading options of the individual books;
- list of the series followed for notifications.

The file does not contain passwords, APNs tokens, downloaded files, the download queue or
unsynced bookmark changes. Addresses, accounts and series are
still personal data: share it only with whoever needs to receive them.

Importing the file fills in the fields; tap **Connect** to verify them and
apply the preferences. The already saved password is kept only for the
same account/server and the addresses already configured. The identity declared
by a file does not authorize sending the password to a new address. On a
new device or when the addresses change you enter the password once.
Old connection-only configurations, including those with a password,
remain importable; a new export never copies that password.

Book options and followed series are restored only after
verifying the server identity and the same username. Followed series
are added to those already present, without deleting the others. Consent
to notifications belongs to iOS and must be given on each device: the JSON cannot
transfer it, nor can it enable APNs if the server is not configured.
