---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Ownership

Make ownership transfer visible in signatures. Borrow for temporary access; take ownership when retaining, consuming, or transferring a value. The API defines the contract, and the caller chooses how to satisfy it.

## Borrowed Views and Owned Inputs

For temporary read access, prefer `&str`, `&[T]`, `&Path`, or `&T` over references to particular containers. `&String` coerces to `&str`; an owned `String` still needs to be borrowed at the call site.

```rust
fn inspect(text: &str) -> usize {
    text.len()
}

fn retain(text: String, messages: &mut Vec<String>) {
    messages.push(text);
}

let owned = String::from("hello");
assert_eq!(inspect(&owned), 5);
retain(owned, &mut Vec::new());
```

Internal allocation can be the right contract when ownership is needed only on some paths. This interner allocates a key only on a miss:

```rust
use std::collections::HashMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Symbol(usize);

#[derive(Default)]
struct Interner {
    symbols: HashMap<String, Symbol>,
}

impl Interner {
    fn intern(&mut self, value: &str) -> Symbol {
        if let Some(&symbol) = self.symbols.get(value) {
            return symbol;
        }
        let symbol = Symbol(self.symbols.len());
        self.symbols.insert(value.to_owned(), symbol);
        symbol
    }
}

let mut interner = Interner::default();
assert_eq!(interner.intern("name"), interner.intern("name"));
```

Taking `String` here would make a caller starting with `&str` allocate before discovering a hit. Similarly, a repeatable builder may deliberately clone its configuration: [ripgrep's `SearcherBuilder::build(&self)`](../../resources/languages/rust/ripgrep/crates/searcher/src/searcher/mod.rs) leaves the builder available for another build.

## Clone for Independent Ownership

When cloning resolves a borrow error, determine whether two independently owned values are needed. If they are, the clone expresses the data model. If they are not, shorten a borrow, reorder operations, destructure fields, or transfer ownership.

```rust
use std::collections::HashMap;

let mut current_key = String::from("current");
let mut map = HashMap::new();

// Both places retain the key: a clone is necessary for this representation.
map.insert(current_key.clone(), 1);
assert_eq!(current_key, "current");

// Transfer the key when leaving current_key empty is intended.
let key = std::mem::take(&mut current_key);
map.insert(key, 2);
assert!(current_key.is_empty());
```

Moving a clone into a separate statement does not eliminate it. Also preserve update semantics: `insert` replaces an existing value; `entry(key).or_insert_with(compute)` preserves it and computes only on a miss. Use the entry API for that behavior, not as a generic borrow-checker fix.

## Borrow Disjoint Fields Directly

Rust already permits an immutable borrow of one field alongside a mutable borrow of another. Newtype wrappers are unnecessary for this:

```rust
fn transform(input: &[u8]) -> impl Iterator<Item = u8> {
    input.iter().map(|byte| byte.wrapping_add(1))
}

struct Processor {
    input: Vec<u8>,
    output: Vec<u8>,
}

impl Processor {
    fn process(&mut self) {
        self.output.extend(transform(&self.input));
    }

    fn process_explicitly(&mut self) {
        let Self { input, output } = self;
        output.extend(transform(input));
    }
}

let mut processor = Processor { input: vec![1, 2], output: vec![] };
processor.process();
processor.process_explicitly();
assert_eq!(processor.output, [2, 3, 2, 3]);
```

A method requiring `&mut self` borrows the whole receiver. This different example fails:

```rust,compile_fail,E0502
struct Processor { input: Vec<u8>, output: Vec<u8> }

impl Processor {
    fn transform(&mut self, input: &[u8]) {
        self.output.extend_from_slice(input);
    }

    fn process(&mut self) {
        self.transform(&self.input);
    }
}
```

Expose the narrower access with a free function or a method on a component. Decompose types when ownership, invariants, or responsibilities are separate; exploit field borrowing first. See the [Rustonomicon on splitting borrows](https://doc.rust-lang.org/nomicon/borrow-splitting.html).

## Transfer Values with `take` or `replace`

Use `mem::take(&mut field)` when `Default::default()` is a valid replacement. Use `mem::replace(&mut field, replacement)` when an explicit value better expresses the temporary state. An `Option<T>` also offers `.take()`, leaving `None`.

Whole-state replacement can make a transition easier to inspect:

```rust
enum State {
    Ready { data: String },
    Processing { data: String },
    Done,
}

fn transition(state: &mut State, process: impl FnOnce(String)) {
    let previous = std::mem::replace(state, State::Done);
    *state = match previous {
        State::Ready { data } => State::Processing { data },
        State::Processing { data } => {
            process(data);
            State::Done
        }
        State::Done => State::Done,
    };
}
```

Choose the replacement deliberately. If `process` unwinds, this version leaves `state` as `Done`. Taking only the data field instead could leave `Processing` with an empty string. Neither temporary state is universally correct. See [Rust Design Patterns on `mem::replace`](../../resources/languages/rust/patterns/src/idioms/mem-replace.md).

## Consider Returning Inputs on Failure

If failure leaves an owned argument available and callers can reasonably retry or recover it, consider returning it in the error. [Tokio's channel errors](../../resources/languages/rust/tokio/tokio/src/sync/mpsc/error.rs) provide `SendError<T>(T)` and distinguish full from closed channels in `TrySendError<T>`.

```rust
use std::sync::mpsc;

let (sender, receiver) = mpsc::channel();
drop(receiver);
let error = sender.send(String::from("recover me")).unwrap_err();
assert_eq!(error.0, "recover me");
```

`String::from_utf8` similarly preserves invalid bytes in its error. This is a recovery design choice: partial consumption, sensitive contents, error size, and meaningless retries can justify a different contract.

## Lifetimes Express Relationships

Use elision for straightforward signatures. A short name is idiomatic for one obvious relationship; descriptive names help distinguish several sources in a larger API. An annotation never extends the life of its referent.

```rust
fn first<'a, T>(items: &'a [T]) -> Option<&'a T> {
    items.first()
}

struct Document<'input> { text: &'input str }
struct Config;

fn parse<'input>(input: &'input str, _config: &Config) -> Document<'input> {
    Document { text: input }
}
```

In Serde, `Deserialize<'de>` can produce values borrowing from input that lives for `'de`. [`DeserializeOwned`](../../resources/languages/rust/serde/serde_core/src/de/mod.rs) means `for<'de> Deserialize<'de>`, so the result need not borrow from a particular deserializer input. Substituting `Deserialize<'static>` does not express that contract. See [Serde's lifetime explanation](https://serde.rs/lifetimes.html).

## Precise RPIT Capture

In Rust 2024, return-position `impl Trait` captures all in-scope lifetime, type, and const parameters by default. Type and const capture already applied in earlier editions; the edition change mainly adds implicit lifetime capture to free and inherent functions.

Use `use<...>` when an unwanted capture would unnecessarily constrain callers. This example actually excludes a lifetime:

```rust
use std::collections::HashMap;

fn keys<'map, 'context, K, V>(
    map: &'map HashMap<K, V>,
    _context: &'context (),
) -> impl Iterator<Item = &'map K> + use<'map, K, V> {
    map.keys()
}

let map = HashMap::from([(1, 2)]);
let iter = {
    let context = ();
    keys(&map, &context)
};
assert_eq!(iter.copied().collect::<Vec<_>>(), [1]);
```

Without the capture bound, the return type also captures `'context`, preventing this use after `context` leaves scope. Capture controls which generic parameters the opaque type may depend on; an outlives bound such as `+ 'map` makes a different promise.

Current restrictions require every in-scope type and const parameter in `use<...>`, along with lifetimes mentioned in the other bounds. Put lifetimes first. In trait definitions, include `Self`. Argument-position `impl Trait` introduces an anonymous type parameter: rewrite it as a named generic to list it. `use<>` is possible only when there are no required parameters to list. Precise capture has been stable since 1.82, including in edition 2021; the older `Captures` workaround is historical. See the [Reference](https://doc.rust-lang.org/reference/types/impl-trait.html#precise-capturing) and [Edition Guide](https://doc.rust-lang.org/edition-guide/rust-2024/rpit-lifetime-capture.html).

## Shared Ownership and Task Lifetimes

Accept `&T` for temporary access. Accept `Rc<T>` or `Arc<T>` when acquiring, storing, or transferring shared ownership:

```rust
use std::rc::Rc;

#[derive(Default)]
struct Registry { entries: Vec<Rc<String>> }

impl Registry {
    fn register(&mut self, value: Rc<String>) {
        self.entries.push(value);
    }
}
```

`Rc<RefCell<T>>` is appropriate for shared mutable objects on one thread. Runtime borrow checks and potential cycles need a deliberate design; widespread unstructured use is a reason to review that design, not an automatic defect. The [Rust Book's interior mutability chapter](../../resources/languages/rust/rust-book/src/ch15-05-interior-mutability.md) explains this combination.

`T: 'static` rules out references with shorter lifetimes inside `T`; it does not require keeping the value alive forever. `&'static T` is a reference valid for the static lifetime. Require these bounds only when the operation needs them, such as an independently spawned task. Scoped threads can borrow local data:

```rust
let values = vec![1, 2, 3];
let total = std::thread::scope(|scope| {
    scope.spawn(|| values.iter().sum::<i32>()).join().unwrap()
});
assert_eq!(total, 6);
```

## Related

- [Types](types.md): representation, builders, and conditional ownership
- [Traits](traits.md): generic and async contracts
- [Async I/O](async-io.md): task ownership and cancellation
- [References and source examples](resources.md): pinned snapshots and reading paths
