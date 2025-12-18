---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Types

Domain modeling, type safety, newtypes, builders, and compile-time invariants.

## Core Guidelines

### Start with Types

**Model your domain with types FIRST. Types are the design.**

```rust
// ✓ CORRECT: Domain types express the model
pub struct Order {
    id: OrderId,
    customer: CustomerId,
    items: Vec<LineItem>,
    status: OrderStatus,
}

pub enum OrderStatus {
    Draft,
    Submitted { at: DateTime<Utc> },
    Fulfilled { at: DateTime<Utc>, tracking: TrackingId },
    Cancelled { reason: String },
}

// ✘ WRONG: Stringly-typed, no compile-time guarantees
pub struct BadOrder {
    id: String,
    customer_id: String,
    status: String,  // "draft", "submitted", ???
    tracking: Option<String>,
}
```

Design types before writing logic. The type system catches errors at compile time.

### Newtype for Type Safety

**Wrap primitives to distinguish semantically different values.**

```rust
// ✓ CORRECT: Newtypes prevent mixing up IDs
pub struct UserId(pub u64);
pub struct OrderId(pub u64);
pub struct ProductId(pub u64);

fn get_order(user: UserId, order: OrderId) -> Option<Order> {
    // Compiler prevents: get_order(order_id, user_id)
}

// ✓ CORRECT: Newtypes for units
pub struct Miles(pub f64);
pub struct Kilometers(pub f64);

impl Miles {
    pub fn to_kilometers(self) -> Kilometers {
        Kilometers(self.0 * 1.60934)
    }
}

// ✘ WRONG: Type aliases don't provide safety
type UserId = u64;
type OrderId = u64;  // Can accidentally swap these
```

Newtypes are zero-cost: same runtime representation as the wrapped type.

### Arguments Convey Meaning Through Types

**Use enums instead of `bool` or `Option` for clarity.**

```rust
// ✓ CORRECT: Enum arguments are self-documenting
pub enum Visibility {
    Public,
    Private,
}

pub enum Compression {
    None,
    Gzip,
    Zstd,
}

fn upload(data: &[u8], visibility: Visibility, compression: Compression) {
    // Clear what each argument means
}

// ✘ WRONG: What do these booleans mean?
fn upload_bad(data: &[u8], is_public: bool, compress: bool) {
    // upload_bad(data, true, false) - unclear
}

// ✘ WRONG: Option obscures intent
fn upload_worse(data: &[u8], public: Option<()>, compress: Option<()>) {
    // What does None mean?
}
```

Enums make call sites readable and enable exhaustive matching.

### Use Builders for Complex Construction

**Builder pattern for types with many optional fields or complex setup.**

```rust
// ✓ CORRECT: Builder for complex configuration
pub struct Client {
    endpoint: String,
    timeout: Duration,
    retries: u32,
    auth: Option<Auth>,
}

pub struct ClientBuilder {
    endpoint: String,
    timeout: Duration,
    retries: u32,
    auth: Option<Auth>,
}

impl ClientBuilder {
    pub fn new(endpoint: impl Into<String>) -> Self {
        Self {
            endpoint: endpoint.into(),
            timeout: Duration::from_secs(30),
            retries: 3,
            auth: None,
        }
    }

    pub fn timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    pub fn retries(mut self, retries: u32) -> Self {
        self.retries = retries;
        self
    }

    pub fn auth(mut self, auth: Auth) -> Self {
        self.auth = Some(auth);
        self
    }

    pub fn build(self) -> Client {
        Client {
            endpoint: self.endpoint,
            timeout: self.timeout,
            retries: self.retries,
            auth: self.auth,
        }
    }
}

// Usage
let client = ClientBuilder::new("https://api.example.com")
    .timeout(Duration::from_secs(60))
    .auth(Auth::bearer(token))
    .build();
```

Consider `#[derive(Builder)]` from the `derive_builder` crate for boilerplate reduction.

### Implement Common Traits Eagerly

**Derive standard traits for public types.**

```rust
// ✓ CORRECT: Derive appropriate traits
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct UserId(String);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub struct Point {
    x: i32,
    y: i32,
}

#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(Serialize, Deserialize))]
pub struct Config {
    name: String,
    value: f64,
}
```

| Trait | When to Derive |
|-------|----------------|
| `Debug` | Almost always (required for error messages) |
| `Clone` | When values can be duplicated |
| `Copy` | Small, trivial types without heap allocation |
| `PartialEq`/`Eq` | When equality comparison makes sense |
| `Hash` | When used as HashMap/HashSet keys |
| `Default` | When there's a sensible default value |
| `Serialize`/`Deserialize` | For data interchange (feature-gated) |

### Use `bitflags` for Flag Sets

**Don't use enums with bit values. Use the `bitflags` crate.**

```rust
// ✓ CORRECT: bitflags for combinable flags
use bitflags::bitflags;

bitflags! {
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct Permissions: u32 {
        const READ    = 0b0001;
        const WRITE   = 0b0010;
        const EXECUTE = 0b0100;
        const ADMIN   = 0b1000;
    }
}

fn check_access(user_perms: Permissions, required: Permissions) -> bool {
    user_perms.contains(required)
}

let perms = Permissions::READ | Permissions::WRITE;

// ✘ WRONG: Enum with manual bit manipulation
enum BadPermissions {
    Read = 0b0001,
    Write = 0b0010,
    // Can't combine these naturally
}
```

### Parse Don't Validate

**Convert at boundaries to validated types. Core logic uses guaranteed-valid types.**

```rust
// ✓ CORRECT: Parse into validated type
pub struct Email(String);

impl Email {
    pub fn parse(s: &str) -> Result<Self, EmailError> {
        if s.contains('@') && s.len() > 3 {
            Ok(Email(s.to_string()))
        } else {
            Err(EmailError::Invalid)
        }
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

// Core logic uses Email, not String
fn send_notification(to: &Email, message: &str) {
    // No validation needed here - Email is guaranteed valid
}

// ✘ WRONG: Validate repeatedly
fn send_notification_bad(to: &str, message: &str) -> Result<(), Error> {
    if !to.contains('@') {
        return Err(Error::InvalidEmail);  // Validated everywhere
    }
    // ...
}
```

Parse at system boundaries (API handlers, CLI, config loading). Propagate validated types internally.

### Make Illegal States Unrepresentable

**Use enums to eliminate invalid state combinations.**

```rust
// ✓ CORRECT: State machine as enum
pub enum Connection {
    Disconnected,
    Connecting { attempt: u32 },
    Connected { session: Session },
    Failed { error: Error, retries: u32 },
}

// Each variant has exactly the fields it needs
// Can't have a session while disconnected
// Can't have retries without an error

// ✘ WRONG: All fields optional, many invalid combinations
pub struct BadConnection {
    is_connected: bool,
    is_connecting: bool,
    session: Option<Session>,
    error: Option<Error>,
    attempt: Option<u32>,
    retries: Option<u32>,
}
// is_connected=true, is_connecting=true, session=None ???
```

If a combination of values is invalid, make it unrepresentable in the type system.

## Summary

- **NEVER** use `String` or primitives for domain identifiers (use newtypes)
- **NEVER** use `bool` parameters for modes or options (use enums)
- **NEVER** model state machines with `Option` soup (use enums)
- **DO** design types before implementing logic
- **DO** use newtypes for type safety (IDs, units, validated strings)
- **DO** use enums for arguments with distinct modes
- **DO** use builders for complex construction
- **DO** derive common traits (`Debug`, `Clone`, `PartialEq`, etc.)
- **DO** use `bitflags` for combinable flags
- **DO** parse at boundaries, use validated types internally

---

## Related

- [ownership.md](ownership.md) - How types express ownership semantics
- [traits.md](traits.md) - Implementing and deriving traits
- [errors.md](errors.md) - Error types for parsing failures

## References

- [Rust API Guidelines: Type Safety](https://rust-lang.github.io/api-guidelines/type-safety.html)
- [Rust Design Patterns: Newtype](https://rust-unofficial.github.io/patterns/patterns/behavioural/newtype.html)
- [Rust Design Patterns: Builder](https://rust-unofficial.github.io/patterns/patterns/creational/builder.html)
- [Parse, don't validate (Haskell, concepts apply)](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)
