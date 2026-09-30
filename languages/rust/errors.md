---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Errors

Use `Result<T, E>` for expected failures and expose enough information for callers to decide what to do. Use `Option<T>` when absence is the entire contract. Treat panic conditions, recovery, and partial effects as parts of the API.

## Expected Failures and Context

User input, file access, and network operations can fail during normal use. Propagate those failures rather than turning them into unexplained panics. Add context where it identifies the failed operation or resource; bare `?` is appropriate when the error already carries the needed information.

```rust
use std::{num::ParseIntError, path::{Path, PathBuf}};
use thiserror::Error;

#[derive(Debug, Error)]
enum LoadError {
    #[error("failed to read {path:?}: {source}")]
    Read { path: PathBuf, source: std::io::Error },
    #[error("invalid count in {path:?}: {source}")]
    Parse { path: PathBuf, source: ParseIntError },
}

fn load_count(path: &Path) -> Result<u32, LoadError> {
    let text = std::fs::read_to_string(path).map_err(|source| LoadError::Read {
        path: path.to_owned(), source,
    })?;
    text.trim().parse().map_err(|source| LoadError::Parse {
        path: path.to_owned(), source,
    })
}
```

`thiserror` exposes a field named `source` through the standard error chain. Use `match` when variants need different handling, and avoid flattening useful typed information into a string before the caller has made that choice.

Do not include secrets merely to provide context. Keep message wording compatible with the outer reporting layer so source errors are not printed twice when that layer also walks the chain.

## Choose Error Types by Caller Needs

| Caller need                              | Suitable approach                                                       |
| ---------------------------------------- | ----------------------------------------------------------------------- |
| Match on recovery cases                  | A typed error, implemented manually or with `thiserror`                 |
| Report an operation failure with context | An opaque report such as `anyhow::Error` can suffice                    |
| Represent one named failure              | A small named error type may be clearer than an enum                    |
| Distinguish no failure details           | Consider whether `Option` or a predicate better describes the operation |

Libraries commonly expose typed errors and application entry points commonly collect reports, but the target type alone does not decide the contract. Public errors usually benefit from `Debug`, `Display`, and `std::error::Error`; avoid `Result<T, ()>` when it deprives callers of useful information.

```rust
use anyhow::{Context, Result};
use std::path::Path;

fn read_settings(path: &Path) -> Result<String> {
    std::fs::read_to_string(path)
        .with_context(|| format!("failed to read settings from {}", path.display()))
}
```

`anyhow` still permits downcasting, but callers depending on specific variants are generally better served by an explicit typed API. See [`thiserror`](https://docs.rs/thiserror/) and [`anyhow`](https://docs.rs/anyhow/).

## Recovery and Partial Effects

Consider returning an owned input on failure if it remains available and callers can reuse it. [Tokio's channel errors](../../resources/languages/rust/tokio/tokio/src/sync/mpsc/error.rs) preserve unsent values; `String::from_utf8` preserves invalid bytes:

```rust
let bytes = vec![0xff];
let error = String::from_utf8(bytes).unwrap_err();
assert_eq!(error.into_bytes(), [0xff]);
```

This is useful recovery, not a universal rule. Partial consumption, mutation, error size, or sensitive contents can make retaining the input inappropriate. A retry also needs to account for operations that may already have taken effect.

[redb's `WriteTransaction::commit(self)`](../../resources/languages/rust/redb/src/transactions.rs) consumes the transaction. Its documented commit failures distinguish a poisoned transaction from other failures where changes may already have become durable. An error alone does not imply rollback or make blind retry safe. Read the specific operation's contract before deciding whether it should return its input or be retried.

For async APIs, cancellation may differ from a returned error: a canceled send future can drop its message, and canceled I/O can leave partial progress. See [async I/O](async-io.md#deadlines-and-cancellation).

## When `unwrap`/`expect` is Acceptable

An invariant-backed panic can be appropriate in library code. Prefer `expect` when its message explains why failure would indicate a bug:

```rust
use std::collections::HashMap;

let mut values = HashMap::new();
values.insert("answer", 42);
let answer = values.get("answer").expect("the key was inserted above");
assert_eq!(*answer, 42);
```

Other common uses include assertions in tests, known-valid documentation examples, and short local scripts where terminating is the intended failure policy. A literal regex is still checked at runtime by `Regex::new`; its being a literal is an invariant to test, not compile-time validation by that API.

A public panic condition should be documented. Do not classify ordinary malformed input as a programming bug merely to avoid returning an error. The [Rust Book's panic guidance](../../resources/languages/rust/rust-book/src/ch09-03-to-panic-or-not-to-panic.md) distinguishes recoverable failures, examples, and invariant assumptions.

Unwinding is not guaranteed in every build; `panic = "abort"` changes that behavior. `catch_unwind` cannot recover from aborting panics, and `AssertUnwindSafe` does not itself catch anything.

## Document Errors, Panics, and Safety

Explain observable failure behavior, including whether an operation has changed state when it returns an error:

```rust
/// Parses an unsigned decimal count.
///
/// # Errors
/// Returns a parse error for invalid syntax or values outside u32's range.
pub fn parse_count(text: &str) -> Result<u32, std::num::ParseIntError> {
    text.parse()
}

assert_eq!(parse_count("42").unwrap(), 42);
assert!(parse_count("-1").is_err());
```

Use `# Panics` for public panic conditions and `# Safety` for unsafe caller obligations. Keep the implementation's unsafe operations in explicit blocks; see [unsafe](unsafe.md). A safety section cannot make hidden obligations acceptable on a safe function.

## Validate Once, Preserve the Invariant

Validated types can move repeated checks to a boundary, provided their constructors, mutation methods, and deserialization preserve the invariant. Prefer that to adding unchecked APIs by default.

An `_unchecked` API is justified only when its omitted checks and safety or logical obligations are precise, and a real use case needs it. If safe callers could cause undefined behavior by violating the precondition, the function must be unsafe. A `debug_assert!` is a diagnostic aid, not a release-mode proof. Measure before increasing the unsafe surface for performance.

## Diagnostic Quality

Use actionable messages, usually lowercase without trailing punctuation when chaining. Where a blanket implementation produces misleading compiler suggestions, `#[diagnostic::do_not_recommend]` can suppress recommendations involving that implementation; it does not change trait resolution:

```rust
trait Internal {}
trait Public {}

#[diagnostic::do_not_recommend]
impl<T: Internal> Public for T {}
```

## Related

- [Ownership](ownership.md): recoverable inputs and transfer semantics
- [Types](types.md): validated values
- [Async I/O](async-io.md): cancellation and retry policy
- [API Guidelines: error types](../../resources/languages/rust/api-guidelines/src/interoperability.md)
- [Source catalog](resources.md): Tokio and redb contracts
