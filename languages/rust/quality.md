---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Quality

Use familiar names, understandable control flow, and documentation that explains observable behavior. Let rustfmt handle routine formatting; keep lint policy aligned with the project's supported toolchain and contracts.

## Naming

| Item                                | Convention                     | Examples                             |
| ----------------------------------- | ------------------------------ | ------------------------------------ |
| Types, traits, variants             | `UpperCamelCase`               | `UserId`, `Iterator`, `Some`         |
| Functions, methods, modules, macros | `snake_case`                   | `read_file`, `as_bytes`, `my_macro!` |
| Constants and statics               | `SCREAMING_SNAKE_CASE`         | `MAX_SIZE`, `CONFIG`                 |
| Type parameters                     | Short meaningful capitals      | `T`, `E`, `Reader`                   |
| Lifetimes                           | Short or descriptive lowercase | `'a`, `'de`, `'input`                |

Treat acronyms as words: `Uuid`, `HttpRequest`. Omit `get_` from simple getters such as `name()`; indexed or fallible access can appropriately use `get()` and `get_mut()`.

### Conversion Prefixes

The [API Guidelines' naming chapter](../../resources/languages/rust/api-guidelines/src/naming.md) uses these conventions:

| Prefix  | Typical meaning                                         | Examples                            |
| ------- | ------------------------------------------------------- | ----------------------------------- |
| `as_`   | Cheap borrowed view or reference conversion             | `str::as_bytes`, `Vec::as_slice`    |
| `to_`   | Conversion preserving the source, potentially expensive | `str::to_lowercase`, `Path::to_str` |
| `into_` | Consuming conversion, with variable cost                | `String::into_bytes`                |

`to_` is not restricted to borrowed-to-owned conversion: `Path::to_str` returns an optional borrowed string, and a `Copy` value may be taken by value. Names describe the conversion contract, not a universal allocation rule.

```rust
struct Bytes(Vec<u8>);

impl Bytes {
    fn as_slice(&self) -> &[u8] { &self.0 }
    fn to_vec(&self) -> Vec<u8> { self.0.clone() }
    fn into_vec(self) -> Vec<u8> { self.0 }
}
```

Collections should support appropriate `IntoIterator` implementations and familiar `iter`/`iter_mut` methods. See [traits](traits.md#collection-traits).

## Public Documentation

Explain what the API does, its important restrictions, and a representative use. Use complete examples with imports and types; hide necessary setup with rustdoc's `#` lines when it distracts from the example. Mark intentional rejection examples `compile_fail`, and use `no_run` only when executing an otherwise compilable example would require external state.

Document expected errors, public panic conditions, and caller safety obligations in their relevant sections. A safe function must not depend on a hidden `# Safety` requirement; see [unsafe](unsafe.md).

```rust
/// Returns the first byte.
///
/// # Panics
/// Panics when `bytes` is empty.
pub fn first_byte(bytes: &[u8]) -> u8 {
    *bytes.first().expect("bytes must be nonempty")
}
```

A documented panic contract can be valid. If empty input is an expected caller case, an `Option<u8>` API may serve them better. `unwrap` is reasonable in a short usage example with known valid data; show `?` when propagation is part of the lesson. See [errors](errors.md#when-unwrapexpect-is-acceptable).

`#[doc(hidden)]` hides an item from documentation, not from the type system or downstream access. Use visibility to control the public surface.

## Control Flow

Use let chains for related conditions that read naturally together. They require Rust 1.88 and edition 2024:

```rust
let input = Some("42");
if let Some(text) = input
    && let Ok(value) = text.parse::<u32>()
    && value > 0
{
    assert_eq!(value, 42);
}
```

Nested blocks remain useful when branches have separate work or different error handling. A `while let` chain stops when any condition fails; it does not skip a failed item automatically.

Rust 1.95 also supports `if let` match guards:

```rust
fn parse_positive(input: Option<&str>) -> Option<u32> {
    match input {
        Some(text) if let Ok(value) = text.parse::<u32>() && value > 0 => Some(value),
        _ => None,
    }
}
assert_eq!(parse_positive(Some("42")), Some(42));
```

Choose iterator chains for straightforward transformations and loops when control flow, mutation, or early exits are clearer:

```rust
let numbers: [i32; 4] = [-1, 0, 2, 3];
let squares: Vec<_> = numbers.into_iter()
    .filter(|value| *value > 0)
    .map(|value| value * value)
    .collect();
assert_eq!(squares, [4, 9]);

let mut total = 0;
for value in squares {
    total += value;
}
assert_eq!(total, 13);
```

Loops are valid for transformations too, and `for_each` can deliberately express effects. Prefer clarity over a categorical imperative-versus-functional rule.

## Lint Policy

Start with default compiler and Clippy diagnostics, then select additional lints with demonstrated value. Pedantic and nursery groups may need case-by-case exceptions; a blanket group is a project choice, not a language requirement. Give lint groups lower priority when individual overrides are needed:

```toml
# Root Cargo.toml
[workspace.lints.rust]
unsafe_op_in_unsafe_fn = "deny"

[workspace.lints.clippy]
all = { level = "warn", priority = -1 }
# Optional project policy:
pedantic = { level = "warn", priority = -1 }
```

```toml
# Member Cargo.toml
[lints]
workspace = true
```

Use `#[expect(lint, reason = "...")]` for a specific diagnostic that should remain present. It warns when the expectation is unfulfilled, helping expose stale exceptions. `#[allow]` is suitable when the lint is intentionally inapplicable regardless of whether it fires under every build configuration:

```rust
#[expect(dead_code, reason = "reserved internal hook during this refactor")]
fn future_hook() {}
```

Prefer enforcing warnings in CI over embedding `#![deny(warnings)]` in a reusable library. New diagnostics can otherwise turn a source-compatible compiler upgrade into a build failure in contexts where lint capping does not apply. Cargo normally caps dependency lints; avoid claiming that every dependency consumer necessarily breaks.

On Cargo 1.97+, `CARGO_BUILD_WARNINGS=deny` provides a warning policy without the cache invalidation of changing `RUSTFLAGS`. See [modernization](modernization.md#cargo-warning-policy-197).

## Error Messages

Use lowercase wording without trailing punctuation when a message is designed to be chained, for example `failed to read configuration: permission denied`. Preserve paths, operations, and source errors where useful, while keeping credentials and other sensitive data out of diagnostics. Match the application's presentation style at the outermost boundary.

## Tooling

Use [routine validation](test.md#routine-validation) for source-preserving checks and [modernization](modernization.md#routine-checks-and-deliberate-edits) for deliberate edits. Keep edition fixes within the [edition migration procedure](edition.md).

Use `cargo info crate_name` for package metadata and feature information. Check current documentation for API and version claims, and use the pinned [source examples](resources.md) to understand contextual design choices.

## Related

- [Errors](errors.md): recoverability, context, and panic contracts
- [Modules](modules.md): public surface and workspace inheritance
- [Testing](test.md): executable documentation
- [Official Style Guide](https://doc.rust-lang.org/style-guide/)
