---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Style Guide

Practical guidance for Rust 1.98.1 and edition 2024, checked against the stable toolchain available on 2026-09-13. Projects supporting older compilers should keep their own minimum supported Rust version (MSRV) and check the stabilization versions in [modernization](modernization.md).

Start with the topic relevant to the change. For an edition upgrade, use the [migration procedure](edition.md); routine development uses read-only checks, not automatic edition fixes.

## Topics

| Guide                                          | Use it for                                                              |
| ---------------------------------------------- | ----------------------------------------------------------------------- |
| [Ownership](ownership.md)                      | Borrowed views, ownership transfer, cloning, lifetimes, precise capture |
| [Types](types.md)                              | Newtypes, invariants, builders, collections, lazy initialization        |
| [Errors](errors.md)                            | Recoverable failures, error contracts, context, panics                  |
| [Traits](traits.md)                            | Dispatch, conversions, GATs, async `Send` and dynamic dispatch          |
| [Modules](modules.md)                          | Crate boundaries, workspace inheritance, resolver and MSRV              |
| [Quality](quality.md)                          | Naming, control flow, lint policy, public documentation                 |
| [Async I/O](async-io.md)                       | Blocking work, task lifetimes, cancellation, channels, async closures   |
| [Testing](test.md)                             | Unit, integration, property, snapshot, async, and documentation tests   |
| [Unsafe](unsafe.md)                            | Safe boundaries, pointer validity, invariants, FFI                      |
| [Macros](macros.md)                            | Declarative and procedural macros, conditional compilation              |
| [Edition 2024](edition.md)                     | Edition migration and behavior changes                                  |
| [Modernization](modernization.md)              | Stable additions, dependency migration, dated 2027 watchlist            |
| [References and source examples](resources.md) | Vendored Rust Book, API guidance, ripgrep, redb, Tokio, Serde           |

## Design Principles

### Express the Ownership Contract

Borrow for temporary access and take ownership when retaining or consuming. Prefer flexible borrowed views such as `&str` and `&[T]`. Avoid unconditional hidden copies, while allowing internal allocation on a cache miss and cloning for repeatable builders or independent owners.

Use field-level borrowing before changing the type structure. Choose `take` or `replace` only when the replacement state is intended. Return owned inputs on failure when useful recovery is part of the contract.

### Encode Useful Invariants

Use enums and newtypes where they prevent meaningful mistakes. Parse at boundaries, then preserve the invariant through constructors and mutation APIs. A newtype's default layout is not an ABI promise; use an explicit representation when interoperability needs one.

Named boolean builder switches can be clear. Nested options can represent distinct states, such as an omitted patch field versus an explicit removal. Prefer the representation that makes those states understandable.

### Make Failure and Concurrency Contracts Explicit

Use `Result` for expected failures. An invariant-backed `expect` can be appropriate; document public panic conditions. Recovering inputs and adding context should help the caller act on the failure.

Choose task ownership, cancellation, deadlines, and shutdown behavior together. Native async trait methods do not automatically promise a `Send` future. A trait's `Send` bound and dynamic-dispatch support are separate decisions.

### Choose Abstractions for the Use Case

Generics support specialization and inlining; dynamic dispatch can simplify interfaces, support runtime choice, and reduce monomorphization. `&dyn Trait` does not require heap allocation. Measure performance claims instead of treating either approach as universally faster.

Use `Rc` or `Arc` for real shared ownership. Localized interior mutability is legitimate. An immutable binding alone does not make its type thread-safe: `Send` and `Sync` describe the relevant guarantees.

### Keep Language Rules Separate from Preferences

Let rustfmt handle formatting. Use lifetimes to express relationships, with descriptive names when they clarify several sources. Keep unsafe operations small and justify their preconditions; comments cannot impose hidden safety obligations on callers of a safe function.

Prefer standard-library APIs when their behavior matches the requirement. Before replacing a crate, compare errors, blocking behavior, platform support, initialization, and ownership contracts. Treat proposed 2027 features as a watchlist until stabilized.

## Routine Validation

Use the commands in [routine validation](test.md#routine-validation), including the separate doctest run. For deliberate source edits, follow [modernization](modernization.md#routine-checks-and-deliberate-edits); for an edition change, follow the [migration order](edition.md#migration-order).

## Review Prompts

- Do parameters communicate temporary access, consumption, or shared ownership?
- Does a clone represent independent values, or could a shorter borrow or transfer suffice?
- Does an API refactor preserve replacement, retry, cancellation, and error behavior?
- Are future `Send` requirements and task lifetimes visible in trait contracts?
- Can safe callers violate any invariant used by unsafe code?
- Do workspace members inherit the intended edition, MSRV, dependencies, and lints?
- Are examples complete, intentional failures marked, and doctests included in validation?
- Are version and performance claims backed by a current contract or measurement?

## Sources

Use the [Rust Reference](https://doc.rust-lang.org/reference/) and [standard library documentation](https://doc.rust-lang.org/std/) for language and library contracts, the [Edition Guide](https://doc.rust-lang.org/edition-guide/) for migrations, and the [official Style Guide](https://doc.rust-lang.org/style-guide/) for formatting. The [source catalog](resources.md) records the role and provenance of local references and mature codebases. Their examples inform design choices; they are not universal rules.
