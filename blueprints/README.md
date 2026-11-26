# Blueprints

Strict lint, format, type-check, and hook configuration for projects that follow the loqui guides, distributed with [phora](https://github.com/srnnkls/phora).

## Start a project

A project pins the runner, `bin/loqui`, as a mise file task in its own `mise.toml`:

```toml
[tasks.loqui]
file = "git::https://github.com/srnnkls/loqui.git//bin/loqui?ref=main"
```

mise fetches the repository at `ref` into its cache and runs the script from there, so the blueprints it reads come from the same commit. `ref` takes a branch, tag, or commit; a tag or commit pins loqui for the project.

mise loads `git::` file tasks only with `experimental` on, and the script runs under `uv`. The first `loqui init` needs both from the machine; afterwards the managed `.config/mise/conf.d/loqui.toml` sets `experimental` and pins `uv` for every checkout, CI included.

```bash
mise run loqui init rust python          # bind the blueprints at the runner's commit
mise run loqui init go --var go_module=example.com/demo
mise run loqui init rust-release         # add a layer to a bound project
```

`loqui init` writes each layer's `phora.toml` into the project's and pins every `loqui-*` source to the commit the runner was fetched at, copies scaffold files the project lacks, writes `hk.pkl`, then runs `phora sync`, `mise trust`, and `mise install`.

## Update a project

`mise run loqui:update` refetches the runner at `ref`, runs `loqui update`, then the full gate. `loqui update` does what `init` does for the layers the project already binds:

- the `loqui-*` sources and the `loqui` target in `phora.toml` are rewritten from the runner's blueprints and pinned to its commit, so new, renamed, and dropped managed files arrive with the next sync;
- scaffold files a newer blueprint added are copied when the project lacks them;
- `hk.pkl` is regenerated while it is still the one loqui wrote; an edited `hk.pkl` is kept, with a note.

A branch `ref` such as `main` moves the project to that branch's tip on every update; a tag or commit `ref` holds it until the project changes `ref`. Project sources and targets in `phora.toml` are never touched; bind them in a target other than `loqui`.

To develop loqui itself, point `file` at a checkout's `bin/loqui` and run `mise run loqui init --local rust`; the sources then bind the committed HEAD of that checkout through `phora.local.toml`.

After that, the project runs:

| Task | Runs |
|---|---|
| `mise run loqui:check` | every hk gate step, including tests |
| `mise run loqui:fix` | formatters and fixers |
| `mise run loqui:verify` | `phora sync --frozen --force`, then `git diff --exit-code`; fails on drifted managed files |
| `mise run loqui:update` | `mise run --no-cache loqui update`, then the full gate |

## Ownership

Each layer, `<layer>/`, holds its blueprint files under plain names; the `take` table in `<layer>/phora.toml` maps each one to its path in the project. Files under `<layer>/scaffold/` are copied once, when the project lacks them, and then belong to the project.

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
| Rust release | `.github/workflows/release-plz.yml`, `.loqui/rust-release/cliff.toml`; `[dist] cargo-dist-version` in `dist-workspace.toml` | `release-plz.toml`, the rest of `dist-workspace.toml` |

Cargo has no way to extend a lint table from another file, so `loqui merge-lints` writes `.loqui/rust/lints.toml` into `[workspace.lints]` (or `[lints]` for a single package) on every sync, and the `rust-lints` gate step fails when the table or a member's `lints.workspace = true` drifts.

Toolchain pins for the lint tools live in the managed `.config/mise/conf.d/loqui*.toml`; compiler and runtime versions stay in the project's own `mise.toml`.

## Rust release

The `rust-release` layer releases a Cargo workspace with [release-plz](https://release-plz.dev) and [cargo-dist](https://axodotdev.github.io/cargo-dist/):

1. Every push to `main` runs `release-pr`, which opens or updates a release PR with the version bumps and changelogs (git-cliff, `.loqui/rust-release/cliff.toml`).
2. Merging it runs `release`: release-plz publishes the unpublished crates to crates.io through trusted publishing and pushes the `v<version>` tag.
3. The `release` job dispatches cargo-dist's `release.yml` for that tag, which builds the binaries, attests them, and creates the GitHub Release.

`loqui init rust-release` copies `release-plz.toml` and `dist-workspace.toml`, adds `[profile.dist]` to `Cargo.toml`, and runs `dist generate`; the `rust-release-dist` gate step fails when `release.yml` drifts from `dist-workspace.toml`. `loqui update` keeps `[dist] cargo-dist-version` on the pinned cargo-dist.

The repository needs, once:

| Setting | Why |
|---|---|
| Settings → Actions → "Allow GitHub Actions to create and approve pull requests" | `release-pr` opens the release PR |
| a crates.io trusted publisher per crate: this repository, workflow `release-plz.yml` | `release` publishes without a stored token; crates.io accepts trusted publishing only after the first `cargo publish` from a maintainer's machine |
| optional: variable `RELEASE_APP_ID` and secret `RELEASE_APP_PRIVATE_KEY` of a GitHub App with contents and pull-request write | the release PR then triggers CI, which a PR opened with `GITHUB_TOKEN` does not |

A crate that cannot be published, for example because it depends on a git revision, sets `git_only = true` under its `[[package]]` (or `[workspace]`) in `release-plz.toml`: release-plz then versions it from its git tags and skips `cargo publish`, and cargo-dist still builds it. A workspace releasing several crates at one version keeps one tag by setting `git_tag_enable = false` on every package but the one whose binary ships.
