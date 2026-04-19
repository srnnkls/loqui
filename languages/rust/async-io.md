---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Async I/O

Async/await patterns, tokio, concurrency, and I/O guidelines.

## Core Guidelines

### Async Only for I/O-Bound Operations

**Don't use async for CPU-bound work.**

```rust
// ✓ CORRECT: Async for I/O
async fn fetch_data(url: &str) -> Result<String, Error> {
    let response = reqwest::get(url).await?;
    response.text().await
}

// ✓ CORRECT: CPU work on blocking thread pool
async fn process_image(data: Vec<u8>) -> Result<Vec<u8>, Error> {
    tokio::task::spawn_blocking(move || {
        // CPU-intensive work runs on blocking thread
        expensive_image_processing(&data)
    }).await?
}

// ✘ WRONG: CPU work blocking the async runtime
async fn bad_process(data: &[u8]) -> Vec<u8> {
    expensive_computation(data)  // Blocks executor thread!
}
```

### Never Block the Async Runtime

**Use `spawn_blocking` for blocking operations.**

```rust
// ✘ WRONG: Blocking I/O in async context
async fn bad_read_file(path: &Path) -> Result<String, Error> {
    std::fs::read_to_string(path)  // Blocks the executor!
}

// ✓ CORRECT: Use async file I/O
async fn read_file(path: &Path) -> Result<String, Error> {
    tokio::fs::read_to_string(path).await
}

// ✓ CORRECT: Or spawn_blocking for std I/O
async fn read_file_blocking(path: PathBuf) -> Result<String, Error> {
    tokio::task::spawn_blocking(move || {
        std::fs::read_to_string(&path)
    }).await??  // Outer ? propagates JoinError, inner ? propagates io::Error
}
```

### Avoid Holding Locks Across `.await`

**Standard `Mutex` guards block other tasks on the same executor thread.**

```rust
use std::sync::Mutex;

// ✘ WRONG: Lock held across await point
async fn bad_update(state: &Mutex<State>) {
    let mut guard = state.lock().unwrap();
    let data = fetch_data().await;  // Other tasks on this thread can't acquire lock!
    guard.value = data;
}

// ✓ CORRECT: Scope the lock, then await
async fn good_update(state: &Mutex<State>) {
    let current = state.lock().unwrap().value.clone();  // Lock released here
    let data = fetch_data_based_on(current).await;
    state.lock().unwrap().value = data;  // Re-acquire briefly
}

// ✓ OK: tokio::sync::Mutex when you genuinely need lock across await
use tokio::sync::Mutex as AsyncMutex;

async fn async_mutex_update(state: &AsyncMutex<State>) {
    let mut guard = state.lock().await;
    guard.value = fetch_data().await;  // Allowed, but consider if you really need this
}  // Caution: holding locks across await can cause contention
```

Prefer restructuring to scope locks tightly. Use `tokio::sync::Mutex` only when the lock genuinely must span an await—it has higher overhead than `std::sync::Mutex`.

### Always Set Timeouts

**Every async I/O operation should have a timeout.**

```rust
use tokio::time::{timeout, Duration};

// ✓ CORRECT: Explicit timeout
async fn fetch_with_timeout(url: &str) -> Result<String, Error> {
    let response = timeout(
        Duration::from_secs(30),
        reqwest::get(url)
    ).await??;

    timeout(
        Duration::from_secs(60),
        response.text()
    ).await?
}

// ✘ WRONG: No timeout, can hang forever
async fn fetch_no_timeout(url: &str) -> Result<String, Error> {
    let response = reqwest::get(url).await?;
    response.text().await
}
```

### Structured Concurrency with JoinSet

**Prefer `JoinSet` over raw `spawn` for managing concurrent tasks.**

```rust
use tokio::task::JoinSet;

// ✓ CORRECT: Structured concurrency
async fn fetch_all(urls: Vec<String>) -> Vec<Result<String, Error>> {
    let mut set = JoinSet::new();

    for url in urls {
        set.spawn(async move {
            fetch_data(&url).await
        });
    }

    let mut results = Vec::new();
    while let Some(result) = set.join_next().await {
        results.push(result.unwrap_or_else(|e| Err(e.into())));
    }
    results
}

// ✘ FRAGILE: Raw spawns, harder to track
async fn fetch_all_raw(urls: Vec<String>) {
    for url in urls {
        tokio::spawn(async move {
            fetch_data(&url).await
        });
        // Tasks are orphaned, no way to await them all
    }
}
```

### Use `select!` Carefully

**Handle all branches, consider cancellation safety.**

```rust
use tokio::select;

// ✓ CORRECT: Proper select with cancellation handling
async fn fetch_or_timeout(url: &str) -> Result<String, Error> {
    let fetch = fetch_data(url);
    let timeout = tokio::time::sleep(Duration::from_secs(30));

    select! {
        result = fetch => result,
        _ = timeout => Err(Error::Timeout),
    }
}

// Document cancellation behavior
/// Fetches data with a deadline.
///
/// # Cancellation Safety
///
/// If the timeout fires first, the fetch is cancelled mid-flight.
/// No partial data is returned.
async fn documented_fetch(url: &str) -> Result<String, Error> {
    // ...
}
```

### Prefer `async fn` Over Manual Futures

**Use `async fn` unless you need specific lifetime control.**

```rust
// ✓ PREFERRED: async fn
async fn process(data: &str) -> Result<Output, Error> {
    // implementation
}

// ✓ OK: When you need to name the future type
fn process_named(data: &str) -> impl Future<Output = Result<Output, Error>> + '_ {
    async move {
        // implementation
    }
}

// ✓ OK: When lifetime elision doesn't work
fn process_explicit<'a>(data: &'a str) -> impl Future<Output = &'a str> + 'a {
    async move { data }
}
```

### Async Trait Methods

**Default to native `async fn` in traits (stable since Rust 1.75).** Only reach for `#[async_trait]` when you need `dyn Trait`.

```rust
// ✓ CORRECT: native async fn in traits — no macros, no boxed futures
trait AsyncReader {
    async fn read(&mut self) -> Result<Vec<u8>, Error>;
}

// Use when concrete types are known at compile time (static dispatch).
async fn consume<R: AsyncReader>(mut r: R) -> Result<(), Error> {
    let bytes = r.read().await?;
    // ...
    Ok(())
}

// ✓ Keep #[async_trait] only when you need dyn dispatch
use async_trait::async_trait;

#[async_trait]
trait DynService: Send + Sync {
    async fn call(&self, request: Request) -> Response;
}

fn register(svc: Box<dyn DynService>) { /* ... */ }
```

**Why the split:** native `async fn` returns an anonymous `impl Future`, which doesn't fit in a `dyn Trait` vtable. `#[async_trait]` works around this by boxing the future — with allocation overhead. For static dispatch (the common case), native is strictly better. For dynamic dispatch, you still need `#[async_trait]` or `trait-variant`.

See [traits.md](traits.md) for the full discussion.

### Async Closures (Rust 1.85+)

**`async ‖ { … }` creates an async closure that can capture environment references across `.await` points.** A regular closure that returns an `async { … }` block can't.

```rust
// ✓ CORRECT: higher-order async function taking an async closure
async fn retry<F, T>(f: F) -> T
where
    F: AsyncFn() -> T,
{
    loop {
        if let Ok(v) = std::panic::AssertUnwindSafe(f()).await {
            return v;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

// Call with an async closure — captures `state` by reference across awaits
let state = load_state();
retry(async || fetch_with(&state).await).await;
```

The three new trait flavors:

- `AsyncFnOnce` — consumes captured state on first call
- `AsyncFnMut` — mutates captured state between calls
- `AsyncFn` — borrows captured state immutably

Prefer async closures over `Fn() -> impl Future` boilerplate when you need to capture references across awaits.

### Axum 0.8 Handler Style (January 2025)

**Axum 0.8 dropped the `#[async_trait]` requirement from handlers and extractors** thanks to native `async fn` in traits. Handlers are now just `async fn`s that take extractors and return an `IntoResponse`.

```rust
use axum::{routing::get, Router, extract::State, Json};
use std::sync::Arc;

#[derive(Clone)]
struct AppState {
    db: Arc<dyn Database + Send + Sync>,
}

async fn get_user(State(state): State<AppState>) -> Json<User> {
    Json(state.db.fetch(1).await)
}

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/user", get(get_user))
        .with_state(AppState { db: Arc::new(Pg::new()) });

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
```

Migration from 0.7 is mostly mechanical: drop `#[async_trait]` annotations from custom extractors and `FromRequestParts` impls; the compiler flags the rest.

### Actor Pattern with Tokio Channels

**For shared mutable state in async code, prefer an actor (owned-state + channel) over a `Mutex` on hot paths.** The actor holds the state exclusively; callers send commands; no lock contention.

```rust
use tokio::sync::{mpsc, oneshot};

enum Cmd {
    Inc,
    Get(oneshot::Sender<u64>),
}

async fn counter_actor(mut rx: mpsc::Receiver<Cmd>) {
    let mut count = 0u64;
    while let Some(cmd) = rx.recv().await {
        match cmd {
            Cmd::Inc => count += 1,
            Cmd::Get(tx) => { let _ = tx.send(count); }
        }
    }
}

// Callers hold only the Sender — no shared data, no lock.
#[derive(Clone)]
struct CounterHandle {
    tx: mpsc::Sender<Cmd>,
}

impl CounterHandle {
    pub fn new() -> Self {
        let (tx, rx) = mpsc::channel(64);
        tokio::spawn(counter_actor(rx));
        Self { tx }
    }
    pub async fn inc(&self) { let _ = self.tx.send(Cmd::Inc).await; }
    pub async fn get(&self) -> u64 {
        let (tx, rx) = oneshot::channel();
        let _ = self.tx.send(Cmd::Get(tx)).await;
        rx.await.unwrap_or(0)
    }
}
```

**When to use actor vs `tokio::sync::Mutex`:** use actor when operations are naturally sequential (counter, state machine, coordinated writes). Use `RwLock`/`Mutex` when operations are genuinely concurrent-read (cache lookups, configuration).

### OS Pipes with `std::io::pipe` (Rust 1.87+)

Stdlib `std::io::pipe()` replaces ad-hoc pipe crates:

```rust
let (mut reader, mut writer) = std::io::pipe()?;
std::thread::spawn(move || {
    let _ = writer.write_all(b"hello");
});
let mut buf = String::new();
reader.read_to_string(&mut buf)?;
```

### Channel Patterns

**Use appropriate channel types for the use case.**

```rust
use tokio::sync::{mpsc, oneshot, broadcast};

// mpsc: Multiple producers, single consumer
async fn worker_pool() {
    let (tx, mut rx) = mpsc::channel::<Task>(100);

    // Spawn workers
    tokio::spawn(async move {
        while let Some(task) = rx.recv().await {
            process(task).await;
        }
    });
}

// oneshot: Single response
async fn request_response() {
    let (tx, rx) = oneshot::channel();

    tokio::spawn(async move {
        let result = compute().await;
        let _ = tx.send(result);
    });

    let result = rx.await?;
}

// broadcast: Multiple consumers, all receive
async fn pub_sub() {
    let (tx, _rx) = broadcast::channel::<Event>(100);

    // Each subscriber gets all messages
    let mut rx1 = tx.subscribe();
    let mut rx2 = tx.subscribe();
}
```

## Summary

- **NEVER** block the async runtime with sync I/O or CPU work
- **AVOID** holding `std::sync::Mutex` guards across `.await`
- **NEVER** forget timeouts on network operations
- **DO** use async only for I/O-bound operations
- **DO** use `spawn_blocking` for CPU-bound or blocking work
- **DO** use `JoinSet` for structured concurrency
- **DO** document cancellation safety
- **DO** prefer `async fn` over manual futures
- **DO** use native `async fn` in traits (1.75+); keep `#[async_trait]` only for `dyn`
- **DO** use async closures (`async ‖ {}`, 1.85+) when you need to capture references across awaits
- **DO** prefer the actor pattern over `Mutex` for sequential shared state
- **DON'T** use raw `spawn` without tracking tasks
- **DON'T** carry `#[async_trait]` forward in 2024-edition code unless you need `dyn`

---

## Related

- [errors.md](errors.md) - Error handling in async contexts
- [traits.md](traits.md) - Async traits

## References

- [Tokio Tutorial](https://tokio.rs/tokio/tutorial)
- [Async Book](https://rust-lang.github.io/async-book/)
- [Tokio Select](https://tokio.rs/tokio/tutorial/select)
- [Async closures — Rust 1.85 release notes](https://blog.rust-lang.org/2025/02/20/Rust-1.85.0.html)
- [Announcing Axum 0.8](https://tokio.rs/blog/2025-01-01-announcing-axum-0-8-0) - No more `#[async_trait]` for handlers
- [Actors with Tokio](https://ryhl.io/blog/actors-with-tokio/) - Canonical actor pattern write-up
- [trait-variant crate](https://docs.rs/trait-variant/) - Native + `dyn` bridging
