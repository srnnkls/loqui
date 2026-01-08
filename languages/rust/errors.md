---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Errors

Error handling, Result types, propagation patterns, and panic guidelines.

## Core Guidelines

### Result is the Default

**Use `Result<T, E>` for all fallible operations.**

```rust
// ✓ CORRECT: Return Result for fallible operations
fn load_config(path: &Path) -> Result<Config, ConfigError> {
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(e) => return Err(ConfigError::Io { path: path.to_owned(), source: e }),
    };

    let config: Config = toml::from_str(&content)
        .map_err(|e| ConfigError::Parse { source: e })?;

    validate(&config)?;
    Ok(config)
}

// ✘ WRONG: Unwrap in library code
fn load_config_bad(path: &Path) -> Config {
    let content = fs::read_to_string(path).unwrap();  // Panics on error
    toml::from_str(&content).unwrap()
}
```

Never `.unwrap()` or `.expect()` in library code. Let callers decide how to handle errors.

### Add Context When Propagating Errors

**Bare `?` loses context. Add information that aids debugging.**

```rust
// ✘ PROBLEMATIC: Bare ? loses context
fn process_file(path: &Path) -> Result<Data, Error> {
    let content = fs::read_to_string(path)?;  // Which file failed?
    let parsed = parse(&content)?;            // Parse of what?
    let validated = validate(parsed)?;        // Validation of what?
    Ok(validated)
}

// ✓ CORRECT: Add context with .map_err()
fn process_file(path: &Path) -> Result<Data, Error> {
    let content = fs::read_to_string(path)
        .map_err(|e| Error::ReadFile { path: path.to_owned(), source: e })?;

    let parsed = parse(&content)
        .map_err(|e| Error::Parse { source: e })?;

    let validated = validate(parsed)
        .map_err(|e| Error::Validation { source: e })?;

    Ok(validated)
}

// ✓ ALSO GOOD: Match for complex handling
fn process_file(path: &Path) -> Result<Data, Error> {
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(e) if e.kind() == ErrorKind::NotFound => {
            return Ok(Data::default());  // Special case: missing file is OK
        }
        Err(e) => return Err(Error::ReadFile { path: path.to_owned(), source: e }),
    };
    // ...
}
```

**Decision table for error propagation:**

| Context | Approach | Example |
|---------|----------|---------|
| **App code + anyhow** | `?` with `.context()` | `fs::read(p).context("reading config")?` |
| **Library + thiserror** | Bare `?` if `From` adds context | `parse(s)?` where `ParseError` captures input |
| **Library + generic error** | `.map_err()` to add context | `.map_err(\|e\| Error::Io { path, source: e })?` |
| **Need to recover** | `match` for specific variants | `match result { Err(e) if recoverable => ... }` |
| **Internal helpers** | Bare `?` is fine | Context is obvious from call site |

**When bare `?` is acceptable:**
- Error type has `From` impls that preserve context (see [Error Handling in Rust](https://burntsushi.net/rust-error-handling/))
- Internal helper functions where context is obvious
- With `.context()` from `anyhow` in application code

**When to use `match` or `.map_err()`:**
- Different error variants need different handling
- You want to recover from specific errors
- You need to add context (path, operation, input value)

### Create Meaningful Error Types

**Never use `()` as an error type. Implement `std::error::Error`.**

```rust
// ✓ CORRECT: Meaningful error type with context
#[derive(Debug)]
pub enum ConfigError {
    Io { path: PathBuf, source: std::io::Error },
    Parse { source: toml::de::Error },
    Validation(String),
}

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io { path, source } => write!(f, "failed to read {}: {source}", path.display()),
            Self::Parse { source } => write!(f, "invalid config format: {source}"),
            Self::Validation(msg) => write!(f, "config validation failed: {msg}"),
        }
    }
}

impl std::error::Error for ConfigError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            Self::Parse { source } => Some(source),
            Self::Validation(_) => None,
        }
    }
}

// ✘ WRONG: Unit error type
fn do_thing() -> Result<Value, ()> {
    // Caller has no information about what went wrong
}
```

Use `thiserror` crate to reduce boilerplate for error type definitions.

### Error Messages are Lowercase

**Error messages should be lowercase without trailing punctuation.**

```rust
// ✓ CORRECT: Lowercase, no punctuation
impl Display for MyError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound => write!(f, "resource not found"),
            Self::InvalidInput(s) => write!(f, "invalid input: {s}"),
            Self::Timeout { after } => write!(f, "operation timed out after {after:?}"),
        }
    }
}

// ✘ WRONG: Capitalized with punctuation
impl Display for BadError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Resource not found.")  // Wrong style
    }
}
```

This convention allows error messages to be chained naturally: "failed to connect: connection refused".

### Document Errors, Panics, and Safety

**Use `# Errors`, `# Panics`, `# Safety` sections in rustdoc.**

```rust
/// Loads configuration from the given path.
///
/// # Errors
///
/// Returns an error if:
/// - The file cannot be read
/// - The file contains invalid TOML
/// - Required fields are missing
///
/// # Panics
///
/// Panics if `path` is empty (programmer error).
pub fn load_config(path: &Path) -> Result<Config, ConfigError> {
    assert!(!path.as_os_str().is_empty(), "path cannot be empty");
    // ...
}

/// Converts bytes to a string without checking validity.
///
/// # Safety
///
/// The caller must ensure that `bytes` contains valid UTF-8.
pub unsafe fn bytes_to_str_unchecked(bytes: &[u8]) -> &str {
    std::str::from_utf8_unchecked(bytes)
}
```

### Bugs vs Errors: The Core Distinction

**Errors are expected. Bugs are not. This determines your handling strategy.**

| | Errors | Bugs |
|---|--------|------|
| **What** | Expected failure modes | Programming mistakes |
| **Examples** | File not found, network timeout, invalid input | Invariant violations, impossible states |
| **Handling** | `Result<T, E>` | `panic!`, `assert!`, `unwrap` |
| **Recovery** | Caller decides | Fix the code |

```rust
// ERROR: File might not exist - expected, recoverable
fn load_config(path: &Path) -> Result<Config, ConfigError> {
    let content = fs::read_to_string(path)?;  // Returns Err if missing
    // ...
}

// BUG: Index out of bounds - programming mistake
fn get_item(items: &[Item], index: usize) -> &Item {
    assert!(index < items.len(), "index out of bounds");  // Panic is correct
    &items[index]
}

// BUG: Impossible state reached
fn process(state: State) {
    match state {
        State::Ready => { /* ... */ }
        State::Done => { /* ... */ }
        State::Invalid => unreachable!("invalid state should never occur"),
    }
}

// ✘ WRONG: Treating an error as a bug
fn connect(url: &str) -> Connection {
    match try_connect(url) {
        Ok(conn) => conn,
        Err(e) => panic!("connection failed: {e}"),  // Network failure is expected!
    }
}
```

See [Unwrap and Expect (BurnSushi)](https://burntsushi.net/unwrap/) for the full discussion.

### When `unwrap`/`expect` is Acceptable

**Use `unwrap`/`expect` when failure indicates a bug, not an error.**

```rust
// ✓ OK: Invariant guaranteed by prior check
let value = map.get(&key).unwrap();  // We just inserted this key

// ✓ OK: Type system can't express the guarantee
let regex = Regex::new(r"^\d+$").unwrap();  // Literal regex, compile-time correct

// ✓ OK: Test code (panic = clear test failure)
#[test]
fn test_parse() {
    let result = parse("valid input").unwrap();
    assert_eq!(result.value, 42);
}

// ✓ OK: Quick scripts and prototyping
fn main() {
    let config = load_config("config.toml").unwrap();  // You're the only user
}

// ✓ OK: Doc examples (see quality.md for house style)
/// ```
/// let result = parse("input").unwrap();  // Focus on the API, not error handling
/// ```

// ✘ WRONG: User-provided input might fail
fn parse_user_input(input: &str) -> Value {
    serde_json::from_str(input).unwrap()  // Should return Result!
}

// ✘ WRONG: External resource might not exist
fn read_config() -> Config {
    let content = fs::read_to_string("config.toml").unwrap();  // Should return Result!
    toml::from_str(&content).unwrap()
}
```

**The question to ask:** "If this fails, is it a bug in my code or an expected error?"

### Validate Arguments Statically When Possible

**Prefer type-level validation over runtime checks.**

```rust
// ✓ CORRECT: Static validation via newtype
pub struct NonEmptyString(String);

impl NonEmptyString {
    pub fn new(s: String) -> Result<Self, EmptyStringError> {
        if s.is_empty() {
            Err(EmptyStringError)
        } else {
            Ok(Self(s))
        }
    }
}

// Function can't receive empty string
fn greet(name: &NonEmptyString) {
    println!("Hello, {}!", name.0);
}

// ✘ WRONG: Runtime validation everywhere
fn greet_bad(name: &str) -> Result<(), Error> {
    if name.is_empty() {
        return Err(Error::EmptyName);  // Checked in every function
    }
    println!("Hello, {name}!");
    Ok(())
}
```

Push validation to boundaries. Once data is validated, use types that guarantee validity.

### Provide `_unchecked` Variants for Hot Paths

**Offer opt-out validation for performance-critical code.**

```rust
impl Ascii {
    /// Creates an Ascii from a byte, returning an error if invalid.
    pub fn new(byte: u8) -> Result<Self, AsciiError> {
        if byte.is_ascii() {
            Ok(Self(byte))
        } else {
            Err(AsciiError(byte))
        }
    }

    /// Creates an Ascii from a byte without checking validity.
    ///
    /// # Safety
    ///
    /// The caller must ensure that `byte` is a valid ASCII value (< 128).
    pub unsafe fn new_unchecked(byte: u8) -> Self {
        debug_assert!(byte.is_ascii());
        Self(byte)
    }
}
```

The `_unchecked` variant should still use `debug_assert!` to catch errors in development.

### Use `thiserror` for Library Errors, `anyhow` for Applications

**Choose error handling approach based on context.**

```rust
// ✓ Library code: thiserror for structured errors
use thiserror::Error;

#[derive(Debug, Error)]
pub enum DatabaseError {
    #[error("connection failed: {0}")]
    Connection(#[from] std::io::Error),

    #[error("query failed: {0}")]
    Query(String),

    #[error("record not found: {id}")]
    NotFound { id: u64 },
}

// ✓ Application code: anyhow with context
use anyhow::{Context, Result};

fn main() -> Result<()> {
    // In application code, ? with .context() is acceptable
    // because anyhow captures backtraces and context is added
    let config = load_config()
        .context("failed to load configuration")?;

    let db = connect(&config.db_url)
        .with_context(|| format!("failed to connect to {}", config.db_url))?;

    Ok(())
}
```

- **Libraries**: Use `thiserror` - structured errors, callers match on variants
- **Applications**: Use `anyhow` with `.context()` - `?` is acceptable here because context is preserved

## Summary

**Bugs vs Errors:**
- **Errors** (expected failures) → `Result<T, E>`
- **Bugs** (programming mistakes) → `panic!`, `assert!`, `unwrap`

**Error handling:**
- **DO** return `Result` for operations that can fail expectedly
- **DO** add context when propagating errors (path, operation, input)
- **DO** use `.map_err()` or `match` to add context before `?`
- **DO** implement `std::error::Error` for error types
- **DO** use `thiserror` for library error types
- **DO** use `anyhow` with `.context()` in application code
- **NEVER** use `()` as an error type

**Panicking:**
- **DO** use `unwrap`/`expect` when failure indicates a bug
- **DO** use `unwrap` in tests and quick scripts
- **DON'T** use `unwrap` for user input, files, or network (these are errors, not bugs)

**Style:**
- **DO** write error messages lowercase without trailing punctuation
- **DO** document errors with `# Errors` section

---

## Related

- [types.md](types.md) - Designing types that prevent invalid states
- [ownership.md](ownership.md) - Returning consumed arguments in errors
- [async-io.md](async-io.md) - Error handling in async contexts

## References

- [Error Handling in Rust (BurnSushi)](https://burntsushi.net/rust-error-handling/) - Comprehensive guide by ripgrep author
- [Unwrap and Expect (BurnSushi)](https://burntsushi.net/unwrap/) - When panicking is appropriate
- [Rust API Guidelines: Error Types](https://rust-lang.github.io/api-guidelines/interoperability.html#c-good-err)
- [Rust API Guidelines: Dependability](https://rust-lang.github.io/api-guidelines/dependability.html)
- [thiserror crate](https://docs.rs/thiserror/)
- [anyhow crate](https://docs.rs/anyhow/)
- [Error Handling in Rust](https://doc.rust-lang.org/book/ch09-00-error-handling.html)
