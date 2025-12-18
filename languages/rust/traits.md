---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Traits

Trait design, composition patterns, and polymorphism guidelines.

## Core Guidelines

### Traits for Shared Behavior

**No inheritance in Rust. Use trait-based polymorphism.**

```rust
// ✓ CORRECT: Trait defines shared behavior
trait Drawable {
    fn draw(&self, canvas: &mut Canvas);
    fn bounds(&self) -> Rect;
}

struct Circle { center: Point, radius: f64 }
struct Rectangle { origin: Point, size: Size }

impl Drawable for Circle {
    fn draw(&self, canvas: &mut Canvas) { /* ... */ }
    fn bounds(&self) -> Rect { /* ... */ }
}

impl Drawable for Rectangle {
    fn draw(&self, canvas: &mut Canvas) { /* ... */ }
    fn bounds(&self) -> Rect { /* ... */ }
}

// ✘ NO EQUIVALENT: Inheritance-based polymorphism
// class Shape { virtual void draw() = 0; }
// class Circle : public Shape { ... }
```

### Prefer Generics Over Trait Objects

**Static dispatch by default. Dynamic dispatch when required.**

```rust
// ✓ PREFERRED: Generics (static dispatch, monomorphized)
fn draw_all<D: Drawable>(items: &[D], canvas: &mut Canvas) {
    for item in items {
        item.draw(canvas);
    }
}

// ✓ CORRECT: Trait object when heterogeneous collection needed
fn draw_mixed(items: &[Box<dyn Drawable>], canvas: &mut Canvas) {
    for item in items {
        item.draw(canvas);
    }
}

// Use trait objects when:
// - Heterogeneous collections (different concrete types)
// - Plugin systems / runtime extension
// - Reducing code size (no monomorphization)
```

Generics: zero-cost, inlined, larger binary
Trait objects: indirection, vtable lookup, smaller binary

### Make Traits Object-Safe When Useful

**Use `Self: Sized` to exclude non-object-safe methods.**

```rust
trait Storage {
    // Object-safe: can be used with dyn Storage
    fn read(&self, key: &str) -> Option<Vec<u8>>;
    fn write(&self, key: &str, value: &[u8]);

    // Not object-safe due to generic, but excluded from trait object
    fn read_typed<T: DeserializeOwned>(&self, key: &str) -> Option<T>
    where
        Self: Sized,  // Excludes from dyn Storage
    {
        self.read(key).and_then(|bytes| serde_json::from_slice(&bytes).ok())
    }
}

// Can use as trait object
fn use_storage(storage: &dyn Storage) {
    storage.read("key");  // Works
    // storage.read_typed::<Config>("key");  // Won't compile
}
```

### Use Extension Traits for External Types

**Add methods to types you don't own via extension traits.**

```rust
// ✓ CORRECT: Extension trait for String
trait StringExt {
    fn truncate_to(&self, max_len: usize) -> &str;
}

impl StringExt for str {
    fn truncate_to(&self, max_len: usize) -> &str {
        if self.len() <= max_len {
            self
        } else {
            &self[..self.floor_char_boundary(max_len)]
        }
    }
}

// Now available on all &str
let s = "hello world".truncate_to(5);
```

Convention: name extension traits `{Type}Ext` (e.g., `IteratorExt`, `StringExt`).

### Implement Standard Conversion Traits

**Use `From`/`TryFrom`, never implement `Into`/`TryInto` directly.**

```rust
// ✓ CORRECT: Implement From
impl From<Config> for Settings {
    fn from(config: Config) -> Self {
        Settings {
            name: config.name,
            value: config.value,
        }
    }
}

// Automatically get Into for free
let settings: Settings = config.into();

// ✓ CORRECT: TryFrom for fallible conversions
impl TryFrom<&str> for Email {
    type Error = EmailError;

    fn try_from(s: &str) -> Result<Self, Self::Error> {
        if s.contains('@') {
            Ok(Email(s.to_string()))
        } else {
            Err(EmailError::InvalidFormat)
        }
    }
}

// ✘ WRONG: Don't implement Into directly
impl Into<Settings> for Config {
    fn into(self) -> Settings { /* ... */ }  // Use From instead
}
```

### Never Use Deref for Inheritance

**`Deref` is for smart pointers only, not for inheritance-like patterns.**

```rust
// ✘ WRONG: Deref polymorphism (anti-pattern)
struct Button {
    widget: Widget,
}

impl Deref for Button {
    type Target = Widget;
    fn deref(&self) -> &Widget {
        &self.widget  // Trying to "inherit" Widget methods
    }
}

// ✓ CORRECT: Explicit delegation
struct Button {
    widget: Widget,
}

impl Button {
    pub fn position(&self) -> Point {
        self.widget.position()
    }

    pub fn set_position(&mut self, pos: Point) {
        self.widget.set_position(pos);
    }
}

// ✓ CORRECT: Deref for actual smart pointers
impl<T> Deref for MyBox<T> {
    type Target = T;
    fn deref(&self) -> &T {
        &self.0
    }
}
```

`Deref` should convert pointer-to-T to T, not convert between unrelated types.

### Collections Implement FromIterator and Extend

**Enable `.collect()` and `.extend()` for custom collections.**

```rust
struct IdSet(HashSet<u64>);

impl FromIterator<u64> for IdSet {
    fn from_iter<I: IntoIterator<Item = u64>>(iter: I) -> Self {
        IdSet(iter.into_iter().collect())
    }
}

impl Extend<u64> for IdSet {
    fn extend<I: IntoIterator<Item = u64>>(&mut self, iter: I) {
        self.0.extend(iter);
    }
}

// Now works with iterator methods
let ids: IdSet = vec![1, 2, 3].into_iter().collect();
```

### Use Sealed Traits for Implementation Control

**Prevent external implementations when needed.**

```rust
mod private {
    pub trait Sealed {}
}

/// This trait cannot be implemented outside this crate.
pub trait DatabaseDriver: private::Sealed {
    fn connect(&self, url: &str) -> Connection;
}

// Only types in this crate can implement Sealed
impl private::Sealed for PostgresDriver {}
impl DatabaseDriver for PostgresDriver {
    fn connect(&self, url: &str) -> Connection { /* ... */ }
}

// External crates can use the trait but not implement it
```

## Summary

- **NEVER** use `Deref` for inheritance-like patterns
- **NEVER** implement `Into` or `TryInto` directly (implement `From`/`TryFrom`)
- **DO** prefer generics over trait objects for static dispatch
- **DO** use `Self: Sized` to make traits object-safe
- **DO** use extension traits for adding methods to external types
- **DO** implement `FromIterator`/`Extend` for collections
- **DO** use sealed traits when implementation must be controlled
- **DON'T** create "god traits" with too many methods (split them)

---

## Related

- [ownership.md](ownership.md) - Trait bounds and ownership
- [types.md](types.md) - Deriving common traits
- [quality.md](quality.md) - Trait naming conventions

## References

- [Rust API Guidelines: Flexibility](https://rust-lang.github.io/api-guidelines/flexibility.html)
- [Rust Design Patterns: Deref Anti-Pattern](https://rust-unofficial.github.io/patterns/anti_patterns/deref.html)
- [Rust Book: Traits](https://doc.rust-lang.org/book/ch10-02-traits.html)
