---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Ownership

Ownership, borrowing, lifetimes, and patterns for working with the borrow checker.

## Core Guidelines

### Caller Decides Ownership

**Let the caller control where copies happen. Don't clone inside functions.**

```rust
// ✓ CORRECT: Take ownership when you need it
fn consume(value: String) {
    // use value as owned
}

// ✓ CORRECT: Borrow when you don't need ownership
fn inspect(value: &str) {
    // use value as borrowed
}

// ✘ WRONG: Borrow then clone inside
fn bad_consume(value: &String) {
    let owned = value.clone();  // Caller can't avoid this clone
    // use owned
}
```

The function signature should express the true ownership requirements.

### Prefer Borrowed Types in Arguments

**Use `&str` over `&String`, `&[T]` over `&Vec<T>`, `&T` over `&Box<T>`.**

```rust
// ✓ CORRECT: Accepts &str, &String, String slices
fn process(text: &str) {
    println!("{text}");
}

// ✘ WRONG: Only accepts &String
fn process_bad(text: &String) {
    println!("{text}");
}

fn main() {
    let owned = String::from("hello");
    let literal = "world";

    process(&owned);   // works
    process(literal);  // works

    // process_bad(literal);  // FAILS: &str doesn't coerce to &String
}
```

Borrowed types accept more input types through deref coercion.

### Never Clone to Satisfy the Borrow Checker

**If you're cloning to make the borrow checker happy, restructure your code instead.**

```rust
// ✘ WRONG: Clone to avoid borrow conflict
fn bad_update(data: &mut Data) {
    let key = data.current_key.clone();  // Clone to satisfy borrow checker
    data.map.insert(key, compute_value());
}

// ✓ CORRECT: Restructure to avoid the conflict
fn good_update(data: &mut Data) {
    let value = compute_value();  // Compute first
    data.map.insert(data.current_key.clone(), value);  // Or use entry API
}

// ✓ BETTER: Use entry API for maps
fn better_update(data: &mut Data) {
    data.map.entry(data.current_key.clone())
        .or_insert_with(compute_value);
}
```

Cloning hides the real problem. Fix the structure, not the symptom.

### Use `mem::take` and `mem::replace` for In-Place Mutation

**Extract owned values from mutable references without cloning.**

```rust
use std::mem;

enum State {
    Ready { data: String },
    Processing { data: String },
    Done,
}

// ✓ CORRECT: Use mem::take to move data out
fn transition(state: &mut State) {
    *state = match state {
        State::Ready { data } => State::Processing {
            data: mem::take(data),  // Takes data, leaves empty String
        },
        State::Processing { data } => {
            process(mem::take(data));
            State::Done
        }
        State::Done => State::Done,
    };
}

// ✘ WRONG: Clone to move data
fn bad_transition(state: &mut State) {
    *state = match state {
        State::Ready { data } => State::Processing {
            data: data.clone(),  // Unnecessary allocation
        },
        // ...
    };
}
```

`mem::take` replaces with `Default::default()`. Use `mem::replace` when you need a specific replacement value.

### Return Consumed Arguments on Error

**If a function consumes an argument and can fail, return the argument in the error.**

```rust
// ✓ CORRECT: Return the consumed value on error
pub fn send(message: Message) -> Result<(), SendError> {
    if can_send() {
        do_send(message);
        Ok(())
    } else {
        Err(SendError { message })  // Return ownership back
    }
}

pub struct SendError {
    pub message: Message,  // Caller can retry or recover
}

// Usage: retry pattern without extra clones
fn send_with_retry(mut msg: Message) -> Result<(), SendError> {
    for _ in 0..3 {
        msg = match send(msg) {
            Ok(()) => return Ok(()),
            Err(e) => e.message,  // Recover and retry
        };
    }
    Err(SendError { message: msg })
}
```

This pattern is used in `String::from_utf8` which returns the original bytes on error.

### Struct Decomposition for Independent Borrowing

**Split structs to allow borrowing different parts independently.**

```rust
// ✘ PROBLEM: Can't borrow input and output simultaneously
struct Processor {
    input: Vec<u8>,
    output: Vec<u8>,
}

impl Processor {
    fn process(&mut self) {
        // Can't do: self.output.extend(transform(&self.input));
        // because &mut self and &self.input conflict
    }
}

// ✓ SOLUTION: Decompose into separate structs
struct Input(Vec<u8>);
struct Output(Vec<u8>);

struct Processor {
    input: Input,
    output: Output,
}

impl Processor {
    fn process(&mut self) {
        // Now we can borrow input and output independently
        self.output.0.extend(transform(&self.input.0));
    }
}
```

The borrow checker tracks borrows at the field level within a single function.

### Use Explicit Lifetimes When They Aid Understanding

**Name lifetimes meaningfully in complex signatures.**

```rust
// ✓ CORRECT: Named lifetimes clarify relationships
fn parse<'input>(
    input: &'input str,
    config: &Config,
) -> Result<Document<'input>, Error> {
    // Document contains references into input
}

// ✓ CORRECT: Multiple lifetimes when genuinely different
fn merge<'a, 'b>(
    base: &'a Document,
    overlay: &'b Document,
) -> MergedView<'a, 'b> {
    // Result references both inputs
}

// ✘ AVOID: Meaningless single-letter lifetimes in complex cases
fn confusing<'a, 'b, 'c>(x: &'a Foo<'b>, y: &'c Bar) -> &'a Baz<'b, 'c>
```

Let lifetime elision handle simple cases. Add explicit lifetimes when the relationships matter.

### Prefer References Over Smart Pointers

**Use `Rc`/`Arc` only when shared ownership is genuinely needed.**

```rust
// ✓ CORRECT: Regular references for temporary sharing
fn process(data: &Data) {
    helper(data);
    another_helper(data);
}

// ✓ CORRECT: Rc when multiple owners must exist
struct Node {
    parent: Option<Weak<Node>>,
    children: Vec<Rc<Node>>,
}

// ✘ WRONG: Rc when a reference would suffice
fn bad_process(data: Rc<Data>) {
    helper(&data);  // Why Rc? A reference works fine
}

// ✘ WRONG: Rc<RefCell<T>> as a design crutch
struct OverEngineered {
    state: Rc<RefCell<State>>,  // Usually indicates design issue
}
```

`Rc<RefCell<T>>` everywhere usually means the ownership model needs rethinking.

## Summary

- **NEVER** clone to satisfy the borrow checker (restructure code instead)
- **NEVER** use `Rc<RefCell<T>>` as a default pattern (indicates design issue)
- **DO** let callers decide ownership (take or borrow based on need)
- **DO** use borrowed types in arguments (`&str`, `&[T]`, `&T`)
- **DO** use `mem::take`/`mem::replace` for in-place mutation
- **DO** return consumed arguments in error types
- **DO** decompose structs for independent borrowing
- **DO** use explicit lifetimes when they clarify relationships
- **DON'T** overuse `'static` (limits API flexibility)
- **DON'T** add lifetime parameters unnecessarily (let elision work)

---

## Related

- [types.md](types.md) - Designing types that encode ownership semantics
- [traits.md](traits.md) - Trait bounds and generic ownership patterns
- [errors.md](errors.md) - Error types that preserve ownership

## References

- [The Rust Book: Ownership](https://doc.rust-lang.org/book/ch04-00-understanding-ownership.html)
- [Rust API Guidelines: Flexibility](https://rust-lang.github.io/api-guidelines/flexibility.html)
- [Rust Design Patterns: mem::take](https://rust-unofficial.github.io/patterns/idioms/mem-replace.html)
