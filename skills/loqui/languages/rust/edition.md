---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust 2024 Edition

Edition 2024 has been stable since Rust 1.85. The guide uses Rust 1.98.1, but the edition and compiler version remain separate settings. Crates using different editions can share a workspace.

Use the [Edition Guide](https://doc.rust-lang.org/edition-guide/rust-2024/index.html) for the full set of migration changes. The points below are especially relevant to API contracts and examples in this guide.

## Migration Order

1. Begin with a clean working tree and passing checks on the existing edition. Upgrade the toolchain if necessary.
2. While the manifest still declares the old edition, run `cargo fix --edition --workspace --all-targets`. Repeat for supported feature combinations and targets that expose different code.
3. Review the edits. The fixer changes files; it is not a preview and does not prove behavioral equivalence.
4. Change the intended crates to `edition = "2024"`. Members inheriting the edition need an update to `[workspace.package]`; members with explicit editions need individual updates. Set the intended workspace resolver explicitly.
5. Check formatting, lint, and run tests, including doctests. Inspect public API compatibility and drop-order-sensitive behavior.

Use the [routine validation commands](test.md#routine-validation) after migration.

`cargo fix --edition` covers compiler migration suggestions for the code actually compiled. It cannot audit safety comments, hidden feature combinations, external macro callers, or application invariants. Use it for edition migration, not after every ordinary edit. See [`cargo fix`](https://doc.rust-lang.org/cargo/commands/cargo-fix.html).

## Return-Position `impl Trait` Capture

Rust 2024 automatically captures all in-scope lifetime, type, and const parameters. The lifetime change applies to free and inherent functions that previously captured lifetimes only when mentioned in bounds. Types and const parameters were already captured, and other opaque-return contexts already captured lifetimes.

An additional lifetime capture can keep an argument borrowed longer than callers expect. A precise `use<...>` bound can exclude it; see the working [ownership example](ownership.md#precise-rpit-capture) and the [migration reference](https://doc.rust-lang.org/edition-guide/rust-2024/rpit-lifetime-capture.html).

Precise capture stabilized in 1.82 and works in edition 2021 too. A historical `Captures` trait is not required for modern 2021 code. List every required type and const parameter, even if the purpose is to narrow lifetime capture.

## Temporary Drop Scopes

### `if let ... else`

In edition 2024, temporaries from an `if let` scrutinee drop before entering `else` when the pattern fails. On a match, they live through the consequent block. Edition 2021 could keep them through `else`, which matters for lock guards:

```rust
use std::sync::RwLock;

let slot = RwLock::new(None::<u32>);
if let Some(value) = *slot.read().unwrap() {
    assert_eq!(value, 7);
} else {
    // In edition 2024, the failed match has released the read guard.
    *slot.write().unwrap() = Some(7);
}
assert_eq!(*slot.read().unwrap(), Some(7));
```

Review destructor effects and synchronization when migrating. An earlier drop is a behavior change, not a universal correctness guarantee. Migration lints may suggest `match` to retain the former scope. See [`if let` temporary scope](https://doc.rust-lang.org/edition-guide/rust-2024/temporary-if-let-scope.html).

### Tail Expressions

Edition 2024 can drop a block's tail-expression temporaries before local variables and before the end of the surrounding expression. If a borrowed temporary needs to survive beyond that block, bind its owner explicitly:

```rust
let text = String::from("hello");
let view = { text.as_str() };
assert_eq!(view.len(), 5);
```

Check drop order where guards or other destructors affect observable state. See [tail-expression temporary scope](https://doc.rust-lang.org/edition-guide/rust-2024/temporary-tail-expr-scope.html).

## Unsafe Declarations and Operations

Extern blocks require `unsafe`; `no_mangle`, `export_name`, and `link_section` require the unsafe attribute wrapper. `link_name` does not:

```rust,no_run
use std::ffi::{c_char, c_int};

unsafe extern "C" {
    #[link_name = "puts"]
    fn c_puts(text: *const c_char) -> c_int;
}
```

`unsafe_op_in_unsafe_fn` warns by default in edition 2024. Put unsafe operations in explicit blocks and explain why their preconditions hold. A warning is not a hard language error unless the lint is denied. The [unsafe guide](unsafe.md) covers sound boundaries, complete contracts, and the relevant attributes.

Edition 2024 also makes some formerly safe standard-library functions unsafe, including `std::env::set_var` and `remove_var`. Prefer configuring child processes with `Command::env` when that is the intended effect; do not mechanically wrap process-wide environment mutation without reviewing thread-safety obligations. See [newly unsafe functions](https://doc.rust-lang.org/edition-guide/rust-2024/newly-unsafe-functions.html).

## Macro Fragments and Match Ergonomics

The `expr` fragment in a macro defined in edition 2024 accepts top-level const blocks and underscore expressions. `expr_2021` retains the earlier matching behavior. The macro definition's edition determines this rule, including calls from other editions:

```rust
macro_rules! classify {
    ($value:expr) => { "expression" };
    (const $value:expr) => { "const-prefixed fallback" };
}

assert_eq!(classify!(const { 1 + 1 }), "expression");
assert_eq!(classify!(_), "expression");
```

This illustrates a possible change in which arm wins. Review the fixer's `expr_2021` suggestions against the macro's intended grammar. There is no `expr_2024` specifier, and this change does not make a `let` binding an ordinary expression fragment. See [macro fragment specifiers](https://doc.rust-lang.org/edition-guide/rust-2024/macro-fragment-specifiers.html).

Match ergonomics also restrict where explicit `mut`, `ref`, `ref mut`, and reference patterns can appear when a pattern relies on implicit reference matching. Let the compiler suggest a fully explicit pattern, then simplify only after checking the binding types. See [match ergonomics reservations](https://doc.rust-lang.org/edition-guide/rust-2024/match-ergonomics.html).

## Keywords and Prelude

`gen` is reserved in edition 2024. Rename an identifier or escape it as `r#gen`:

```rust
fn r#gen() -> u32 { 42 }
assert_eq!(r#gen(), 42);
```

Reservation does not stabilize generator blocks. `Future` and `IntoFuture` join the 2024 prelude, so some imports become redundant and some method calls can become ambiguous. Resolve ambiguities explicitly. Async closures and precise capture are compiler features that do not themselves require edition 2024; let chains require edition 2024 on a sufficiently new compiler.

## Workspace Settings

A virtual workspace has no root package edition from which to infer a resolver. Set `resolver = "3"` explicitly; `[workspace.package].edition` alone does not select it:

```toml
# Root Cargo.toml
[workspace]
members = ["library", "cli"]
resolver = "3"

[workspace.package]
edition = "2024"
rust-version = "1.98.1"
```

```toml
# Member Cargo.toml
[package]
name = "example-library"
version = "0.1.0"
edition.workspace = true
rust-version.workspace = true
```

Inheritance is opt-in. Resolver 3 defaults to MSRV-aware fallback, which prefers compatible dependency versions where possible; it does not guarantee that every chosen dependency or source file supports the declared MSRV. Test that compiler if older-toolchain support is promised. See [workspace configuration](modules.md).

## Related

- [Modernization](modernization.md): routine checks and stable additions
- [Ownership](ownership.md): precise capture and lifetimes
- [Macros](macros.md): macro design
- [Unsafe](unsafe.md): safety contracts
