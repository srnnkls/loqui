# Blueprints

Strict lint, format, type-check, and hook configuration for projects that follow the loqui guides, distributed with [phora](https://github.com/srnnkls/phora).

## Start a project

```bash
loqui init rust python          # bind the GitHub repository
loqui init --local rust         # bind a loqui git checkout through phora.local.toml
loqui init go --var go_module=example.com/demo
```

Runner: `bin/loqui`, installed with the loqui skill as `scripts/loqui` next to `blueprints/`; a consumer puts it on `PATH`. `loqui init` merges each language's `phora.toml` into the project's, copies scaffold files the project lacks, writes `hk.pkl` when absent, then runs `phora sync`, `mise trust`, and `mise install`. It never overwrites a project file.

After that, the project runs:

| Task | Runs |
|---|---|
| `mise run loqui:check` | every hk gate step, including tests |
| `mise run loqui:fix` | formatters and fixers |
| `mise run loqui:verify` | `phora sync --frozen --force`, then `git diff --exit-code`; fails on drifted managed files |
| `mise run loqui:update` | `phora update --prune`, then the full gate |

## Ownership

Each `<language>/` holds its blueprint files under plain names; the `take` table in `<language>/phora.toml` maps each one to its path in the project. Files under `<language>/scaffold/` are copied once by `loqui init` and then belong to the project.

Deployed blueprint files are phora artifacts: verbatim, hash-verified, overwritten on sync. A project never edits them; it adds exceptions on top, one rule at a time with a reason, per [Fix lint causes](../skills/loqui/SKILL.md#fix-lint-causes):

| Language | Managed | Project-owned extension point |
|---|---|---|
| all | `.loqui/hk/gate.pkl`, `.config/mise/conf.d/loqui.toml` | `hk.pkl` imports the gate and adds its own steps |
| Rust | `rustfmt.toml`, `clippy.toml`, `.loqui/rust/lints.toml`, `.loqui/rust/merge-lints` | `#[expect(lint, reason = "...")]` in source |
| Python | `ty.toml`, `.loqui/python/ruff.toml` | `ruff.toml` extends the base; `ignore` and `extend-per-file-ignores` only, never `select` |
| Go | `.golangci.yml` (rendered with `go_module`) | `//nolint:linter // reason` |
| Emacs Lisp | `.loqui/elisp/strict.el` | `Eask` loads it |
| Zig | `.loqui/zig/check.zig` | `build.zig` calls `addChecks` |
| Bash | `.shellcheckrc` | `# shellcheck disable=SCxxxx` with a reason |

Cargo has no way to extend a lint table from another file, so `merge-lints` writes `.loqui/rust/lints.toml` into `[workspace.lints]` (or `[lints]` for a single package) on every sync, and the `rust-lints` gate step fails when the table or a member's `lints.workspace = true` drifts.

Toolchain pins for the lint tools live in the managed `.config/mise/conf.d/loqui*.toml`; compiler and runtime versions stay in the project's own `mise.toml`.
