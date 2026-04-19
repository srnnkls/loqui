---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust 2024 Edition

Migrating to the 2024 edition: RPIT capture, `if let` scopes, `unsafe extern`, and the `gen` reservation.

The 2024 edition is stable since **Rust 1.85 (February 2025)** and is the largest edition Rust has ever shipped. Most behavioral changes are either improvements (let chains, RPIT capture) or safety tightening (`unsafe extern`, `unsafe_op_in_unsafe_fn`).

If you aren't on the 2024 edition yet, getting there should be your highest-priority modernization task.

---

## Why Migrate

The 2024 edition unlocks three entire classes of ergonomics:

1. **Let chains** (see [quality.md](quality.md)) — no more nested `if let` pyramids.
2. **Cleaner lifetime story for RPIT** — the `Captures<'a>` workaround disappears.
3. **Safer-by-default unsafe** — unsafe operations become visible even inside `unsafe fn`.

It also sets you up for future features (generators / `gen { … }`, evolving match ergonomics) that depend on 2024 reservations.

---

## Automated Migration

```bash
# From a clean git state:
cargo fix --edition

# Then flip the edition in Cargo.toml:
#   edition = "2024"
# Or for workspace members:
#   [workspace.package]
#   edition = "2024"

# Verify:
cargo clippy --all-targets
cargo test --all-targets
```

`cargo fix --edition` handles the vast majority of structural changes automatically. What it can't fix is the small set of genuine behavioral changes — those are what this doc covers.

---

## Behavioral Changes

### RPIT Lifetime Capture

**2024 edition auto-captures all in-scope lifetime parameters in return-position `impl Trait`**, consistent with how `async fn` has always behaved. The old `Captures<'a>` workaround is no longer necessary — and the new `+ use<>` syntax lets you opt *out* when you genuinely need to.

```rust
// ✘ Rust 2021 — required the Captures trick
trait Captures<'a> {}
impl<'a, T> Captures<'a> for T {}

fn iter_2021<'a>(s: &'a [u8]) -> impl Iterator<Item = u8> + Captures<'a> {
    s.iter().copied()
}

// ✓ Rust 2024 — auto-captures 'a, just works
fn iter_2024<'a>(s: &'a [u8]) -> impl Iterator<Item = u8> {
    s.iter().copied()
}

// ✓ Opt out with use<> when you want no capture
fn static_iter() -> impl Iterator<Item = u8> + use<> {
    (0..10).into_iter()
}

// ✓ Partial capture — name exactly what you want to capture
fn partial_capture<'a, T>(s: &'a [T]) -> impl Iterator<Item = &'a T> + use<'a, T> {
    s.iter()
}
```

### `if let` Temporary Scopes

**2024 edition tightens temporary drop scopes in `if let … else`.** In 2021, a temporary inside the scrutinee could outlive the whole `if let` expression; in 2024, it drops at the end of the block.

```rust
// Behavioral change — lock.read() returns a guard that is now dropped
// at the end of the if-let block, not after the else-branch.
if let Some(v) = lock.read().get(&key) {
    use_value(v);
} else {
    // 2021: lock is still held here
    // 2024: lock guard has been dropped — OK to reacquire
    lock.write().insert(key, make());
}
```

This is strictly safer, but watch for code that accidentally relied on the old extended scope. `cargo fix --edition` flags cases where the change is likely material.

### `unsafe extern "C" { … }`

**Extern blocks must be marked `unsafe` in the 2024 edition.** This surfaces the fact that the author of the extern block is asserting the function signatures match the foreign definitions — a classic UB trap.

```rust
// ✘ Rust 2021
extern "C" {
    fn puts(s: *const c_char) -> c_int;
}

// ✓ Rust 2024 — required
unsafe extern "C" {
    fn puts(s: *const c_char) -> c_int;
}
```

Individual attributes that carry unsafe semantics also require the `unsafe(…)` wrapper:

```rust
// ✓ Rust 2024
#[unsafe(no_mangle)]
pub extern "C" fn my_export() {}

#[unsafe(export_name = "custom_name")]
pub extern "C" fn renamed() {}

#[unsafe(link_name = "libfoo_bar")]
unsafe extern "C" {
    fn bar();
}
```

### `unsafe_op_in_unsafe_fn` — Warn by Default

**In 2024, unsafe operations inside an `unsafe fn` must be wrapped in an explicit `unsafe {}` block**; otherwise the compiler warns. This makes the unsafe surface area visible even inside unsafe functions.

```rust
// ✘ Rust 2021 (allowed, unsafe ops invisible)
unsafe fn dangerous(p: *const u8) -> u8 {
    *p
}

// ✓ Rust 2024 — explicit inner block
unsafe fn dangerous(p: *const u8) -> u8 {
    // SAFETY: caller guarantees p is valid and points to an initialized byte
    unsafe { *p }
}
```

See [unsafe.md](unsafe.md) for the full pattern.

### Reserved Keywords: `gen`

**`gen` is a reserved keyword in the 2024 edition** in anticipation of generator syntax (`gen { … }` blocks, `gen fn`). Any identifier named `gen` must be renamed or escaped as `r#gen`.

```rust
// ✘ Rust 2024 — compile error
fn gen() -> u32 { 42 }

// ✓ Rename or escape
fn generate() -> u32 { 42 }
// or:
fn r#gen() -> u32 { 42 }
```

`try` semantics have also been refined in 2024, though practical breakage is rare.

### `Future` and `IntoFuture` in Prelude

No more `use std::future::Future;` — these traits are now in the 2024 prelude. Remove stale imports; `cargo fix --edition` handles this.

### Match Ergonomics / `expr_2024` Fragment Specifier

Macro authors should know: the `expr` macro-fragment specifier now matches additional expression forms in 2024 (notably `let` scrutinees in let chains). If you need the old behavior, use `expr_2021`.

```rust
// Macro author: use expr_2024 (the default in 2024-edition crates) to match let chains:
macro_rules! is_some_and {
    ($scrutinee:expr, $($pattern:pat)|+ if $cond:expr) => { … };
}
```

### Tail Expression Drop Scope

Temporaries in tail expressions of blocks now drop at the end of the block, not at the surrounding expression. This is almost always what you want — but if you had code relying on a temporary escaping the block, you'll need to bind it explicitly.

```rust
// ✓ Bind explicitly when you need to extend the lifetime
let lock_guard = MUTEX.lock().unwrap();
let value = lock_guard.clone();
```

---

## Migration Playbook

1. **Start from a clean git tree.** You want the diff reviewable.
2. **Run `cargo fix --edition`.** It handles 90%+ of mechanical rewrites.
3. **Flip `edition = "2024"`** in `Cargo.toml` (or `[workspace.package]` for workspaces).
4. **Run `cargo clippy --all-targets`.** Clippy surfaces 2024-edition lints that `cargo fix` doesn't apply automatically.
5. **Run your full test suite** — the `if let` and tail-expr drop-scope changes are behavioral.
6. **Check for reserved-keyword collisions** — grep for `fn gen\b`, `let gen\b`, etc.
7. **Remove stale imports** — `use std::future::Future;`, `use std::future::IntoFuture;` — the prelude now covers these.
8. **Tighten unsafe blocks** — the `unsafe_op_in_unsafe_fn` warning tells you where. Replace `unsafe fn foo() { *p }` with `unsafe fn foo() { unsafe { *p } }` and add a `// SAFETY:` comment to the inner block.

### Hybrid-Edition Workspaces

Workspaces can contain crates on different editions without issue. Migrate crate-by-crate. Declare workspace-wide defaults for new crates:

```toml
# Cargo.toml at workspace root
[workspace.package]
edition = "2024"
rust-version = "1.85"

# Individual crates inherit:
# [package]
# edition.workspace = true
# rust-version.workspace = true
```

See [modules.md](modules.md) for workspace inheritance in full.

### MSRV Coordination

The 2024 edition requires **Rust 1.85 or later**. If you ship a library:

```toml
[package]
edition = "2024"
rust-version = "1.85"   # or later — pick a version and stick to it
```

Don't mix "I want 2024 edition features" with "I support MSRV 1.82" — it won't compile.

---

## Summary

- **DO** migrate to the 2024 edition with `cargo fix --edition` — it's the single highest-leverage modernization task
- **DO** drop the `Captures<'a>` RPIT workaround — 2024 auto-captures; use `+ use<>` to opt out
- **DO** mark all `extern` blocks as `unsafe extern`
- **DO** wrap unsafe ops inside `unsafe fn` bodies in explicit inner `unsafe {}` blocks
- **DO** use `#[unsafe(no_mangle)]` / `#[unsafe(link_name)]` / `#[unsafe(export_name)]` attributes
- **DO** rename any identifier called `gen` (or escape as `r#gen`)
- **DO** bump `rust-version` to 1.85+ alongside the edition flip
- **DON'T** treat 2024 migration as optional — pre-2024 idioms keep accumulating technical debt
- **DON'T** migrate without a clean working tree — the diff matters for review

---

## Related Files

- [modernization.md](modernization.md) - Per-version feature tour, stdlib-first migrations
- [unsafe.md](unsafe.md) - `unsafe extern`, `unsafe_op_in_unsafe_fn`, `#[unsafe(…)]` attrs
- [ownership.md](ownership.md) - RPIT capture, `use<>` precise-capture syntax
- [quality.md](quality.md) - Let chains, `#[expect(lint)]`
- [modules.md](modules.md) - Workspace inheritance, MSRV field
- [traits.md](traits.md) - Native async in traits, RPITIT

## References

- [Rust 2024 Edition Guide](https://doc.rust-lang.org/edition-guide/rust-2024/) - Canonical migration reference
- [Rust 1.85 release notes](https://blog.rust-lang.org/2025/02/20/Rust-1.85.0.html) - 2024 edition stabilization
- [RFC 3498 — RPIT lifetime capture rules 2024](https://rust-lang.github.io/rfcs/3498-lifetime-capture-rules-2024.html)
- [`use<>` precise capturing](https://doc.rust-lang.org/edition-guide/rust-2024/rpit-lifetime-capture.html)
- [Reserved syntax 2024](https://doc.rust-lang.org/edition-guide/rust-2024/reserved-syntax.html)
- [`unsafe_op_in_unsafe_fn` RFC](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html)
