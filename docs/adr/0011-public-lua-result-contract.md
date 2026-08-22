# ADR 0011: Define public Lua result contracts

- Status: Accepted
- Date: 2026-08-22

## Context

Commands and buffer-local keymaps do not consume return values, but the same
actions are exposed as a public Lua API for keymaps and custom workflows. Some
facade functions returned useful values from their implementation while
others discarded them. A caller therefore could not reliably distinguish an
opened interface, a rejected action, an in-memory source change, and a durable
mutation.

Prompt-based actions add another boundary: launching a prompt is synchronous,
but the user's later choice is not.

## Decision

- Public functions that open UI or control a session return a boolean. `true`
  means the synchronous action was accepted; `false` means it was rejected or
  had no effect. For `vim.ui` prompts, `true` means the prompt was launched; it
  does not predict the later answer.
- Public source mutations return `ok, message, persisted`. `ok` says whether
  the change was accepted. `message` is `nil` when nothing needs explaining;
  otherwise it describes the result, warning, or error. `persisted` is always
  a boolean and is `false` when the mutation fails or no mutation occurs. A
  successful `false` value means the source changed only in a modified buffer
  and still needs to be written.
- Public queries return their requested data. Validation actions return their
  status together with the cards and diagnostics they computed.
- `setup(opts)` returns `true` after applying a valid configuration and keeps
  raising an error for invalid configuration.
- `command(args)` returns the result of the routed public function. The
  `:Flashcards` command continues to ignore that result, so command-line and
  keymap behavior does not change.

## Consequences

Lua callers can branch on acceptance and persistence without inspecting UI
state or notifications. Existing callers that only use the first boolean keep
working. Callers must still handle prompt completion in the prompt callback;
the API does not turn asynchronous input into a synchronous result.
