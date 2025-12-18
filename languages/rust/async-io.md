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
    }).await?
}
```

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

**Use `async_trait` or return `impl Future` (Rust 1.75+).**

```rust
// Rust 1.75+: Native async in traits (with limitations)
trait AsyncReader {
    async fn read(&mut self) -> Result<Vec<u8>, Error>;
}

// Or with async_trait crate (more flexible)
use async_trait::async_trait;

#[async_trait]
trait AsyncService {
    async fn call(&self, request: Request) -> Response;
}

#[async_trait]
impl AsyncService for MyService {
    async fn call(&self, request: Request) -> Response {
        // implementation
    }
}
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
- **NEVER** forget timeouts on network operations
- **DO** use async only for I/O-bound operations
- **DO** use `spawn_blocking` for CPU-bound or blocking work
- **DO** use `JoinSet` for structured concurrency
- **DO** document cancellation safety
- **DO** prefer `async fn` over manual futures
- **DON'T** use raw `spawn` without tracking tasks

---

## Related

- [errors.md](errors.md) - Error handling in async contexts
- [traits.md](traits.md) - Async traits

## References

- [Tokio Tutorial](https://tokio.rs/tokio/tutorial)
- [Async Book](https://rust-lang.github.io/async-book/)
- [Tokio Select](https://tokio.rs/tokio/tutorial/select)
