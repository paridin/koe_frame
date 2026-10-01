# Media intake slices

The set incrementally implements approved product scenario P-01 from
[`../../../product.md`](../../../product.md). The server foundation is
first so HTTP and client code can depend on one tenant-safe offset/checksum
contract.

## Order

1. `01-session-and-local-staging.md` — implemented in the current working tree;
   session persistence, bounded chunks, checksum finalization, safe relative
   paths, and server-owned staging permissions.
2. `02-authenticated-tus-api.md` — pending resolution of the private
   `defdo_auth_client` dependency and registration of the narrow tenant scope.
3. `03-mac-folder-client.md` — pending the authenticated API; enumerates a
   folder, sends a manifest, resumes at the server offset, and reports progress.
4. `99-verification.md` — durable gates for P-01 as the HTTP API and client
   slices land.

P-01 is not done until a real interrupted multi-gigabyte directory transfer
resumes and its staged files have verified digests and configured modes/owner.
