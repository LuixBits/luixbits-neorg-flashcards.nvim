# ADR 0005: Use one structured composer for add and edit

- Status: Accepted
- Date: 2026-08-22
- Amended: 2026-08-22

## Context

The first add form rendered each field as an editable label prefix followed by
its value. Saving depended on every prefix remaining on its original physical
line. Backspace, linewise editing, or multiline paste could therefore damage
plugin-owned structure, and errors were found only after submission. Editing
an existing card still opened raw Neorg source, so add and edit offered very
different levels of guidance and safety.

The add path also changed a target buffer before running `:write`. A failed
post-write hook could leave the card on disk while the form still appeared
unsaved, so retrying created a duplicate. The form did not show its target or
protect a changed draft when closing.

General question, definition, code, and sentence cards also need fields that
can contain paragraphs or code. Letting those lines spill into the protected
form would bring back the structural ambiguity that the composer removed.

## Decision

- The composer buffer contains one protected row for each schema field. Scalar
  rows hold the raw one-line value. A field with `multiline = true` holds a
  first-line preview while its complete value stays in the structured draft.
  Labels, required marks, placeholders, field help, validation, target context,
  and save status are extmark decorations rather than buffer text.
- Line-count changes are rejected and the last valid draft is restored. A
  Backspace, word deletion, and Delete are also stopped at value boundaries so
  they cannot join adjacent fields.
- Enter on a multiline field opens a focused scratch editor. `Ctrl-S` applies
  the complete value; `Esc` or `q` cancels it. Cancelling changed text requires
  confirmation, and the parent form cannot close behind an unresolved editor.
- Multiline values use an explicit on-disk block. The header is `field: |` and
  each value line has a two-space container indent. Only fields declared with
  `multiline = true` accept the block form; scheduler and identity fields never
  do. Single-line values keep `field: value`, and implicit continuation lines
  remain invalid rather than being guessed.
- The file path and card type are captured when the composer opens. Later hub
  or window changes cannot redirect that draft.
- Required fields are validated together, errors remain visible beside their
  fields, and focus moves to the first invalid value.
- Valid existing cards open the same composer with their schema-owned values
  filled in. Edit mode replaces only those schema-owned fields and preserves
  the stable ID and scheduler metadata. Save-and-new is disabled while
  editing. Invalid or malformed blocks continue to open as raw source because
  structural repair requires the literal block to remain visible.
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
repair. Adding or editing in a modified source preserves unrelated edits
without writing them automatically, while post-write hook failures cannot
cause duplicate cards on retry. Structured edit makes ordinary content
changes consistent with creation without hiding malformed source that needs
manual repair.

Schemas may provide `title`, `placeholder`, `help`, and `multiline`
presentation metadata. The composer requires Neovim 0.10's inline virtual text
support. The focused editor lets long values use ordinary buffer editing while
the parent form keeps one row per field. A parse, serialize, add, edit, or
restore round trip preserves the value's line breaks and indentation.
