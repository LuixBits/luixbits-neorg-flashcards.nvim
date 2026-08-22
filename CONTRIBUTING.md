# Contributing

Bug fixes, documentation corrections, and focused feature proposals are
welcome. Please open an issue before a large UI, scheduling, or storage change
so its interaction and data format can be agreed before implementation.

## Development setup

Required:

- Neovim 0.10.4 or newer;
- Bash;
- Lua 5.4 when running the standalone syntax check.

Neorg is optional for normal use, but the integration suite exercises it. Nix
can provide the complete release check environment. Node.js is needed only for
changes under `video/`.

Run the main checks from the repository root:

```sh
bash scripts/test.sh
bash scripts/check-clean-install.sh
```

If you have Nix, run the same package, formatting, documentation, workflow,
headless, and Neorg integration checks used for release validation:

```sh
nix flake check --print-build-logs
```

Video changes have their own checks:

```sh
npm ci --prefix video
npm run check --prefix video
npm run compositions --prefix video
npm run still --prefix video
```

## Pull requests

Keep changes focused and explain the observable behavior, not only the files
changed. Add tests for behavior changes and update the README, Vim help, and
changelog when the public interface changes.

Flashcard fixtures must be synthetic. Do not commit personal note contents,
review ledgers, machine-specific paths, or captured credentials.

Before opening a pull request:

- run the checks relevant to the changed files;
- format Lua with StyLua;
- confirm a clean install still works without Neorg when runtime code changes;
- check both the visible shortcut ribbon and `?` help after changing a UI
  action;
- mention any check you could not run and why.

Security reports follow [SECURITY.md](SECURITY.md), not the public bug form.
