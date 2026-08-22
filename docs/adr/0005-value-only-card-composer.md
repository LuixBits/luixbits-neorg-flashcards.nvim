# ADR 0005: Use a value-only card composer

- Status: Accepted
- Date: 2026-08-22

## Context

The first add form rendered each field as an editable label prefix followed by
its value. Saving depended on every prefix remaining on its original physical
line. Backspace, linewise editing, or multiline paste could therefore damage
plugin-owned structure, and errors were found only after submission.

The add path also changed a target buffer before running `:write`. A failed
post-write hook could leave the card on disk while the form still appeared
unsaved, so retrying created a duplicate. The form did not show its target or
protect a changed draft when closing.

## Decision

- The composer buffer contains one raw, single-line value for each schema
  field. Labels, required marks, placeholders, field help, validation, target
  context, and save status are extmark decorations rather than buffer text.
- Line-count changes are rejected and the last valid draft is restored. A
  Backspace, word deletion, and Delete are also stopped at value boundaries so
  they cannot join adjacent fields. A separate multiline editor will be
  designed before code or long-explanation card types are enabled.
- The file path and card type are captured when the composer opens. Later hub
  or window changes cannot redirect that draft.
- Required fields are validated together, errors remain visible beside their
  fields, and focus moves to the first invalid value.
- `Ctrl-S` saves and closes. `Ctrl-N` saves, restores schema defaults, and
  stays open for another card. Closing a changed draft requires confirmation.
- The save callback returns an explicit `{ ok, persisted, path, message }`
  result. A dirty loaded target may accept a change with `persisted = false`;
  the composer treats it as committed to that buffer and tells the user to
  write it.
- Card insertion builds candidate source lines and commits them through the
  same buffer-aware store used by scheduling changes. Notifications and hub
  refreshes occur after the commit and cannot turn a successful write into a
  retryable draft.
- Composer mappings, its compact footer, and `?` help continue to come from
  the shared action catalogue. No new global or NVF shortcut is added.

## Consequences

Deleting a visible label is impossible because labels are not stored in the
draft. Failed validation or persistence leaves every value available for
repair. Adding to a modified source preserves unrelated edits without writing
them automatically, while post-write hook failures cannot cause duplicate
cards on retry.

Schemas may provide `title`, `placeholder`, and `help` presentation metadata.
The composer requires Neovim 0.10's inline virtual text support. Multiline
fields, collection selection, type selection, and live preview remain later
layers on the same structured draft model.
