---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Modules

Organize code around responsibilities and dependency boundaries. Prefer a small public interface and keep implementation details private. Domain-oriented modules often help, while technical modules such as parsers, storage engines, or protocol adapters can also be coherent boundaries.

## Modules and Crates

Keep related types and operations together. Use a separate crate when it provides a meaningful dependency, reuse, publication, or build boundary; avoid splitting solely to hit an arbitrary size limit.

[ripgrep's crates](../../resources/languages/rust/ripgrep/crates) separate matching, searching, printing, and directory traversal. Those are distinct responsibilities within one tool, not a rule that every application should copy the same layout.

Both `foo.rs` with a `foo/` directory and `foo/mod.rs` are valid module layouts. Keep the local convention consistent and avoid unnecessary nesting. A small crate can remain mostly in `lib.rs` until its responsibilities justify splitting.

## Visibility and Public API

Default to private items. Use `pub(super)` or `pub(crate)` for intended internal access, and re-export selected public types from a convenient entry point:

```rust
mod identifiers {
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct UserId(pub u64);
}

pub use identifiers::UserId;
```

A private module can contain a re-exported public item. Conversely, `#[doc(hidden)]` only hides documentation; it does not make a public item private or exempt it from compatibility obligations. Exported macro helpers sometimes need public visibility, so design that support surface deliberately.

Use `#[non_exhaustive]` when callers should allow future variants or fields. It has concrete construction and matching consequences outside the crate:

```rust
#[non_exhaustive]
pub enum ConnectionError {
    Closed,
    TimedOut,
}
```

Downstream matches need a wildcard arm. A non-exhaustive struct cannot be constructed with a struct literal outside its defining crate, so provide constructors as needed. Sealed traits are another targeted evolution tool; see [traits](traits.md#sealing-and-evolution).

## Workspace Inheritance

Declare shared package metadata, dependencies, and lints at the root. A virtual workspace needs an explicit resolver; edition inheritance does not choose one:

```toml
# Root Cargo.toml: a virtual workspace, with no [package].
[workspace]
members = ["library", "cli"]
resolver = "3"

[workspace.package]
version = "0.1.0"
edition = "2024"
rust-version = "1.98.1"
license = "MIT"

[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
thiserror = "2"

[workspace.lints.rust]
unsafe_op_in_unsafe_fn = "deny"

[workspace.lints.clippy]
all = { level = "warn", priority = -1 }
```

Each member opts into the settings it inherits:

```toml
# library/Cargo.toml
[package]
name = "example-library"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
license.workspace = true

[dependencies]
serde.workspace = true
thiserror.workspace = true

[lints]
workspace = true
```

Workspace dependency declarations do not add a dependency to every member. Likewise, metadata and lints are not inherited automatically. Cargo features are additive, so inspect the resolved feature graph when one member enables more capabilities for a shared dependency. See [Cargo workspaces](https://doc.rust-lang.org/cargo/reference/workspaces.html).

## MSRV and Resolver Behavior

`rust-version` declares the compiler version a package supports; it neither selects that compiler nor proves source compatibility. Use a separate toolchain pin for reproducible development and test the MSRV if promising support for it.

Resolver 3 defaults `resolver.incompatible-rust-versions` to `fallback`, preferring dependency versions with compatible declared requirements where possible. Cargo can still choose an incompatible version when no suitable candidate satisfies resolution, and incomplete dependency metadata or feature-specific requirements can defeat the intended compatibility. A checked-in lockfile also needs validation on the supported compiler. See the [resolver reference](https://doc.rust-lang.org/cargo/reference/resolver.html#rust-version).

For an existing crate, retain its supported minimum until intentionally changing that contract. For new code following this guide, Rust 1.98.1 is the development baseline. Mixed-edition and mixed-MSRV workspaces are possible, but their shared dependency graph needs explicit checks.

## Features and Dependency Boundaries

Use features for optional capabilities and optional dependencies. Prefer additive behavior so dependencies can combine feature sets:

```toml
[package]
name = "optional-data-format"
version = "0.1.0"
edition = "2024"

[features]
default = []
serde = ["dep:serde"]

[dependencies]
serde = { version = "1", features = ["derive"], optional = true }
```

```rust
#[derive(Debug, Clone)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Config {
    pub name: String,
}
```

Check the default build, supported minimal configurations, and relevant combinations. `--all-features` is useful only when that combined configuration is supported. Use `cargo tree -e features` to inspect activation and `cargo tree -i dependency_name` to inspect reverse dependencies.

Keep core behavior independent of infrastructure when doing so improves testability and reuse. Avoid introducing a trait for every dependency merely to enforce a diagram; model the abstractions the domain actually needs.

## Unsafe Internals

Keep unsafe machinery behind a small safe interface whose constructors and operations preserve the invariant. Module privacy reduces the code that must maintain that invariant; it is not a substitute for a proof. [redb's source](../../resources/languages/rust/redb/src) separates public typed tables and transactions from storage internals, while guards and lifetimes connect the two. See [unsafe](unsafe.md) for complete boundary examples.

## Validation

Inspect the workspace with `cargo metadata --no-deps --format-version 1`, then run the [routine validation commands](test.md#routine-validation) for its supported feature, platform, and compiler matrix.

## Related

- [Edition 2024](edition.md): migration order and workspace settings
- [Quality](quality.md): lint policy and documentation
- [Macros](macros.md): exported helpers and hygiene
- [Source catalog](resources.md): examples and provenance
