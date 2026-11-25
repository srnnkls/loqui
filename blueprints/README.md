# Blueprints

Strict lint, format, type-check, and hook configuration for projects that follow the loqui guides, distributed with [phora](https://github.com/srnnkls/phora).

## Start a project

A project pins the runner, `bin/loqui`, as a mise file task in its own `mise.toml`:

```toml
[tasks.loqui]
file = "git::https://github.com/srnnkls/loqui.git//bin/loqui?ref=main"
```

mise fetches the repository at `ref` into its cache and runs the script from there, so the blueprints it reads come from the same commit. `ref` takes a branch, tag, or commit; a tag or commit pins loqui for the project.

```bash
mise run loqui init rust python          # bind the blueprints at the runner's ref
mise run loqui init go --var go_module=example.com/demo
```

`loqui init` merges each language's `phora.toml` into the project's and binds every `loqui-*` source to the ref the runner was fetched at, copies scaffold files the project lacks, writes `hk.pkl` when absent, then runs `phora sync`, `mise trust`, and `mise install`. It never overwrites a project file. To move a project to another loqui version, change `ref` and run `mise run loqui init` with the same languages again.

To develop loqui itself, point `file` at a checkout's `bin/loqui` and run `mise run loqui init --local rust`; the sources then bind the committed HEAD of that checkout through `phora.local.toml`.

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
| Rust | `rustfmt.toml`, `clippy.toml`, `.loqui/rust/lints.toml` | `#[expect(lint, reason = "...")]` in source |
| Python | `ty.toml`, `.loqui/python/ruff.toml` | `ruff.toml` extends the base; `ignore` and `extend-per-file-ignores` only, never `select` |
| Go | `.golangci.yml` (rendered with `go_module`) | `//nolint:linter // reason` |
| Emacs Lisp | `.loqui/elisp/strict.el` | `Eask` loads it |
| Zig | `.loqui/zig/check.zig` | `build.zig` calls `addChecks` |
| Bash | `.shellcheckrc` | `# shellcheck disable=SCxxxx` with a reason |

Cargo has no way to extend a lint table from another file, so `loqui merge-lints` writes `.loqui/rust/lints.toml` into `[workspace.lints]` (or `[lints]` for a single package) on every sync, and the `rust-lints` gate step fails when the table or a member's `lints.workspace = true` drifts.

Toolchain pins for the lint tools live in the managed `.config/mise/conf.d/loqui*.toml`; compiler and runtime versions stay in the project's own `mise.toml`.
