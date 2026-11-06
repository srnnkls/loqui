---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Modernization

This guide targets Rust 1.98.1 and edition 2024 as of 2026-09-13. Use released features when they simplify the actual contract; keep proposed changes separate from stable recommendations. Rust 1.98.1 fixes a vtable-generation miscompilation in 1.98.0, so use the patch release for this baseline. [Release announcement](https://blog.rust-lang.org/2026/09/03/Rust-1.98.1/)

## Routine Checks and Deliberate Edits

Use the [routine validation commands](test.md#routine-validation) to check code without rewriting source files, including documentation tests and the project's supported build configurations.

When automatic fixes are useful, apply them deliberately from a clean working tree:

```bash
cargo clippy --fix --workspace --all-targets
cargo fmt --all
git diff
```

These commands modify files. Review their changes and rerun the relevant checks; machine-applicable suggestions are not a proof of unchanged behavior. Piping their output or passing `--allow-dirty` does not turn them into a preview. `cargo fix --edition` belongs specifically to [edition migration](edition.md): run it while the old edition is still declared, then update the manifest. See the [Cargo command](https://doc.rust-lang.org/cargo/commands/cargo-fix.html) and [Clippy's automatic-fix documentation](https://doc.rust-lang.org/clippy/usage.html).

Generated and handwritten code need the same review of compiler support and semantics. An older idiom or dependency is not itself evidence of a defect.

## Toolchain, Edition, and MSRV

A project can pin a reproducible development toolchain:

```toml
# rust-toolchain.toml
[toolchain]
channel = "1.98.1"
profile = "minimal"
components = ["clippy", "rustfmt"]
```

Keep `edition` and `rust-version` explicit in Cargo manifests. Using the latest compiler for development does not automatically raise a library's promised MSRV. If supporting older compilers, run checks on that minimum as well and verify the dependency graph. Virtual workspaces need an explicit resolver; `rust-version` alone does not guarantee compatible resolution. See [modules](modules.md).

## Standard-Library Alternatives

Compare semantics before removing a dependency. These are candidate replacements, not automatic migrations:

| Existing use                                                 | Standard option                           | Stable since | Contract to compare                                                 |
| ------------------------------------------------------------ | ----------------------------------------- | ------------ | ------------------------------------------------------------------- |
| Lazy shared initialization                                   | `std::sync::LazyLock`                     | 1.80         | Initialization, poisoning, required methods, MSRV                   |
| Write-once shared storage                                    | `std::sync::OnceLock`                     | 1.70         | Fallible initialization and retry behavior                          |
| Local lazy or write-once storage                             | `LazyCell` / `OnceCell` in `std::cell`    | 1.80 / 1.70  | Single-threaded access and API coverage                             |
| `cfg-if` branches                                            | `cfg_select!`                             | 1.95         | First matching branch and supported compiler                        |
| Blocking exclusive file lock                                 | `File::lock`                              | 1.89         | Blocking, platform, descriptor, and error semantics                 |
| Nonblocking exclusive lock such as `fs2::try_lock_exclusive` | `File::try_lock`                          | 1.89         | Contention stays nonblocking; map error variants deliberately       |
| OS pipe wrapper                                              | `std::io::pipe`                           | 1.87         | Handles, platform support, blocking behavior                        |
| Historical RPIT `Captures` bound                             | `use<...>`                                | 1.82         | Required generic parameters and permitted lifetime capture          |
| Boxed async trait method                                     | Native async / RPIT in traits             | 1.75         | Future `Send`, receiver lifetimes, dyn compatibility, API stability |
| Decimal integer buffer formatting                            | `format_into` with `core::fmt::NumBuffer` | 1.98         | Supported format, buffer lifetime, measured performance             |

For locking in particular, changing `try_lock` to `lock` changes contention into waiting. It is not a style-only substitution. Consult [`File`'s locking contracts](https://doc.rust-lang.org/std/fs/struct.File.html#method.try_lock).

Randomness is also an algorithm and seeding contract, not a blanket distinction between crate names. The `rand` ecosystem includes cryptographically suitable and unsuitable generators. For security-sensitive use, follow the selected implementation's `CryptoRng`, entropy, and reseeding requirements and the consuming cryptographic library's guidance. See the project's [cryptographic RNG guidance](https://rust-random.github.io/book/guide-rngs.html).

## Stable Features Worth Knowing

### Collection Operations

```rust
use std::collections::HashMap;

// 1.86: the predicate receives &mut T.
let mut values = vec![1, 2, 3, 4];
assert_eq!(values.pop_if(|value| *value > 3), Some(4));

// 1.87: extract matching Vec elements in the requested range.
let evens: Vec<_> = values.extract_if(.., |value| *value % 2 == 0).collect();
assert_eq!(evens, [2]);
assert_eq!(values, [1, 3]);

// 1.88: HashMap extraction has its own stabilization version.
let mut counts = HashMap::from([("a", 1), ("b", 2)]);
let removed: Vec<_> = counts.extract_if(|_, value| *value == 1).collect();
assert_eq!(removed, [("a", 1)]);

// 1.94: each window is a borrowed fixed-size array.
for window in [1, 2, 3, 4].array_windows::<3>() {
    let _: &[i32; 3] = window;
}
```

Extraction iterators are lazy: unvisited elements remain when the iterator is dropped early. `array_windows` yields `&[T; N]`, so elements need not be `Copy`. See [collection guidance](types.md#collection-helpers) and the standard-library method contracts.

### Control Flow and Conditional Compilation

Let chains require edition 2024 and Rust 1.88. Async closures stabilized in 1.85, while `if let` match guards and `cfg_select!` arrived in 1.95:

```rust
let input = Some("42");
let parsed = match input {
    Some(text) if let Ok(value) = text.parse::<u32>() => Some(value),
    _ => None,
};
assert_eq!(parsed, Some(42));

cfg_select! {
    unix => { const PLATFORM: &str = "unix"; }
    windows => { const PLATFORM: &str = "windows"; }
    _ => { const PLATFORM: &str = "other"; }
}
assert!(!PLATFORM.is_empty());
```

Use these where they improve clarity; nested control flow can still be appropriate. An async retry callback returning `Result<T, E>` needs that result type in its bound. See [async closures](async-io.md#async-closures-and-retries) and the [1.95 release notes](https://blog.rust-lang.org/2026/04/16/Rust-1.95.0/).

### Range Values and Pattern Assertions (1.96)

New `core::range` types separate the range value from its iterator. They can be `Copy` when their fields are, while range syntax still constructs the legacy `core::ops` types. Consider `RangeBounds` when an API should accept both. The pattern-assertion macros require an explicit import; they are not in the prelude. [1.96 release notes](https://blog.rust-lang.org/2026/05/28/Rust-1.96.0/)

```rust
use core::{assert_matches, range::Range};

let range = Range { start: 1, end: 4 };
let saved = range;
assert_eq!(range.into_iter().sum::<i32>(), 6);
assert_eq!(saved.start, 1);
assert_matches!(Some(42), Some(value) if value > 0);
```

### Cargo Warning Policy (1.97)

Cargo can deny warnings without invalidating the build cache by changing `RUSTFLAGS`:

```bash
CARGO_BUILD_WARNINGS=deny cargo check --workspace --all-targets --keep-going
```

Treat this as a CI policy, separate from source-level lint selection. Keep documentation tests and Clippy in the relevant validation jobs. [1.97 release notes](https://blog.rust-lang.org/2026/07/09/Rust-1.97.0/)

### Integer Formatting and Floating-Point Contracts (1.98)

Use a reusable buffer when decimal integer formatting should avoid an owned string:

```rust
use core::fmt::NumBuffer;

let mut buffer = NumBuffer::new();
let text = 1234_u64.format_into(&mut buffer);
assert_eq!(text, "1234");
```

The returned string borrows the buffer. This is a focused alternative to formatting into a `String`, not a replacement for all formatting features.

The algebraic floating-point methods permit optimizations such as reassociation that ordinary operators do not promise. Results can be nondeterministic. Use them only when that numerical contract is acceptable and measurements justify the choice. [1.98 release notes](https://blog.rust-lang.org/2026/08/20/Rust-1.98.0/)

## 2027 Watchlist

Status checked on 2026-09-13. These project goals and nightly developments are planning evidence, not stable release commitments. The suggested responses below are design recommendations inferred from that evidence.

| Area                                                          | Current evidence                                                                                                              | How to prepare                                                                                                                                 |
| ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Conditional borrowing                                         | [Polonius alpha enabled on nightly in August 2026](https://blog.rust-lang.org/2026/08/04/enabling-polonius-alpha-on-nightly/) | Revisit workarounds after stabilization. Ordinary disjoint-field borrowing already works on stable.                                            |
| Trait solving                                                 | [Next solver enabled on nightly in August 2026](https://blog.rust-lang.org/2026/08/21/enabling-next-solver-on-nightly/)       | Check difficult cases on a dated nightly separately from supported stable compilers. Solver progress does not stabilize every related feature. |
| Async trait objects, return-type notation, named opaque types | [Async roadmap](https://goals.rust-lang.org/2026/roadmap-just-add-async.html)                                                 | Preserve explicit `Send`, lifetime, allocation, and dispatch contracts until a stable alternative meets them.                                  |
| View types and richer borrowing                               | [Borrow-checker roadmap](https://goals.rust-lang.org/2026/roadmap-borrow-checker-within.html)                                 | Keep narrower field access in current APIs; do not teach proposed method-view syntax as stable.                                                |
| Pointer projection and in-place initialization                | [Reference and pointer roadmap](https://goals.rust-lang.org/2026/roadmap-beyond-the-ampersand.html)                           | Retain today's validity proofs and safe initialization options; reassess when APIs and contracts stabilize.                                    |
| Guaranteed destruction and cancellation                       | [`Move` goal](https://goals.rust-lang.org/2026/move-trait.html)                                                               | Document present cancellation and cleanup behavior. Ordinary `Drop` does not promise async cleanup or universal destruction.                   |
| Const traits, ADT const parameters, reflection                | [Const roadmap](https://goals.rust-lang.org/2026/roadmap-constify-all-the-things.html)                                        | Keep experiments separate; do not mandate replacing procedural macros based on proposed capabilities.                                          |
| Edition-dependent library evolution                           | [Library API evolution goal](https://goals.rust-lang.org/2026/library-api-evolution.html)                                     | Follow range and migration design, without treating illustrative 2027 syntax as a supported edition.                                           |

Keep stable examples compilable with the declared toolchain. Give experiments a separate compiler version, feature flags, and status; do not publish `edition = "2027"` or generator syntax as current production guidance.

## Related

- [Edition migration](edition.md)
- [Traits](traits.md) and [async I/O](async-io.md)
- [Workspace and MSRV configuration](modules.md)
- [Pinned reference sources](resources.md)
