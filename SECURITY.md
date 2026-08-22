# Security Policy

## Supported versions

Security fixes target the latest tagged release and the current `main` branch.
Older tags are not maintained.

## Local filesystem boundary

The configured `flashcards_dir` is the plugin's read and write boundary. Setup
creates it when absent, then pins the resolved directory identity for that
setup session. Card creation, `:Flashcards open`, source changes, and history
writes use guarded paths inside that root.

If the root is moved, replaced, or retargeted through a symlink while Neovim is
running, collection operations fail instead of following the replacement.
Restore the original directory and rerun `setup()`, or restart Neovim, after an
intentional move.

These checks protect note files from accidental or redirected plugin writes.
They are not a sandbox against arbitrary Neovim configuration, another plugin,
or a process already running as the same operating-system user.

## Report a vulnerability

Do not publish exploit details, private note contents, or a working proof of
concept in a normal issue.

Use the repository's **Report a vulnerability** button under the Security tab
when it is available. If private vulnerability reporting is unavailable, open
a minimal issue titled `Security contact requested` without technical details;
the maintainer will arrange a private channel.

Include these details in the private report:

- the affected plugin version or commit;
- the Neovim version and operating system;
- the security impact and affected data;
- the smallest reproduction you can provide safely;
- any known workaround.

Flashcard files may contain personal study notes. Redact their contents and
paths unless a specific value is necessary to reproduce the issue.

Ordinary crashes, incorrect scheduling, and UI bugs belong in the public bug
report form unless they cross a security boundary or expose data.
