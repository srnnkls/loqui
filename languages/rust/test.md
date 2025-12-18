---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Testing

Testing patterns, organization, and best practices.

## Test Organization

### Unit Tests in Same File

```rust
// src/parser.rs

pub fn parse(input: &str) -> Result<Ast, ParseError> {
    // implementation
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_empty_input() {
        let result = parse("");
        assert!(result.is_ok());
    }

    #[test]
    fn rejects_invalid_syntax() {
        let result = parse("{{invalid");
        assert!(matches!(result, Err(ParseError::Syntax(_))));
    }
}
```

### Integration Tests in `tests/` Directory

```
mylib/
├── src/
│   └── lib.rs
└── tests/
    ├── integration.rs      # Single integration test
    └── api/                # Test module with helpers
        ├── mod.rs
        └── helpers.rs
```

```rust
// tests/integration.rs
use mylib::Client;

#[test]
fn full_workflow() {
    let client = Client::new();
    // Test the public API as an external user would
}
```

### Doc Tests for Examples

```rust
/// Adds two numbers together.
///
/// # Examples
///
/// ```
/// use mylib::add;
/// assert_eq!(add(2, 3), 5);
/// ```
///
/// Negative numbers work too:
///
/// ```
/// use mylib::add;
/// assert_eq!(add(-1, 1), 0);
/// ```
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}
```

Doc tests are compiled and run with `cargo test`. They verify examples stay correct.

## Test Patterns

### Type-Safe Test Fixtures

**Use builders for test data, not random values.**

```rust
#[cfg(test)]
mod tests {
    struct TestUser {
        id: UserId,
        name: String,
        email: Email,
    }

    impl TestUser {
        fn builder() -> TestUserBuilder {
            TestUserBuilder::default()
        }
    }

    #[derive(Default)]
    struct TestUserBuilder {
        id: Option<UserId>,
        name: Option<String>,
        email: Option<Email>,
    }

    impl TestUserBuilder {
        fn id(mut self, id: u64) -> Self {
            self.id = Some(UserId(id));
            self
        }

        fn name(mut self, name: impl Into<String>) -> Self {
            self.name = Some(name.into());
            self
        }

        fn build(self) -> TestUser {
            TestUser {
                id: self.id.unwrap_or(UserId(1)),
                name: self.name.unwrap_or_else(|| "Test User".into()),
                email: self.email.unwrap_or_else(|| Email::parse("test@example.com").unwrap()),
            }
        }
    }

    #[test]
    fn test_with_custom_name() {
        let user = TestUser::builder()
            .name("Alice")
            .build();
        assert_eq!(user.name, "Alice");
    }
}
```

### Test `Send + Sync` Bounds

**Verify thread safety at compile time.**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    fn assert_send<T: Send>() {}
    fn assert_sync<T: Sync>() {}

    #[test]
    fn client_is_send_sync() {
        assert_send::<Client>();
        assert_sync::<Client>();
    }

    #[test]
    fn error_is_send_sync() {
        assert_send::<MyError>();
        assert_sync::<MyError>();
    }
}
```

These tests fail at compile time if bounds aren't satisfied.

### Property-Based Testing

**Use `proptest` for generative testing.**

```rust
#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn parse_roundtrip(s in "[a-z]+") {
            let parsed = parse(&s).unwrap();
            let rendered = render(&parsed);
            assert_eq!(s, rendered);
        }

        #[test]
        fn addition_is_commutative(a in 0i32..1000, b in 0i32..1000) {
            assert_eq!(add(a, b), add(b, a));
        }
    }
}
```

### Async Tests

**Use `#[tokio::test]` for async tests.**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn fetches_data() {
        let client = Client::new();
        let result = client.fetch("https://example.com").await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn handles_timeout() {
        let client = Client::builder()
            .timeout(Duration::from_millis(1))
            .build();
        let result = client.fetch("https://slow.example.com").await;
        assert!(matches!(result, Err(Error::Timeout)));
    }
}
```

### Test Helpers with `rstest`

**Use `rstest` for parameterized tests and fixtures.**

```rust
use rstest::{rstest, fixture};

#[fixture]
fn client() -> Client {
    Client::builder()
        .base_url("https://test.example.com")
        .build()
}

#[rstest]
#[case("hello", 5)]
#[case("", 0)]
#[case("rust", 4)]
fn test_length(#[case] input: &str, #[case] expected: usize) {
    assert_eq!(input.len(), expected);
}

#[rstest]
fn test_with_fixture(client: Client) {
    // client fixture is automatically injected
    assert!(client.is_connected());
}
```

## Test Best Practices

### Test Public API, Not Internals

```rust
// ✓ CORRECT: Test observable behavior
#[test]
fn user_can_be_created_and_retrieved() {
    let store = UserStore::new();
    let user = User::new("alice@example.com");

    store.save(&user).unwrap();
    let retrieved = store.find_by_email("alice@example.com").unwrap();

    assert_eq!(retrieved.email, user.email);
}

// ✘ WRONG: Testing internal implementation details
#[test]
fn internal_cache_is_populated() {
    let store = UserStore::new();
    store.save(&user).unwrap();
    assert!(store.cache.contains_key(&user.id));  // Tests internals
}
```

### No Random Without Seeds

**Tests must be reproducible.**

```rust
// ✘ WRONG: Non-deterministic test
#[test]
fn random_test() {
    let value = rand::random::<u32>();
    assert!(process(value).is_ok());  // May fail randomly
}

// ✓ CORRECT: Seeded RNG for reproducibility
#[test]
fn seeded_random_test() {
    use rand::SeedableRng;
    let mut rng = rand::rngs::StdRng::seed_from_u64(42);
    let value = rng.gen::<u32>();
    assert!(process(value).is_ok());
}
```

### Use `assert!` Macros Appropriately

```rust
// Prefer specific assertions for better error messages
assert_eq!(actual, expected);           // Equality
assert_ne!(actual, unexpected);         // Inequality
assert!(condition);                     // Boolean
assert!(matches!(value, Pattern));      // Pattern matching

// With custom messages
assert_eq!(result.len(), 3, "expected 3 items, got {}", result.len());
```

## Summary

- **DO** put unit tests in `#[cfg(test)] mod tests` in same file
- **DO** put integration tests in `tests/` directory
- **DO** write doc tests for all public API examples
- **DO** use builders for test fixtures
- **DO** test `Send + Sync` bounds at compile time
- **DO** use `proptest` for property-based testing
- **DO** use seeded RNG for reproducible tests
- **DON'T** test internal implementation details
- **DON'T** use non-deterministic values without seeds

---

## Related

- [quality.md](quality.md) - Documentation and examples
- [errors.md](errors.md) - Testing error conditions

## References

- [Rust Book: Testing](https://doc.rust-lang.org/book/ch11-00-testing.html)
- [proptest crate](https://docs.rs/proptest/)
- [rstest crate](https://docs.rs/rstest/)
