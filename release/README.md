# Release metadata

- `min_version.txt` — the oldest version that still works, as `x.y.z`, or
  empty. Builds older than this see a forced update they cannot dismiss (on
  Android and iPhone, once the store offers a newer build). Set
  it only when old builds would actually break (a server or data change they
  cannot read), never just because there is a new release.
- `notes.json` — optional `{"en": "...", "ar": "..."}` for the next release.
  Without it the notes are the commit subjects since the last tag.

Both are read by `tool/write_latest_json.py`, which every release workflow
calls to write `latest.json`.
