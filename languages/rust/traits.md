---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Traits

Traits express shared behavior and the guarantees callers may rely on. Choose dispatch, ownership, lifetimes, and concurrency bounds as parts of that contract.

## Static and Dynamic Dispatch

Generics allow specialization and inlining, with possible costs in compilation time and code size. Trait objects support runtime selection and can reduce monomorphization, with indirect calls unless optimized away. Neither design guarantees better performance without measurement.

```rust
// A borrowed trait object needs no heap allocation.
trait Measure {
    fn size(&self) -> usize;
}

impl Measure for String {
    fn size(&self) -> usize { self.len() }
}

fn size_generic<T: Measure + ?Sized>(value: &T) -> usize {
    value.size()
}

fn size_dynamic(value: &dyn Measure) -> usize {
    value.size()
}

let text = String::from("hello");
assert_eq!(size_generic(&text), size_dynamic(&text));
```

Use dynamic dispatch for runtime choice, interface simplicity, or code-size constraints as well as heterogeneous collections. [ripgrep's directory walker](../../resources/languages/rust/ripgrep/crates/ignore/src/walk.rs) combines shared callbacks with trait objects and scoped visitor lifetimes.

## Dyn Compatibility

A dyn-compatible trait can be used as `dyn Trait`; this was formerly called object safety. Exclude a method that cannot be dispatched through the object with `where Self: Sized` when the remaining interface is useful:

```rust
trait Storage {
    fn read(&self, key: &str) -> Option<Vec<u8>>;

    fn read_as<T>(&self, key: &str) -> Option<T>
    where
        Self: Sized,
        T: From<Vec<u8>>,
    {
        self.read(key).map(T::from)
    }
}

fn inspect(storage: &dyn Storage) -> Option<Vec<u8>> {
    storage.read("key")
}
```

This exclusion makes `read_as` unavailable through `dyn Storage`; it does not make arbitrary generic methods dynamically dispatchable. Native async methods, opaque return types, and GATs have their own restrictions. Check the [Reference's dyn-compatibility rules](https://doc.rust-lang.org/reference/items/traits.html#dyn-compatibility).

Trait-object upcasting has been stable since 1.86:

```rust
trait Animal { fn speak(&self) -> &'static str; }
trait Dog: Animal { fn fetch(&self); }

struct Labrador;
impl Animal for Labrador { fn speak(&self) -> &'static str { "woof" } }
impl Dog for Labrador { fn fetch(&self) {} }

let dog: &dyn Dog = &Labrador;
let animal: &dyn Animal = dog;
assert_eq!(animal.speak(), "woof");
```

An `as_super` helper may be redundant on supported compilers, but removing a public method is still an API compatibility decision.

## Async Methods: Decide the Future Contract

Native `async fn` and return-position `impl Trait` in traits have been stable since 1.75. They work well when their bounds fit the callers. Evaluate these separate questions before changing an existing trait:

| Requirement                                   | Design choice                                                                       |
| --------------------------------------------- | ----------------------------------------------------------------------------------- |
| Local future with no cross-thread requirement | Native `async fn` may suffice                                                       |
| Generic caller needs a `Send` future          | State `-> impl Future<Output = T> + Send`, or generate an equivalent trait contract |
| Runtime dispatch through `dyn Trait`          | Use a dyn-compatible boxed-future interface, manually or via `async-trait`          |
| Borrowed result or receiver                   | Preserve the intended lifetimes; boxing does not remove them                        |

A `Send + Sync` receiver does not promise that each method's future is `Send`. This fails because a generic caller cannot assume that missing guarantee:

```rust,compile_fail
trait Service: Send + Sync {
    async fn fetch(&self) -> String;
}

fn require_send(_: impl Send) {}

fn check<S: Service>(service: &S) {
    require_send(service.fetch());
}
```

State the bound explicitly when callers must move the future between threads:

```rust
trait Service: Sync {
    fn fetch(&self) -> impl Future<Output = String> + Send;
}

struct Greeting(String);

impl Service for Greeting {
    async fn fetch(&self) -> String {
        self.0.clone()
    }
}

fn into_task<S>(service: S) -> impl Future<Output = String> + Send + 'static
where
    S: Service + Send + 'static,
{
    async move { service.fetch().await }
}

fn require_send_static(_: impl Future<Output = String> + Send + 'static) {}
require_send_static(into_task(Greeting(String::from("hello"))));
```

The receiver is owned by the outer future. Its `Send + 'static` bounds and the method future's `Send` bound satisfy different parts of that task contract. See [async trait stabilization guidance](https://blog.rust-lang.org/2023/12/21/async-fn-rpit-in-traits.html).

For dynamic dispatch, make the returned future an explicit, uniform type:

```rust
use std::pin::Pin;

type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

trait DynService: Send + Sync {
    fn fetch(&self) -> BoxFuture<'_, String>;
}

struct Greeting(String);

impl DynService for Greeting {
    fn fetch(&self) -> BoxFuture<'_, String> {
        Box::pin(async move { self.0.clone() })
    }
}

let service: Box<dyn DynService> = Box::new(Greeting(String::from("hello")));
let future = service.fetch();
drop(future);
```

`async-trait` automates a boxed-future transformation and usually adds `Send` requirements; its `?Send` option permits local futures. It can remain useful for established generic APIs too. `trait-variant` generates trait variants with additional bounds, such as `Send`; it does not itself make native async methods dyn-compatible. Removing either macro requires checking the resulting signature and downstream callers, not only whether the local implementation compiles. See [`async-trait`](https://docs.rs/async-trait/) and [`trait-variant`](https://docs.rs/trait-variant/).

## Associated Types and Lending APIs

Use an ordinary associated type when the output type is fixed for an implementation. Use a generic associated type when it depends on another parameter, such as a borrow of the receiver:

```rust
trait LendingSource {
    type Item<'a>
    where
        Self: 'a;

    fn next(&mut self) -> Option<Self::Item<'_>>;
}
```

A source reusing internal storage can return a view tied to the current borrow. A caller must stop using that view before mutably borrowing the source for the next item. Ordinary immutable slice windows do not require a lending interface: standard iterators already express them.

[redb's value and table APIs](../../resources/languages/rust/redb/src/types.rs) use lifetime-parameterized associated types for typed access to stored data. Follow the value representation and guard lifetime before attempting to remove a bound. For return-position `impl Trait`, see [precise capture](ownership.md#precise-rpit-capture); a capture list and an associated type solve different problems.

## Conversions and Extension Traits

Prefer implementing `From` and `TryFrom`; blanket implementations then provide `Into` and `TryInto`. Use `From` for an infallible, semantically appropriate conversion and `TryFrom` for validation that can fail.

```rust
#[derive(Debug, PartialEq, Eq)]
struct UserId(u64);

impl From<u64> for UserId {
    fn from(value: u64) -> Self { Self(value) }
}

let id: UserId = 42.into();
assert_eq!(id, UserId(42));
```

Use extension traits to add methods to external types. This helper truncates a borrowed string at a UTF-8 boundary:

```rust
trait StrExt {
    fn prefix_bytes(&self, limit: usize) -> &str;
}

impl StrExt for str {
    fn prefix_bytes(&self, limit: usize) -> &str {
        &self[..self.floor_char_boundary(limit)]
    }
}

assert_eq!("éclair".prefix_bytes(1), "");
assert_eq!("éclair".prefix_bytes(2), "é");
```

Use `Deref` for a transparent pointer-like access relationship when its implicit coercions and method lookup are intended. It is a poor substitute for inheritance between domain objects; explicit delegation or a shared trait keeps that contract clearer.

## Collection Traits

Support standard collection operations when they fit the abstraction:

```rust
use std::collections::HashSet;

struct IdSet(HashSet<u64>);

impl FromIterator<u64> for IdSet {
    fn from_iter<I: IntoIterator<Item = u64>>(iter: I) -> Self {
        Self(iter.into_iter().collect())
    }
}

impl Extend<u64> for IdSet {
    fn extend<I: IntoIterator<Item = u64>>(&mut self, iter: I) {
        self.0.extend(iter);
    }
}

let mut ids: IdSet = [1, 2].into_iter().collect();
ids.extend([2, 3]);
assert_eq!(ids.0.len(), 3);
```

Implement `IntoIterator` for owned and borrowed forms where appropriate, rather than adding an unrelated inherent method with the same name.

## Sealing and Evolution

Seal a trait only when external implementations would constrain invariants or evolution in ways the API cannot support. Explain that choice to users:

```rust
mod private {
    pub trait Sealed {}
    impl Sealed for u8 {}
}

/// Implemented only for the representations supported by this crate.
pub trait WireByte: private::Sealed {
    fn byte(self) -> u8;
}

impl WireByte for u8 {
    fn byte(self) -> u8 { self }
}
```

Keep traits focused on behavior callers need. Adding required methods, removing blanket implementations, or changing future bounds may affect downstream implementations even when the trait has few methods.

## Related

- [Ownership](ownership.md): lifetimes, `Send` task ownership, and capture
- [Async I/O](async-io.md): Tokio examples and cancellation
- [Source catalog](resources.md): Serde, redb, and ripgrep case studies
- [Rust API Guidelines: flexibility](../../resources/languages/rust/api-guidelines/src/flexibility.md)
