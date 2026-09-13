---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Async I/O

Async allows tasks to yield while waiting. Design the executor workload, task ownership, deadlines, and cancellation behavior together. The examples below use Tokio 1.x with the features they exercise enabled; see the [vendored source catalog](resources.md).

## Keep Blocking Work off Executor Threads

Small computations belong inside async functions when useful. Sustained CPU work and blocking calls can prevent other tasks from progressing. Use async I/O APIs, or move blocking operations to `spawn_blocking`:

```rust
use std::{error::Error, path::PathBuf};

type ReadError = Box<dyn Error + Send + Sync>;

async fn read_file(path: PathBuf) -> Result<String, ReadError> {
    let contents = tokio::task::spawn_blocking(move || {
        std::fs::read_to_string(path)
    }).await??;
    Ok(contents)
}
```

The first `?` handles `JoinError`; the second handles the I/O error. After both, the value is a `String`, so a `Result<String, _>` function must return `Ok(contents)`. `tokio::fs::read_to_string(path).await` is the simpler option when its interface fits.

Limit the concurrency of CPU-heavy work, using a semaphore or a dedicated compute pool where appropriate. Tokio's blocking pool can grow substantially; `spawn_blocking` is not an automatic CPU scheduling policy. A blocking task that has started cannot generally be stopped by aborting its handle. See [Tokio's implementation and contract](../../resources/languages/rust/tokio/tokio/src/task/blocking.rs).

## Keep Lock Scopes Deliberate

A standard mutex is often appropriate for short, uncontended access that does not span `.await`. Give the guard a lexical scope so its release is visible:

```rust
use std::sync::Mutex;

async fn observe(state: &Mutex<String>) -> String {
    let snapshot = {
        state.lock().expect("state mutex is not poisoned").clone()
    };
    tokio::task::yield_now().await;
    snapshot
}
```

A snapshot can become stale while a task awaits. Reacquiring the lock to commit a result requires checking the state again if concurrent updates matter. Splitting the critical section is not automatically behavior-preserving.

Use `tokio::sync::Mutex` when an async operation needs a guard across suspension or when asynchronous acquisition is otherwise required. It avoids blocking the executor while waiting for the lock, but still serializes access. Review contention, reentrancy, and cancellation paths.

## Deadlines and Cancellation

Set a deadline where the operation's contract needs bounded waiting. Prefer a shared overall deadline when repeated per-step timeouts could exceed the caller's budget. Long-lived subscriptions may instead use explicit shutdown.

```rust
use tokio::time::{timeout, Duration, error::Elapsed};

async fn with_timeout<T>(operation: impl Future<Output = T>) -> Result<T, Elapsed> {
    timeout(Duration::from_secs(30), operation).await
}
```

Timeouts are cooperative: an operation that does not yield can run past the deadline. Dropping a future does not roll back completed effects or automatically stop work already spawned elsewhere. Decide what partial progress, retries, and cleanup mean for the operation.

When a branch completes, Tokio's `select!` drops the other futures it owns. Selecting on a mutable reference to a pinned future instead leaves that underlying future alive. Whether recreating a future loses data depends on the operation's contract:

```rust
use tokio::sync::{mpsc, oneshot};

async fn receive_or_stop(
    receiver: &mut mpsc::Receiver<u32>,
    stop: oneshot::Receiver<()>,
) -> Option<u32> {
    tokio::select! {
        message = receiver.recv() => message,
        _ = stop => None,
    }
}
```

`mpsc::Receiver::recv` is cancellation-safe here. Operations such as `read_exact` and `write_all` can make partial progress before cancellation; restarting them can lose that progress. Canceling a pending channel `send(value)` drops the owned value with the future, unlike a completed `Err(SendError(value))`. Consider reserving capacity before transferring ownership when losing the value is unacceptable. Consult [Tokio's `select!` documentation](../../resources/languages/rust/tokio/tokio/src/macros/select.rs) and [bounded channel source](../../resources/languages/rust/tokio/tokio/src/sync/mpsc/bounded.rs).

## Track and Bound Spawned Tasks

Keep handles when results, errors, or shutdown matter. `JoinSet` is useful for a group with shared lifetime and completion-order results; a single `JoinHandle` can be sufficient for one task. This example bounds the number of active tasks:

```rust
use std::num::NonZeroUsize;
use tokio::task::{JoinError, JoinSet};

async fn lengths(
    names: Vec<String>,
    concurrency: NonZeroUsize,
) -> Result<Vec<usize>, JoinError> {
    let mut input = names.into_iter();
    let mut tasks = JoinSet::new();
    let mut output = Vec::new();

    loop {
        while tasks.len() < concurrency.get() {
            let Some(name) = input.next() else { break };
            tasks.spawn(async move {
                tokio::task::yield_now().await;
                name.len()
            });
        }
        let Some(result) = tasks.join_next().await else { break };
        match result {
            Ok(length) => output.push(length),
            Err(error) => {
                tasks.shutdown().await;
                return Err(error);
            }
        }
    }
    Ok(output)
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let mut result = lengths(vec!["a".into(), "abc".into()], NonZeroUsize::new(2).unwrap())
        .await.unwrap();
    result.sort_unstable();
    assert_eq!(result, [1, 3]);
}
```

Dropping a `JoinSet` requests abortion of its tasks; that does not synchronously wait for their termination. `shutdown().await` waits after requesting abortion, subject to the tasks' cancellation behavior. Add a cooperative shutdown protocol when work needs to finish or flush state. If output order matters, retain input indices instead of relying on completion order.

## Async Trait Contracts and Spawn

The receiver being `Send + Sync` does not make a native async trait method's future `Send`. A generic spawn path needs a future bound in the trait:

```rust
trait Service: Sync {
    fn fetch(&self) -> impl Future<Output = String> + Send;
}

struct Greeting(String);
impl Service for Greeting {
    async fn fetch(&self) -> String { self.0.clone() }
}

fn spawn_fetch<S>(service: S) -> tokio::task::JoinHandle<String>
where
    S: Service + Send + 'static,
{
    tokio::spawn(async move { service.fetch().await })
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let result = spawn_fetch(Greeting(String::from("hello"))).await.unwrap();
    assert_eq!(result, "hello");
}
```

For a `dyn` interface, use a boxed-future contract or `async-trait`. `trait-variant` can generate `Send` variants, but does not provide dynamic dispatch for native async methods. See [traits](traits.md#async-methods-decide-the-future-contract) before removing a macro from an existing public API.

Prefer `async fn` for ordinary async functions. `fn -> impl Future` is useful for explicit bounds, capture control, or eager setup before constructing a future; it still returns an opaque type rather than giving the future a public concrete name.

## Async Closures and Retries

`async || { ... }` creates an async closure. The `AsyncFn`, `AsyncFnMut`, and `AsyncFnOnce` traits model shared, mutable, and consuming calls. They can express lending relationships that a regular `FnMut` returning one fixed future type cannot. Ordinary closures can still return futures that borrow externally owned data; borrowing across `.await` is not exclusive to async closures.

A retry callback returning `Result<T, E>` needs that result type in its bound. Bound the attempts and decide which errors are retryable:

```rust
use std::num::NonZeroUsize;
use tokio::time::{sleep, Duration};

async fn retry<F, T, E>(
    mut operation: F,
    attempts: NonZeroUsize,
    should_retry: impl Fn(&E) -> bool,
) -> Result<T, E>
where
    F: AsyncFnMut() -> Result<T, E>,
{
    let mut remaining = attempts.get();
    loop {
        match operation().await {
            Ok(value) => return Ok(value),
            Err(error) => {
                remaining -= 1;
                if remaining == 0 || !should_retry(&error) {
                    return Err(error);
                }
                sleep(Duration::from_millis(100)).await;
            }
        }
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let text = String::from("hello");
    let result = retry(async || Ok::<_, ()>(text.as_str()), NonZeroUsize::new(3).unwrap(), |_| true)
        .await.unwrap();
    assert_eq!(result, "hello");
}
```

This retries returned errors. `AssertUnwindSafe` only asserts an unwind-safety property; it does not catch panics. A production retry policy also needs to account for idempotency, total deadlines, cancellation, and appropriate backoff.

## Channels and Owned State

Choose a channel for the communication contract:

| Channel        | Contract                                                                  |
| -------------- | ------------------------------------------------------------------------- |
| Bounded `mpsc` | Multiple senders, one receiver, backpressure at capacity                  |
| `oneshot`      | One response or cancellation when the sender disappears                   |
| `broadcast`    | Multiple subscribers; slow receivers can report lag and miss old messages |
| `watch`        | Latest state; intermediate updates may be coalesced                       |

An actor owns mutable state and processes commands sequentially. This can clarify ownership and coordinate operations, but message queues still introduce waiting and overhead. A mutex can be simpler for short shared-state access. Return send/receive failures instead of disguising a stopped actor as a valid default result:

```rust
use tokio::sync::oneshot;

async fn request_response() -> Result<u64, oneshot::error::RecvError> {
    let (sender, receiver) = oneshot::channel();
    let worker = tokio::spawn(async move {
        // A dropped receiver means the caller no longer needs this response.
        let _ = sender.send(42);
    });
    let result = receiver.await;
    worker.await.expect("response task must not panic");
    result
}
```

An `mpsc` receiver is not a multi-consumer worker pool by itself. Define how work is dispatched and how tasks are joined. Preserve the unsent command when a failed send makes recovery useful, as in [Tokio's `SendError<T>`](../../resources/languages/rust/tokio/tokio/src/sync/mpsc/error.rs).

## Framework-Specific APIs

Check a framework's current trait bounds and migration guide before adapting handlers or extractors. Axum 0.8 removed `async-trait` from extractor implementations; ordinary async handlers predate that change. It did not make application-defined native async database traits dyn-compatible. See [Axum's 0.8 announcement](https://tokio.rs/blog/2025-01-01-announcing-axum-0-8-0).

## Related

- [Ownership](ownership.md): ownership transfer, scoped threads, and `'static`
- [Traits](traits.md): native and boxed futures
- [Errors](errors.md): recovery contracts
- [Tokio source reading path](resources.md)
