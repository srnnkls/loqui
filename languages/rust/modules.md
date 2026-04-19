---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Modules

Crate structure, visibility, public APIs, and organization patterns.

## Core Guidelines

### Feature-Based Organization

**Organize by domain, not technical layer.**

```
# ✓ CORRECT: Feature-based
src/
├── lib.rs
├── auth/
│   ├── mod.rs
│   ├── token.rs
│   └── session.rs
├── storage/
│   ├── mod.rs
│   ├── memory.rs
│   └── disk.rs
└── api/
    ├── mod.rs
    └── handlers.rs

# ✘ WRONG: Layer-based
src/
├── lib.rs
├── models/
│   ├── auth.rs
│   └── storage.rs
├── services/
│   ├── auth.rs
│   └── storage.rs
└── handlers/
    ├── auth.rs
    └── storage.rs
```

Related types, traits, and functions stay together.

### Use `pub(crate)` for Internal APIs

**Hide implementation details. Expose only what's needed.**

```rust
// ✓ CORRECT: Explicit visibility levels
pub struct Client {
    // Public field (rare, usually avoided)
    pub config: Config,

    // Crate-internal
    pub(crate) connection: Connection,

    // Module-private (default)
    buffer: Vec<u8>,
}

pub fn connect(url: &str) -> Result<Client, Error> {
    // Public API
}

pub(crate) fn validate_url(url: &str) -> bool {
    // Internal helper, not part of public API
}

fn parse_response(data: &[u8]) -> Response {
    // Private to this module
}
```

### Explicit Public API with Reexports

**Define your public API explicitly in `lib.rs`.**

```rust
// lib.rs
mod auth;
mod storage;
mod error;

// Public API - explicitly reexported
pub use auth::{Token, Session, authenticate};
pub use storage::{Storage, MemoryStorage, DiskStorage};
pub use error::{Error, Result};

// Internal modules not reexported - hidden from users
```

Users import from the crate root, not internal module paths.

### Future-Proof Public APIs

**Use `#[non_exhaustive]` and sealed traits to allow evolution.**

```rust
use std::time::Duration;

// ✓ CORRECT: Non-exhaustive enum allows adding variants
#[non_exhaustive]
pub enum Error {
    NotFound,
    PermissionDenied,
    // Future: can add variants without breaking downstream
}

// ✓ CORRECT: Non-exhaustive struct allows adding fields
#[non_exhaustive]
pub struct Config {
    pub timeout: Duration,
    pub retries: u32,
    // Future: can add fields without breaking downstream
}

impl Config {
    // Provide constructor since struct literals won't work externally
    pub fn new(timeout: Duration) -> Self {
        Self { timeout, retries: 3 }
    }
}

// ✓ CORRECT: Sealed trait prevents external implementations
mod private {
    pub trait Sealed {}
}

pub trait Backend: private::Sealed {
    fn execute(&self, query: &str) -> Result<(), Error>;
}

// Only types in this crate can implement Backend
pub struct PostgresBackend;
impl private::Sealed for PostgresBackend {}
impl Backend for PostgresBackend {
    fn execute(&self, _query: &str) -> Result<(), Error> { Ok(()) }
}
```

| Pattern | Use When |
|---------|----------|
| `#[non_exhaustive]` enum | Public error types, status codes, options |
| `#[non_exhaustive]` struct | Configuration, options with future expansion |
| Sealed trait | Trait where you control all implementations |

### Prefer Small, Focused Crates

**Single responsibility. Easy to understand and test.**

```toml
# ✓ CORRECT: Workspace with focused crates
[workspace]
members = [
    "core",       # Domain types and traits
    "storage",    # Storage implementations
    "api",        # HTTP API
    "cli",        # Command-line interface
]

# Each crate has clear boundaries and minimal dependencies
```

Benefits:
- Parallel compilation
- Clear dependency boundaries
- Easier to test in isolation
- Can be published separately

### Contain Unsafe in Small Modules

**Isolate unsafe code. Provide safe abstractions.**

```rust
// safe_wrapper.rs - minimal unsafe surface
mod raw {
    //! Unsafe internals - do not use directly

    pub(super) unsafe fn dangerous_operation(ptr: *mut u8) {
        // Unsafe implementation
    }
}

/// Safe wrapper around dangerous_operation.
///
/// # Panics
/// Panics if buffer is empty.
pub fn safe_operation(buffer: &mut [u8]) {
    assert!(!buffer.is_empty());
    // SAFETY: buffer is non-empty and valid
    unsafe {
        raw::dangerous_operation(buffer.as_mut_ptr());
    }
}
```

### Dependencies Flow Toward Core

**Domain core has no dependencies on infrastructure.**

```
┌─────────────────────────────────────┐
│              CLI / API              │  ← Entry points
├─────────────────────────────────────┤
│            Application              │  ← Orchestration
├─────────────────────────────────────┤
│    Storage    │    External APIs    │  ← Infrastructure
├───────────────┴─────────────────────┤
│           Domain Core               │  ← Pure types & logic
└─────────────────────────────────────┘
     Dependencies flow DOWN only
```

```rust
// domain/mod.rs - no external dependencies
pub struct Order { /* ... */ }
pub trait OrderRepository {
    fn save(&self, order: &Order) -> Result<(), Error>;
}

// storage/postgres.rs - depends on domain
use crate::domain::{Order, OrderRepository};
use sqlx::PgPool;

pub struct PostgresOrderRepository { pool: PgPool }
impl OrderRepository for PostgresOrderRepository { /* ... */ }
```

### Use Cargo Features for Optional Functionality

**Feature-gate optional dependencies and functionality.**

```toml
[package]
name = "mylib"

[features]
default = []
serde = ["dep:serde"]
async = ["dep:tokio"]
full = ["serde", "async"]

[dependencies]
serde = { version = "1.0", optional = true }
tokio = { version = "1.0", optional = true }
```

```rust
#[cfg(feature = "serde")]
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone)]
#[cfg_attr(feature = "serde", derive(Serialize, Deserialize))]
pub struct Config {
    pub name: String,
}
```

Feature naming: use the dependency name directly, not `use-serde` or `with-serde`.

### Workspace Inheritance (Rust 1.64+)

**Centralize `version`, `edition`, `license`, `rust-version`, and dependencies at the workspace root** — members inherit with `.workspace = true`.

```toml
# Cargo.toml at workspace root
[workspace]
members = ["core", "api", "cli"]

[workspace.package]
version = "0.3.0"
edition = "2024"
license = "MIT"
rust-version = "1.85"
authors = ["Your Name"]

[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
tokio = { version = "1", features = ["full"] }
thiserror = "2"

# Member Cargo.toml
[package]
name = "core"
version.workspace = true
edition.workspace = true
license.workspace = true
rust-version.workspace = true

[dependencies]
serde.workspace = true
thiserror.workspace = true
```

One place to bump versions. One place to set `edition = "2024"`. No drift.

### Workspace Lints (Rust 1.74+)

**Declare lints once at the workspace root; members opt in with `lints.workspace = true`.**

```toml
# Cargo.toml at workspace root
[workspace.lints.clippy]
pedantic = "warn"
unwrap_used = "warn"
expect_used = "warn"

[workspace.lints.rust]
unsafe_op_in_unsafe_fn = "deny"
missing_docs = "warn"

# Member Cargo.toml
[lints]
workspace = true
```

Prefer this over per-crate `#![warn(…)]` attributes — it's declarative, enforced by Cargo, and versioned with your repo.

### MSRV Declaration and Resolver (Rust 1.84+)

**Declare `rust-version` to get MSRV-aware dependency resolution.** Cargo 1.84+ prefers dependency versions whose own MSRV is compatible with yours, avoiding surprise breakage from a transitive dep bump.

```toml
[package]
rust-version = "1.85"
```

Pair with `cargo msrv verify` (from the `cargo-msrv` crate) in CI if you want to enforce the declaration against actual source compatibility.

### Edition Field

**Set `edition = "2024"` on every new crate.** For existing crates, run `cargo fix --edition` and flip the field — see [edition.md](edition.md) for the full playbook.

```toml
[package]
edition = "2024"
```

Mixed-edition workspaces are fully supported — migrate crate-by-crate. Declare the new default at the workspace root so new members pick up 2024 automatically.

### Module File Patterns

**Avoid unnecessary nesting. Both `foo.rs` and `foo/mod.rs` are valid.**

```
# ✓ PREFERRED: Flat files for leaf modules
src/
├── lib.rs
├── auth.rs        # Simple module
├── storage.rs     # Simple module
└── api/           # Directory only because it has submodules
    ├── mod.rs
    ├── handlers.rs
    └── middleware.rs

# ✓ ALSO OK: Directory style (team preference)
src/
├── lib.rs
├── auth/
│   └── mod.rs     # Acceptable if team prefers consistency
└── api/
    ├── mod.rs
    ├── handlers.rs
    └── middleware.rs
```

The goal is avoiding unnecessary depth, not enforcing a specific style. Pick one approach per project and stay consistent. Don't bikeshed layout—focus on logical organization.

## Summary

- **NEVER** organize by technical layer (models/, services/, handlers/)
- **NEVER** expose internal implementation details as public API
- **DO** organize by feature/domain
- **DO** use `pub(crate)` for internal APIs
- **DO** reexport public API from crate root
- **DO** use `#[non_exhaustive]` for public enums/structs that may grow
- **DO** use sealed traits when you must control implementations
- **DO** prefer small, focused crates in workspaces
- **DO** use `[workspace.package]` + `.workspace = true` to centralize version/edition/license/MSRV
- **DO** use `[workspace.lints]` + `lints.workspace = true` to centralize lint policy
- **DO** declare `rust-version` — the MSRV-aware resolver (1.84+) prevents transitive breakage
- **DO** set `edition = "2024"` on all new crates
- **DO** contain unsafe in minimal modules with safe wrappers
- **DO** use Cargo features for optional functionality
- **DON'T** create deeply nested module hierarchies
- **DON'T** duplicate lint configuration across workspace members

---

## Related

- [traits.md](traits.md) - Trait visibility and extension patterns
- [unsafe.md](unsafe.md) - Containing unsafe code
- [quality.md](quality.md) - Documentation for modules

## References

- [Rust API Guidelines: Documentation](https://rust-lang.github.io/api-guidelines/documentation.html)
- [Rust Design Patterns: Small Crates](https://rust-unofficial.github.io/patterns/patterns/structural/small-crates.html)
- [Cargo Book: Features](https://doc.rust-lang.org/cargo/reference/features.html)
- [Cargo Book: Workspaces](https://doc.rust-lang.org/cargo/reference/workspaces.html) - Inheritance syntax
- [Cargo Book: Lints configuration](https://doc.rust-lang.org/cargo/reference/manifest.html#the-lints-section) - `[lints]` and `[workspace.lints]`
- [MSRV-aware resolver RFC](https://rust-lang.github.io/rfcs/3537-msrv-resolver.html)
