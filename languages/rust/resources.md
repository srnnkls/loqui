---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust References and Source Examples

Use language and library specifications for contracts, teaching material for explanations, and mature implementations for concrete design tradeoffs. A project's working code is evidence that a design can be useful; it does not establish a universal performance or style rule.

The local resources live under `resources/languages/rust/` at the repository root and are populated through Phora. See [resource setup](../../README.md#resources), [source configuration](../../phora.toml), and the exact revisions in [phora.lock](../../phora.lock). These are reading snapshots rather than runtime dependencies. Filtered symlink aliases mean a snapshot is not necessarily a standalone buildable checkout.

## Source Roles and Provenance

The revisions below identify the snapshots used for this guide. They are pins, not claims about the projects' latest releases. Local links require the resource sync; upstream revision links also work when reading this guide on GitHub.

| Resource             | Local entry point                                                                                  | Pinned upstream revision                                                                             | Use it for                                                                   |
| -------------------- | -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Rust API Guidelines  | [Flexibility](../../resources/languages/rust/api-guidelines/src/flexibility.md)                    | [97a0969](https://github.com/rust-lang/api-guidelines/tree/97a0969cb07fe4cabb0eed8a56234053f47d83dc) | Public API flexibility, naming, interoperability, documentation              |
| Rust Design Patterns | [Borrowing and cloning](../../resources/languages/rust/patterns/src/anti_patterns/borrow_clone.md) | [f279f35](https://github.com/rust-unofficial/patterns/tree/f279f3541c37f3cc36ac6c95ba09465c70ad5271) | Patterns, motivations, and tradeoffs                                         |
| Idiomatic Rust       | [Index](../../resources/languages/rust/idiomatic-rust/README.md)                                   | [0c4ecad](https://github.com/mre/idiomatic-rust/tree/0c4ecadfd772c57f2e671b850bb82cd6dc926a49)       | Discovering further reading; follow claims to their original sources         |
| Rust Book            | [Contents](../../resources/languages/rust/rust-book/src/SUMMARY.md)                                | [1500248](https://github.com/rust-lang/book/tree/1500248d8f230566e4ec9f27fcbb8fe9e2898ab1)           | Ownership, lifetimes, error handling, interior mutability, async foundations |
| ripgrep              | [Crates](../../resources/languages/rust/ripgrep/crates)                                            | [3fce3b5](https://github.com/BurntSushi/ripgrep/tree/3fce3b5bb0236da2df6d99672afb8a719642eca7)       | Reusable builders, generic I/O, localized mutation, scoped dynamic dispatch  |
| redb                 | [Typed tables](../../resources/languages/rust/redb/src/table.rs)                                   | [8f08680](https://github.com/cberner/redb/tree/8f08680d3d40f2a030a59ae815b7e763ea6c70d9)             | Borrowed views, consuming transactions, guard lifetimes, failure contracts   |
| Tokio                | [Channel errors](../../resources/languages/rust/tokio/tokio/src/sync/mpsc/error.rs)                | [2025ddd](https://github.com/tokio-rs/tokio/tree/2025ddd83c1466b81f25d0be50f5334b620c51c3)           | Tasks, channels, backpressure, cancellation, blocking work                   |
| Serde                | [Deserializer traits](../../resources/languages/rust/serde/serde_core/src/de/mod.rs)               | [a874a1b](https://github.com/serde-rs/serde/tree/a874a1b1bb1cc16cf5ee3b1b7b527af5705742bb)           | Borrowed deserialization, higher-ranked bounds, derives and generated paths  |

The existing local [Rust Style Guide snapshot](../../resources/languages/rust/rust-style-guide/src/README.md) has no managed source entry in `phora.toml`. Use the [official online Style Guide](https://doc.rust-lang.org/style-guide/) for current formatting guidance; do not infer ownership or architecture mandates from an unmanaged formatting reference.

## ripgrep: Ownership Follows the Operation

Read [`SearcherBuilder::build`](https://github.com/BurntSushi/ripgrep/blob/3fce3b5bb0236da2df6d99672afb8a719642eca7/crates/searcher/src/searcher/mod.rs#L315), then `Searcher::search_reader` in the same file. Building through `&self` clones configuration so the builder can be reused. A generic reader taken by value can itself be a borrowed reader; passing a generic value does not necessarily mean transferring ownership of its underlying resource.

The searcher keeps private `RefCell` scratch buffers. Their use is localized around documented access behavior, showing why interior mutability should be evaluated by its invariant and access discipline.

The [printer builder](https://github.com/BurntSushi/ripgrep/blob/3fce3b5bb0236da2df6d99672afb8a719642eca7/crates/printer/src/standard.rs#L127) clones configuration while accepting its writer by value. Its `heading(bool)` and `stats(bool)` methods name simple switches clearly. The [directory walker](https://github.com/BurntSushi/ripgrep/blob/3fce3b5bb0236da2df6d99672afb8a719642eca7/crates/ignore/src/walk.rs) combines shared callbacks and trait objects with scoped lifetimes.

Apply these examples to [ownership](ownership.md), [builders](types.md#choose-builder-ownership-deliberately), and [dispatch](traits.md#static-and-dynamic-dispatch): there is no single ranking of borrowing, cloning, generics, and smart pointers that fits every operation.

## redb: Views, Guards, and Consuming Transactions

Start with [`Value`](https://github.com/cberner/redb/blob/8f08680d3d40f2a030a59ae815b7e763ea6c70d9/src/types.rs#L153), whose lifetime-parameterized associated types describe representations over storage. Then follow [`Table::insert`](https://github.com/cberner/redb/blob/8f08680d3d40f2a030a59ae815b7e763ea6c70d9/src/table.rs#L323): it accepts borrowed-compatible key and value inputs and returns an optional guard over the replaced value.

[`WriteTransaction::open_table`](https://github.com/cberner/redb/blob/8f08680d3d40f2a030a59ae815b7e763ea6c70d9/src/transactions.rs#L1620) returns a table tied to the transaction's borrow, while `commit(self)` and `abort(self)` consume the transaction. A temporary data view and a completed transaction have different ownership requirements. The type parameters' `'static` bounds do not make every returned data view static.

Read the [commit error contract](https://github.com/cberner/redb/blob/8f08680d3d40f2a030a59ae815b7e763ea6c70d9/src/transactions.rs#L1743) before drawing conclusions about retry or rollback. Its distinction between poisoning and other commit failures is why “return the input on every error” and “an error means nothing happened” are poor general rules.

## Tokio: Error Recovery and Cancellation Differ

[`SendError<T>` and `TrySendError<T>`](https://github.com/tokio-rs/tokio/blob/2025ddd83c1466b81f25d0be50f5334b620c51c3/tokio/src/sync/mpsc/error.rs) preserve unsent values when a send returns an error. The [bounded sender contract](https://github.com/tokio-rs/tokio/blob/2025ddd83c1466b81f25d0be50f5334b620c51c3/tokio/src/sync/mpsc/bounded.rs) separately explains what happens when sending is canceled.

Read the cancellation-safety section of [`select!`](https://github.com/tokio-rs/tokio/blob/2025ddd83c1466b81f25d0be50f5334b620c51c3/tokio/src/macros/select.rs). Receiving a channel message and completing a multi-step read have different restart guarantees. Combine these contracts with task ownership, bounded concurrency, and explicit shutdown in [async I/O](async-io.md).

## Serde: Borrowing Is Part of the Format Contract

[`Deserialize<'de>` and `DeserializeOwned`](https://github.com/serde-rs/serde/blob/a874a1b1bb1cc16cf5ee3b1b7b527af5705742bb/serde_core/src/de/mod.rs#L603) distinguish output that may borrow from one input lifetime from output deserializable independently of that lifetime. `DeserializeOwned` is a higher-ranked `for<'de> Deserialize<'de>` bound, not `Deserialize<'static>`.

```rust
use serde::Deserialize;

#[derive(Deserialize)]
struct Message<'a> {
    text: &'a str,
}

let input = String::from(r#"{"text":"hello"}"#);
let message: Message<'_> = serde_json::from_str(&input).unwrap();
assert_eq!(message.text, "hello");
```

The input lives while the borrowed result is used. This particular string can be borrowed directly; escaped strings or other formats may require owned storage. Follow `Visitor::visit_str`, `visit_borrowed_str`, and `visit_string` to see the distinction, and read the [Serde lifetime guide](https://serde.rs/lifetimes.html).

For macros, read [derive path handling](https://github.com/serde-rs/serde/blob/a874a1b1bb1cc16cf5ee3b1b7b527af5705742bb/serde_derive/src/dummy.rs) and the surrounding attribute and bound generation. Generated paths, lifetime relationships, and helper visibility are part of the caller's API experience.

## Rust Book and Contract References

Use the Book's [ownership chapter](../../resources/languages/rust/rust-book/src/ch04-00-understanding-ownership.md), [lifetime chapter](../../resources/languages/rust/rust-book/src/ch10-03-lifetime-syntax.md), [panic guidance](../../resources/languages/rust/rust-book/src/ch09-03-to-panic-or-not-to-panic.md), and [interior mutability chapter](../../resources/languages/rust/rust-book/src/ch15-05-interior-mutability.md) for foundational explanations. `Rc<RefCell<T>>` is explicitly useful for shared mutable single-threaded data; assess its discipline rather than prohibiting the combination.

Resolve language-rule questions with the [Reference](https://doc.rust-lang.org/reference/), library preconditions with [std documentation](https://doc.rust-lang.org/std/), migrations with the [Edition Guide](https://doc.rust-lang.org/edition-guide/), and stabilization with [release announcements](https://blog.rust-lang.org/). Keep the [2027 watchlist](modernization.md#2027-watchlist) separate from supported stable behavior.
