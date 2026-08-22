# ADR 0008: Separate source commits from history delivery

- Status: Accepted
- Date: 2026-08-22

## Context

A rating changes the card's scheduling fields and adds an append-only history
event. Those destinations cannot be committed as one filesystem transaction.
A source save can succeed while a history append fails, and a loaded source
may contain user edits that the plugin must not write without permission.
Directly replacing a source file in place also risks leaving a partial file if
the write is interrupted.

## Decision

- Setup creates the collection root when absent and pins its canonical path and
  filesystem identity. Every later collection operation verifies that the
  configured path still names that directory. A moved, replaced, or retargeted
  root is rejected until setup runs again.
- `:Flashcards open`, default-file bootstrapping, and add-card writes resolve
  through the same guarded store as later source mutations. They check the
  pinned root before creating parent directories and recheck it before the
  final write.
- Unloaded source files are written to a temporary file in the same directory
  and renamed over the destination. Existing file permissions are copied to
  the temporary file before the rename. Temporary-file, permission, or rename
  failures abort the source change. A per-source lock serializes plugin writes;
  immediately before rename, the writer resolves the source again and compares
  its destination and content fingerprint with the snapshot it read. A changed
  source is rejected instead of overwritten.
- Every source mutation must resolve inside the configured collection root at
  the time it is written. A source symlink cannot redirect a write outside the
  collection. Deletion backups canonicalize their parent but never follow a
  symlink in the backup filename itself.
- Loaded source buffers are the authority. A modified buffer is changed in
  memory and remains unsaved; an unmodified loaded buffer is changed and
  written through Neovim. Stale, read-only, or non-modifiable sources reject
  the operation.
- Source persistence and `reviews.jsonl` delivery are separate commits. The
  project does not claim a cross-file transaction or crash-proof `fsync`
  guarantee.
- If a source change is persisted but its history append fails, the normalized
  event is added to an outbox under
  `stdpath("state")/neorg-flashcards/outbox/`. Each history destination has a
  separate hashed JSONL file. The destination is resolved to its canonical
  absolute path before hashing, so a real path and a symlink alias share one
  ledger, lock, and outbox.
- Ledger appends and outbox updates use short, exclusive lock files and guarded
  same-directory atomic replacements. They reject symbolic-link and non-file
  destinations, preserve existing permissions, and recheck the snapshot before
  rename. The ledger must remain a separate `.jsonl` file inside the collection
  root, so it can never resolve to a card source. A lock
  contains its owner's PID and a unique token. Release removes only the same
  token. One reaper may remove a lock only after the operating system confirms
  that its owner PID no longer exists. A reaper lock left by a crashed reaper
  follows the same dead-owner and same-token check. A live or ambiguous owner
  is never displaced; timeout errors name the lock that may need manual
  removal.
- A history append checks the current ledger for its event ID while holding the
  destination lock. There is no process-local event-ID cache. This makes a
  retry idempotent even when another Neovim instance appended the event, and it
  does not suppress an append after the ledger was deleted or replaced.
- Outbox writes read and merge the current file while holding its lock, then
  replace it through a same-directory temporary file and rename. Delivery
  removes only the matching event IDs. Events added by another instance and
  malformed raw lines remain in the file. A clean outbox is removed only after
  its last valid event is delivered.
- Outbox events are loaded during setup and retried before later history
  writes, on focus, and before exit. If both the ledger and outbox are
  temporarily locked or unavailable after a source commit, the event remains
  in an in-memory emergency queue and is retried by the same hooks. Failure to
  make that queue durable before exit produces an explicit error.
- Persisted history events explicitly carry their numeric version, type, and
  event name. They also require a finite epoch or timestamp that `os.date` can
  represent. New events receive this metadata before normalization; malformed
  stored events are reported per line instead of receiving inferred values
  whenever they are read.
- When a rating or card-state change exists only in a modified source buffer,
  its event stays in memory until that source is written. Undo before the write
  cancels a pending rating, and discarding the buffer discards matching unsaved
  events. They do not enter the durable outbox because the corresponding source
  change is not durable. Card-state changes use this path whether they start in
  a review, the hub, or the public Lua API.

## Consequences

A direct source or JSONL write is all-old or all-new at the rename boundary, and a
temporary history outage does not silently lose an event after a successful
source commit. Concurrent Neovim instances merge retry events instead of
replacing one another's queues, and health checks retain corrupt outbox
evidence for repair. Users still need normal filesystem backups: atomic
replacement and an outbox do not make the collection immune to disk loss or
guarantee two-file atomicity. The emergency in-memory queue is not crash
durable until its next successful outbox write. Intentionally moving a
collection requires another `setup()` call or a Neovim restart so the new root
identity can be pinned explicitly.
