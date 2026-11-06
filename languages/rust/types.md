---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Types

Use types to express distinctions and preserve invariants that matter to the operation. Keep the representation understandable; a wrapper or extra enum is useful when it prevents a realistic mistake.

## Newtypes and Representation

A newtype distinguishes values that would otherwise share a primitive type. A type alias gives an existing type another name without creating that distinction:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct UserId(u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct OrderId(u64);

fn order_key(user: UserId, order: OrderId) -> (u64, u64) {
    (user.0, order.0)
}

assert_eq!(order_key(UserId(1), OrderId(2)), (1, 2));
```

Newtype abstraction can optimize away, but default Rust representation does not promise the same ABI as the wrapped type. When that guarantee is required, use `#[repr(transparent)]` with a permitted field layout and a compatible inner type:

```rust
#[repr(transparent)]
#[derive(Clone, Copy)]
pub struct WireId(pub u32);
```

`repr(transparent)` is a layout contract, not validation of the value or an endianness conversion. Keep fields private when construction must enforce an invariant. See [type layout](https://doc.rust-lang.org/reference/type-layout.html#the-transparent-representation).

## Preserve Invariants at Boundaries

Use constructors or `TryFrom` to validate input once, then preserve the invariant through every public operation. A simple, precise invariant is more useful than a toy validator claiming to implement a complex format:

```rust
#[derive(Debug, PartialEq, Eq)]
pub struct NonEmptyString(String);

#[derive(Debug, PartialEq, Eq)]
pub struct EmptyString;

impl TryFrom<String> for NonEmptyString {
    type Error = EmptyString;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        if value.is_empty() { Err(EmptyString) } else { Ok(Self(value)) }
    }
}

impl NonEmptyString {
    pub fn as_str(&self) -> &str { &self.0 }
}

assert!(NonEmptyString::try_from(String::new()).is_err());
assert_eq!(NonEmptyString::try_from("hello".to_owned()).unwrap().as_str(), "hello");
```

Returning `&mut String` from this type would let callers empty it and break the invariant. Likewise, derived deserialization may bypass a constructor; arrange validation in the deserialization path when necessary.

## Model Distinct States

Use an enum when the active state determines which data exists:

```rust
enum Connection {
    Disconnected,
    Connecting { attempt: u32 },
    Connected { session: String },
    Failed { reason: String },
}
```

This avoids combinations such as “connected without a session.” Nested options are sometimes meaningful: `Option<Option<T>>` can distinguish an omitted patch field, explicit removal, and replacement. If that meaning is hard to remember, name it:

```rust
enum Patch<T> {
    Unchanged,
    Remove,
    Set(T),
}
```

An in-memory nested option does not by itself guarantee that a serialization format preserves all three states. Define and test the wire representation separately.

## Make Arguments Understandable

Prefer enums over anonymous booleans when a call such as `upload(data, true, false)` hides distinct modes. A named builder method such as `heading(true)` is already clear: [ripgrep's printer builder](../../resources/languages/rust/ripgrep/crates/printer/src/standard.rs) uses `heading(bool)` and `stats(bool)` for straightforward switches.

For combinable flags, consider the `bitflags` crate when its representation and unknown-bit handling fit the API. An ordinary enum describes alternatives, not arbitrary combinations.

## Choose Builder Ownership Deliberately

A consuming builder can move owned fields into its result:

```rust
use std::time::Duration;

struct Client {
    endpoint: String,
    timeout: Duration,
}

struct ClientBuilder {
    endpoint: String,
    timeout: Duration,
}

impl ClientBuilder {
    fn new(endpoint: impl Into<String>) -> Self {
        Self { endpoint: endpoint.into(), timeout: Duration::from_secs(30) }
    }

    fn timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    fn build(self) -> Client {
        Client { endpoint: self.endpoint, timeout: self.timeout }
    }
}

let client = ClientBuilder::new("https://example.com")
    .timeout(Duration::from_secs(5))
    .build();
assert_eq!(client.timeout, Duration::from_secs(5));
```

A reusable builder can instead configure through `&mut self` and build through `&self`, cloning fields that the result must own. [ripgrep's searcher builder](../../resources/languages/rust/ripgrep/crates/searcher/src/searcher/mod.rs) demonstrates this contract. Use `Result` from `build` when configuration can fail, and retain a simpler constructor when a builder adds no value.

## Derive Meaningful Traits

| Trait                       | Suitable contract                                                  |
| --------------------------- | ------------------------------------------------------------------ |
| `Debug`                     | Useful diagnostics, with sensitive fields redacted if needed       |
| `Clone`                     | Independent duplication or shared-handle duplication is meaningful |
| `Copy`                      | Implicit duplication is part of the public contract                |
| `PartialEq` / `Eq`          | A coherent equality relation exists                                |
| `Hash`                      | Hashing agrees with equality                                       |
| `Default`                   | One value is a sensible default                                    |
| `Serialize` / `Deserialize` | A deliberate data representation exists                            |

Adding a public `Copy` implementation constrains future evolution even when today's fields are small. Derives do not replace review of semantic equality, confidentiality, or validation.

## Conditional Ownership with `Cow`

Use `Cow` when returning borrowed or owned data, or when mutation may require ownership. A function that only reads should usually accept `&str` instead:

```rust
use std::borrow::Cow;

fn lowercase_ascii(mut text: Cow<'_, str>) -> Cow<'_, str> {
    if text.bytes().any(|byte| byte.is_ascii_uppercase()) {
        text.to_mut().make_ascii_lowercase();
    }
    text
}

assert!(matches!(lowercase_ascii(Cow::Borrowed("hello")), Cow::Borrowed(_)));
assert_eq!(lowercase_ascii(Cow::Borrowed("HELLO")), "hello");
```

`to_mut` clones a borrowed value when ownership is needed and reuses an already owned value. The function above defines ASCII normalization, not full Unicode case folding or filesystem path normalization.

[Serde's deserializer interface](../../resources/languages/rust/serde/serde_core/src/de/mod.rs) distinguishes borrowed, transient, and owned input. A borrowed field can avoid allocation when the format and deserializer support it; some transformations, such as unescaping strings, require storage. See [deserializer lifetimes](https://serde.rs/lifetimes.html).

## Static and Local Initialization

Prefer standard-library initialization types when they cover the required behavior:

| Type                     | Initialization                        | Sharing                                                 |
| ------------------------ | ------------------------------------- | ------------------------------------------------------- |
| `std::sync::LazyLock<T>` | Closure on first access               | Synchronized, subject to its `T` and initializer bounds |
| `std::sync::OnceLock<T>` | Explicit set or initialization method | Synchronized, subject to `T`'s bounds                   |
| `std::cell::LazyCell<T>` | Closure on first access               | Local, not `Sync`                                       |
| `std::cell::OnceCell<T>` | Explicit set or initialization method | Local, not `Sync`                                       |

```rust
use std::{collections::HashMap, sync::{LazyLock, OnceLock}};

static CODES: LazyLock<HashMap<&'static str, u16>> = LazyLock::new(|| {
    HashMap::from([("ok", 200), ("missing", 404)])
});
static NAME: OnceLock<String> = OnceLock::new();

fn initialize_name(name: String) -> Result<(), String> {
    NAME.set(name)
}

assert_eq!(CODES["ok"], 200);
initialize_name(String::from("service")).unwrap();
assert_eq!(initialize_name(String::from("replacement")), Err("replacement".into()));
```

Handle initialization failures and repeated sets deliberately. Do not discard an error just because initialization occurs once in the intended path. Compare fallible initialization, poisoning, and compiler support before replacing `once_cell` or `lazy_static`; see [modernization](modernization.md#standard-library-alternatives).

## Collection Helpers

Use collection methods when their behavior matches the operation:

```rust
use std::collections::HashMap;

let mut values = vec![1, 2, 3, 4];
// Vec::pop_if (1.86): predicate gets &mut T and can mutate the last element.
assert_eq!(values.pop_if(|value| *value > 3), Some(4));

// Vec::extract_if (1.87): retained elements keep their order.
let evens: Vec<_> = values.extract_if(.., |value| *value % 2 == 0).collect();
assert_eq!(evens, [2]);
assert_eq!(values, [1, 3]);

// HashMap::extract_if (1.88): map iteration order is unspecified.
let mut counts = HashMap::from([("a", 1), ("b", 2)]);
let removed: Vec<_> = counts.extract_if(|_, value| *value == 1).collect();
assert_eq!(removed, [("a", 1)]);

// array_windows (1.94): borrowed fixed-size windows, not owned arrays.
let values = [1, 2, 3, 4];
let windows: Vec<&[i32; 3]> = values.array_windows::<3>().collect();
assert_eq!(windows, [&[1, 2, 3], &[2, 3, 4]]);

// Result::flatten (1.89): collapses equal error types.
let nested: Result<Result<u32, &str>, &str> = Ok(Ok(42));
assert_eq!(nested.flatten(), Ok(42));
```

Both extraction iterators are lazy: dropping early retains unvisited entries. `array_windows::<0>()` panics; choose a nonzero window size. See [`Vec`](https://doc.rust-lang.org/std/vec/struct.Vec.html), [`HashMap`](https://doc.rust-lang.org/std/collections/struct.HashMap.html), and [slice methods](https://doc.rust-lang.org/std/primitive.slice.html#method.array_windows).

Const arguments can be inferred with `_` where enough type information exists (1.89); omitting a turbofish can be simpler still:

```rust
fn identity<const N: usize>(array: [u8; N]) -> [u8; N] { array }
assert_eq!(identity::<_>([1, 2, 3]), [1, 2, 3]);
```

## Related

- [Ownership](ownership.md): borrowed views, moves, and cloning
- [Traits](traits.md): conversions and associated types
- [API Guidelines: type safety](../../resources/languages/rust/api-guidelines/src/type-safety.md)
- [Source catalog](resources.md): redb's typed tables and Serde's borrowed data
