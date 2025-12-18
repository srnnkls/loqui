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

### Module File Patterns

**Prefer `module.rs` over `module/mod.rs` for leaf modules.**

```
# ✓ PREFERRED: Flat files for simple modules
src/
├── lib.rs
├── auth.rs        # Simple module
├── storage.rs     # Simple module
└── api/           # Complex module with submodules
    ├── mod.rs
    ├── handlers.rs
    └── middleware.rs

# ✘ AVOID: mod.rs for everything
src/
├── lib.rs
├── auth/
│   └── mod.rs     # Unnecessary nesting
└── storage/
    └── mod.rs     # Unnecessary nesting
```

Use directories only when a module has submodules.

## Summary

- **NEVER** organize by technical layer (models/, services/, handlers/)
- **NEVER** expose internal implementation details as public API
- **DO** organize by feature/domain
- **DO** use `pub(crate)` for internal APIs
- **DO** reexport public API from crate root
- **DO** prefer small, focused crates in workspaces
- **DO** contain unsafe in minimal modules with safe wrappers
- **DO** use Cargo features for optional functionality
- **DON'T** create deeply nested module hierarchies

---

## Related

- [traits.md](traits.md) - Trait visibility and extension patterns
- [unsafe.md](unsafe.md) - Containing unsafe code
- [quality.md](quality.md) - Documentation for modules

## References

- [Rust API Guidelines: Documentation](https://rust-lang.github.io/api-guidelines/documentation.html)
- [Rust Design Patterns: Small Crates](https://rust-unofficial.github.io/patterns/patterns/structural/small-crates.html)
- [Cargo Book: Features](https://doc.rust-lang.org/cargo/reference/features.html)
