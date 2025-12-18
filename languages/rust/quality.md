---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Quality

Naming conventions, documentation, and code quality guidelines.

## Naming Conventions

### RFC 430 Casing Rules

| Item | Convention | Example |
|------|------------|---------|
| Types | `UpperCamelCase` | `HttpRequest`, `UserId` |
| Traits | `UpperCamelCase` | `Iterator`, `Display` |
| Enum variants | `UpperCamelCase` | `Some`, `None`, `Ok` |
| Functions | `snake_case` | `read_file`, `to_string` |
| Methods | `snake_case` | `as_bytes`, `into_inner` |
| Macros | `snake_case!` | `println!`, `vec!` |
| Modules | `snake_case` | `http_client`, `file_io` |
| Constants | `SCREAMING_SNAKE_CASE` | `MAX_SIZE`, `PI` |
| Statics | `SCREAMING_SNAKE_CASE` | `GLOBAL_CONFIG` |
| Type parameters | single uppercase | `T`, `E`, `K`, `V` |
| Lifetimes | short lowercase | `'a`, `'de`, `'src` |

Acronyms count as one word: `Uuid` not `UUID`, `Stdin` not `StdIn`.

### Conversion Method Prefixes

| Prefix | Cost | Ownership | Example |
|--------|------|-----------|---------|
| `as_` | Free | borrowed → borrowed | `str::as_bytes()` |
| `to_` | Expensive | borrowed → owned | `str::to_lowercase()` |
| `into_` | Variable | owned → owned | `String::into_bytes()` |

```rust
impl MyType {
    // Free view into internal data
    pub fn as_slice(&self) -> &[u8] {
        &self.data
    }

    // Expensive conversion, allocates
    pub fn to_vec(&self) -> Vec<u8> {
        self.data.to_vec()
    }

    // Takes ownership, may or may not be cheap
    pub fn into_inner(self) -> Vec<u8> {
        self.data
    }
}
```

### Getter Names

**No `get_` prefix for simple getters.**

```rust
// ✓ CORRECT
impl Config {
    pub fn name(&self) -> &str { &self.name }
    pub fn name_mut(&mut self) -> &mut String { &mut self.name }
}

// ✘ WRONG
impl Config {
    pub fn get_name(&self) -> &str { &self.name }
}

// Exception: indexed access uses get
impl Container {
    pub fn get(&self, index: usize) -> Option<&Item> { /* ... */ }
    pub fn get_mut(&mut self, index: usize) -> Option<&mut Item> { /* ... */ }
}
```

### Iterator Methods

Collections should provide `iter`, `iter_mut`, `into_iter`:

```rust
impl MyCollection {
    pub fn iter(&self) -> Iter<'_> { /* ... */ }
    pub fn iter_mut(&mut self) -> IterMut<'_> { /* ... */ }
    pub fn into_iter(self) -> IntoIter { /* ... */ }
}
```

Iterator type names match their methods: `iter()` → `Iter`, `into_iter()` → `IntoIter`.

## Documentation

### All Public Items Have Examples

```rust
/// Parses a configuration string into a Config object.
///
/// # Examples
///
/// ```
/// # use mylib::Config;
/// let config = Config::parse("key=value")?;
/// assert_eq!(config.get("key"), Some("value"));
/// # Ok::<(), mylib::Error>(())
/// ```
pub fn parse(s: &str) -> Result<Config, Error> {
    // ...
}
```

Examples show **why** to use something, not just **how** to call it.

### Doc Examples: `?` vs `unwrap`

**There are two positions:**

1. **Rust API Guidelines**: Use `?` - examples are copied, model good practices
2. **BurnSushi**: `unwrap` is fine - examples shouldn't be overburdened by error handling

```rust
// Position 1: ? with boilerplate
/// ```
/// # fn main() -> Result<(), Box<dyn Error>> {
/// let config = Config::parse("key=value")?;
/// #     Ok(())
/// # }
/// ```

// Position 2: unwrap - clearer focus
/// ```
/// let config = Config::parse("key=value").unwrap();
/// ```
```

**Pragmatic approach:** If error handling obscures what you're demonstrating, use `unwrap`. If error handling is a fundamental part of the API being shown, use `?`.

### Document Errors, Panics, Safety

```rust
/// Opens a database connection.
///
/// # Errors
///
/// Returns an error if:
/// - The connection string is malformed
/// - The database is unreachable
/// - Authentication fails
///
/// # Panics
///
/// Panics if called from within an async runtime.
///
/// # Safety
///
/// (For unsafe functions only)
/// The caller must ensure the pointer is valid and properly aligned.
pub fn connect(url: &str) -> Result<Connection, DbError> {
    // ...
}
```

### Hide Implementation Details

```rust
// Don't expose internal types in docs
#[doc(hidden)]
impl From<InternalError> for PublicError {
    fn from(err: InternalError) -> Self { /* ... */ }
}

// Use pub(crate) for internal APIs
pub(crate) fn internal_helper() { /* ... */ }
```

## Clippy

### Enable Pedantic Lints

```toml
# Cargo.toml
[lints.clippy]
pedantic = "warn"
nursery = "warn"

# Or in clippy.toml for more control
```

```rust
// Or at crate level
#![warn(clippy::pedantic)]
#![warn(clippy::nursery)]
```

### Never Use `#[deny(warnings)]` in Libraries

```rust
// ✘ WRONG: Breaks downstream builds on new lints
#![deny(warnings)]

// ✓ CORRECT: Warn but don't fail
#![warn(clippy::all)]

// ✓ OK for binaries: can use deny
// (won't affect other crates)
#![deny(clippy::all)]  // In main.rs only
```

## Error Message Style

**Lowercase, no trailing punctuation.**

```rust
// ✓ CORRECT
impl Display for MyError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "connection refused")
    }
}

// ✘ WRONG
impl Display for MyError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Connection refused.")
    }
}
```

This allows error chaining: `"failed to connect: connection refused"`.

## Iterators vs Loops

**Use iterators for transformations, loops for side effects.**

Rust supports both imperative and functional styles. They coexist intentionally - don't cargo-cult one over the other.

```rust
// ✓ CORRECT: Iterator for transformation (no side effects)
let squares: Vec<_> = numbers.iter()
    .filter(|n| **n > 0)
    .map(|n| n * n)
    .collect();

// ✓ CORRECT: Loop for side effects
for item in &items {
    println!("{item}");
    db.insert(item)?;
}

// ✘ WRONG: for_each for side effects (just a loop in disguise)
items.iter().for_each(|item| {
    println!("{item}");  // Side effect hidden in functional syntax
});

// ✘ WRONG: Loop for pure transformation
let mut squares = Vec::new();
for n in &numbers {
    if *n > 0 {
        squares.push(n * n);  // Iterator chain is clearer
    }
}
```

**The principle:** Functional pipelines should be pure transformations. If you're doing I/O, mutation, or other side effects, be honest about it - use a `for` loop.

```rust
// ✓ Iterator: data in, data out
let result = input
    .lines()
    .filter(|line| !line.is_empty())
    .map(|line| line.to_uppercase())
    .collect::<Vec<_>>();

// ✓ Loop: side effects are the point
for line in input.lines() {
    if !line.is_empty() {
        file.write_all(line.as_bytes())?;  // Side effect
    }
}
```

**Exception:** `for_each` is acceptable when you need to consume an iterator and the closure is already a function:

```rust
// ✓ OK: for_each with existing function
errors.iter().for_each(log::error);
```

## Summary

- **DO** follow RFC 430 naming conventions
- **DO** use `as_`/`to_`/`into_` prefixes correctly
- **DO** omit `get_` prefix on simple getters
- **DO** provide rustdoc examples for all public items
- **DO** document errors, panics, and safety requirements
- **DO** enable clippy pedantic lints
- **DO** use iterators for transformations, loops for side effects
- **DON'T** use `#[deny(warnings)]` in library code
- **DON'T** expose internal types in documentation
- **DON'T** use `for_each` for side effects (use `for` loop)

---

## Related

- [errors.md](errors.md) - Error type design and messages
- [modules.md](modules.md) - Visibility and public API design
- [traits.md](traits.md) - Trait naming conventions

## References

- [Rust API Guidelines: Naming](https://rust-lang.github.io/api-guidelines/naming.html)
- [Rust API Guidelines: Documentation](https://rust-lang.github.io/api-guidelines/documentation.html)
- [RFC 430: Naming Conventions](https://github.com/rust-lang/rfcs/blob/master/text/0430-finalizing-naming-conventions.md)
