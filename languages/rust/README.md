---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Style Guide

Language-specific patterns, anti-patterns, and best practices for writing modern Rust (target: 1.95+, 2024 edition).

**Start here:** [modernization.md](modernization.md) — run `cargo fix --edition` + `cargo clippy --fix` after every code-gen session. AI agents systematically produce pre-2024-edition idioms; the fixers handle most of it in seconds.

**If you're migrating a pre-2024 codebase:** [edition.md](edition.md) has the full 2024-edition migration playbook.

---

## Quick Reference

| Resource | When to Use |
|----------|-------------|
| [modernization.md](modernization.md) | `cargo fix`, AI-drift guidance, 1.80–1.95 feature tour, stdlib-first migration |
| [edition.md](edition.md) | Rust 2024 edition migration (RPIT capture, `unsafe extern`, `gen` reservation) |
| [ownership.md](ownership.md) | Borrowing, lifetimes, ownership transfer, RPIT capture |
| [types.md](types.md) | Newtypes, builders, `LazyLock`/`OnceLock`, collection helpers |
| [errors.md](errors.md) | `Result` types, error propagation, panics, `thiserror` vs `anyhow` |
| [traits.md](traits.md) | Trait design, native async in traits, upcasting, GATs |
| [modules.md](modules.md) | Crate structure, workspace inheritance, workspace lints, MSRV |
| [quality.md](quality.md) | Naming, let chains, `#[expect(lint)]`, documentation |
| [async-io.md](async-io.md) | Async closures, Axum 0.8, actor pattern, tokio |
| [test.md](test.md) | `cargo nextest`, `insta`, property-based, async tests |
| [unsafe.md](unsafe.md) | `unsafe_op_in_unsafe_fn`, `unsafe extern`, safety invariants |
| [macros.md](macros.md) | `cfg_select!`, declarative and procedural macros |

---

## Core Principles

### 1. Ownership is the Design
**Types encode ownership semantics. Use them to express intent.**

Borrow when you don't need ownership. Take ownership when you do. Avoid cloning as a borrow-checker escape hatch; clone deliberately when it reflects a real ownership boundary.

### 2. Parse Don't Validate
**Convert at boundaries to validated types.**

Use `FromStr`, `TryFrom`, and constructors that enforce invariants. Core logic works with guaranteed-valid types only.

### 3. Make Illegal States Unrepresentable
**Use enums and newtypes to eliminate invalid states at compile time.**

Prefer `enum { A(AData), B(BData) }` over `(Option<AData>, Option<BData>, bool)`.

### 4. Errors are Values
**Use `Result<T, E>` for expected failures. Use `panic!` for bugs.**

Never `.unwrap()` in library code for expected failures. Panic only for programming errors (invariant violations). See [errors.md](errors.md) for the full discussion.

### 5. Newtype for Type Safety
**Wrap primitives to distinguish semantically different values.**

`Miles(f64)` and `Kilometers(f64)` are different types. The compiler prevents confusion.

### 6. Traits for Composition
**No inheritance. Trait-based polymorphism only.**

Prefer generics (static dispatch) over trait objects (dynamic dispatch) unless you need heterogeneous collections.

### 7. Zero-Cost Abstractions
**Use generics by default. Trait objects only when required.**

Generic functions monomorphize to specialized code. No runtime overhead.

### 8. Explicit is Better
**Prefer explicit lifetimes in complex signatures. Name them meaningfully.**

`'input`, `'output`, `'ctx` communicate intent better than `'a`, `'b`, `'c`.

### 9. Immutable by Default
**Use `mut` only when necessary. Prefer transformations over mutation.**

Immutable data is easier to reason about and thread-safe by default.

### 10. Feature-Based Organization
**Organize crates by domain, not technical layer.**

Keep related types, traits, and functions together. Dependencies flow toward the domain core.

### 11. Modern Rust
**Target the current edition. Prefer stdlib over community crates where they overlap.**

Run `cargo fix --edition` after every toolchain bump and every significant AI-generated change. Drop `lazy_static` / `once_cell` / `cfg-if` / `fs2` — stdlib now covers them. Use native `async fn` in traits (not `#[async_trait]`) unless you need `dyn`. See [modernization.md](modernization.md).

---

## Tooling

| Tool | Purpose |
|------|---------|
| `cargo` | Build, test, run, dependency management |
| `rustfmt` | Code formatting (`cargo fmt`) |
| `clippy` | Linting (`cargo clippy`) |
| `rust-analyzer` | IDE support, type hints, refactoring |

**Clippy configuration:** Enable pedantic lints in `Cargo.toml` or `clippy.toml`:

```toml
[lints.clippy]
pedantic = "warn"
```

For public crates, consider starting with `clippy::all` and enabling pedantic lints selectively.

Nursery lints are intentionally more volatile; enable them selectively after review rather than blanket-enabling the entire group:

```toml
[lints.clippy]
pedantic = "warn"

# Example: selectively enabled nursery lints
cognitive_complexity = "warn"
option_if_let_else = "warn"
```

---

## Quick Anti-Patterns Checklist

Flag these when writing or reviewing Rust code:

**Ownership:**
- ✘ Unnecessary clone to satisfy borrow checker (restructure code; clone only when ownership is required)
- ✘ `Rc<RefCell<T>>` everywhere (usually indicates design issue)
- ✘ Overuse of `'static` lifetimes (limits API flexibility)

**Types:**
- ✘ Stringly-typed APIs (use enums and newtypes)
- ✘ `bool` parameters (use enums for clarity)
- ✘ `Option<Option<T>>` (usually wrong modeling)

**Traits:**
- ✘ `Deref` for inheritance-like polymorphism
- ✘ God traits (split into focused traits)
- ✘ Implementing `Into` directly (implement `From` instead)

**Errors:**
- ✘ `.unwrap()` for expected failures (use `Result`)
- ✘ Bare `?` at boundaries without context (use `.map_err()`, `match`, or `anyhow::Context`)
- ✘ Empty error types like `Result<T, ()>`
- ✘ Panic for recoverable errors

**Async:**
- ✘ Blocking in async context (use `spawn_blocking`)
- ✘ Missing timeouts on async I/O
- ✘ Raw `spawn` without structured concurrency
- ✘ `#[async_trait]` when native `async fn` in traits suffices (only needed for `dyn`)

**Style:**
- ✘ `#[deny(warnings)]` in library code (breaks downstream on new lints)
- ✘ `#[allow(lint)]` where `#[expect(lint, reason = "…")]` would catch stale suppressions
- ✘ Unused `pub` items (use `pub(crate)` for internal)
- ✘ Complex unsafe blocks (isolate in small modules)
- ✘ Nested `if let` pyramids when let chains (1.88+, 2024 edition) would work

**Modernization:**
- ✘ `lazy_static!` / `once_cell::sync::Lazy` (use `std::sync::LazyLock`)
- ✘ `once_cell::sync::OnceCell` (use `std::sync::OnceLock`)
- ✘ `cfg_if::cfg_if!` (use stdlib `cfg_select!` on 1.95+)
- ✘ `fs2` for file locking (use `File::lock` on 1.89+)
- ✘ `Captures<'a>` RPIT workaround (2024 edition auto-captures; use `+ use<>` to opt out)
- ✘ `extern "C" { … }` without `unsafe` prefix in 2024-edition code
- ✘ `unsafe fn` bodies that perform unsafe ops without an inner `unsafe {}` block
- ✘ Shipping without running `cargo fix --edition` + `cargo clippy --fix`

---

## Common Derives

Implement common traits eagerly:

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct UserId(String);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub struct Point { x: i32, y: i32 }
```

- `Debug`: Required for error messages and debugging
- `Clone`/`Copy`: When semantically appropriate
- `PartialEq`/`Eq`: For comparisons and hash map keys
- `Hash`: For use in `HashMap`/`HashSet`
- `Default`: When there's a sensible default value
- `Serialize`/`Deserialize`: For data interchange (with `serde`)

---

## Related

- [modernization.md](modernization.md), [edition.md](edition.md), [ownership.md](ownership.md), [types.md](types.md), [errors.md](errors.md), [traits.md](traits.md), [async-io.md](async-io.md), [modules.md](modules.md), [quality.md](quality.md), [test.md](test.md), [unsafe.md](unsafe.md), [macros.md](macros.md)
- **code-review**: Review methodology
- **code-test**: Test-driven development workflow

---

## References

- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) - Official API design guidance
- [Rust Style Guide](https://doc.rust-lang.org/stable/style-guide/) - Official style guide
- [The Rust Book](https://doc.rust-lang.org/book/) - Language reference, updated for 2024 edition
- [Rust 2024 Edition Guide](https://doc.rust-lang.org/edition-guide/rust-2024/) - Migration reference
- [Rust by Example](https://doc.rust-lang.org/rust-by-example/) - Learn through examples
- [The Rustonomicon](https://doc.rust-lang.org/nomicon/) - Unsafe Rust guide
- [Rust Design Patterns](https://rust-unofficial.github.io/patterns/) - Community patterns
- [Rust release blog](https://blog.rust-lang.org/) - Every release announcement
- [releases.rs](https://releases.rs/) - Searchable API stabilization timeline
- [`cargo fix` docs](https://doc.rust-lang.org/cargo/commands/cargo-fix.html) - Modernizer command
