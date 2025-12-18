# Rust Style Guide

Language-specific patterns, anti-patterns, and best practices for writing Rust code.

---

## Quick Reference

| Resource | When to Use |
|----------|-------------|
| [ownership.md](ownership.md) | Borrowing, lifetimes, ownership transfer |
| [types.md](types.md) | Newtypes, builders, discriminated unions |
| [errors.md](errors.md) | Result types, error propagation, panics |
| [traits.md](traits.md) | Trait design, composition, generics vs trait objects |
| [modules.md](modules.md) | Crate structure, visibility, public APIs |
| [quality.md](quality.md) | Naming, documentation, anti-patterns |
| [async-io.md](async-io.md) | Async/await, tokio, timeouts, concurrency |
| [test.md](test.md) | Testing patterns and practices |
| [unsafe.md](unsafe.md) | Unsafe code guidelines, safety invariants |
| [macros.md](macros.md) | Declarative and procedural macros |

---

## Core Principles

### 1. Ownership is the Design
**Types encode ownership semantics. Use them to express intent.**

Borrow when you don't need ownership. Take ownership when you do. Never clone to satisfy the borrow checker.

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

---

## Quick Anti-Patterns Checklist

Flag these when writing or reviewing Rust code:

**Ownership:**
- ✘ Clone to satisfy borrow checker (restructure code instead)
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
- ✘ Bare `?` without context (use `.map_err()` or `match`)
- ✘ Empty error types like `Result<T, ()>`
- ✘ Panic for recoverable errors

**Async:**
- ✘ Blocking in async context (use `spawn_blocking`)
- ✘ Missing timeouts on async I/O
- ✘ Raw `spawn` without structured concurrency

**Style:**
- ✘ `#[deny(warnings)]` in library code (breaks downstream on new lints)
- ✘ Unused `pub` items (use `pub(crate)` for internal)
- ✘ Complex unsafe blocks (isolate in small modules)

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

- [ownership.md](ownership.md), [types.md](types.md), [errors.md](errors.md), etc.
- **code-review**: Review methodology
- **code-test**: Test-driven development workflow

---

## References

- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) - Official API design guidance
- [Rust Style Guide](https://doc.rust-lang.org/stable/style-guide/) - Official style guide
- [The Rust Book](https://doc.rust-lang.org/book/) - Language reference
- [Rust by Example](https://doc.rust-lang.org/rust-by-example/) - Learn through examples
- [The Rustonomicon](https://doc.rust-lang.org/nomicon/) - Unsafe Rust guide
- [Rust Design Patterns](https://rust-unofficial.github.io/patterns/) - Community patterns
