---
paths: "**/*.go, **/go.mod"
---

# Go Concurrency

Goroutines, channels, context, synchronization, and deterministic testing.

---

## Core Guidelines

### Goroutines Only for Concurrent Work

**A goroutine is not a speed-up. It's a structural choice that says: this work can proceed independently.**

```go
// ✓ CORRECT: genuine concurrency — these I/O calls are independent
func fetchAll(ctx context.Context, urls []string) ([]Response, error) {
    g, ctx := errgroup.WithContext(ctx)
    results := make([]Response, len(urls))
    for i, u := range urls {
        g.Go(func() error {
            r, err := fetch(ctx, u)
            if err != nil {
                return err
            }
            results[i] = r
            return nil
        })
    }
    if err := g.Wait(); err != nil {
        return nil, err
    }
    return results, nil
}

// ✘ WRONG: CPU-bound work spread over a goroutine-per-item with no bound
for _, x := range items {
    go compute(x)   // leak risk, no ordering, no error propagation
}
```

### Always Scope Goroutines — No Fire-and-Forget

**Every goroutine needs an answer to two questions: who waits for it, and who cancels it?** If you can't answer both, you have a leak.

```go
// ✓ CORRECT: ctx cancels, WaitGroup/errgroup waits
var wg sync.WaitGroup
wg.Add(1)
go func() {
    defer wg.Done()
    pollUntil(ctx)
}()
// ... eventually:
cancel()
wg.Wait()

// ✘ WRONG: no cancellation path, no wait — ghost goroutine
go func() {
    for {
        time.Sleep(time.Second)
        doThing()
    }
}()
```

**Prefer structured concurrency primitives** (`errgroup.Group`, `sync.WaitGroup`) over bare goroutines. They make the wait/cancel structure explicit.

### `context.Context` Propagation

**`context.Context` is the first parameter of every function that does I/O, blocks, or calls another context-aware function.**

```go
// ✓ CORRECT: ctx threaded through
func (c *Client) GetUser(ctx context.Context, id int) (*User, error) {
    req, err := http.NewRequestWithContext(ctx, "GET", c.url(id), nil)
    if err != nil {
        return nil, err
    }
    return c.do(ctx, req)
}

// ✘ WRONG: swallowing ctx or creating a new background inside
func (c *Client) GetUser(id int) (*User, error) {
    ctx := context.Background()   // caller can no longer cancel
    // ...
}
```

**Rules:**
- `ctx context.Context` is always the **first** parameter, never a struct field (exception: long-lived values explicitly holding a context for lifecycle, like servers).
- Never pass `nil` — use `context.TODO()` when truly unknown.
- Don't store contexts for later — they carry a deadline and a cancellation.
- Use `context.WithTimeout` / `context.WithDeadline` at the boundary where latency matters (HTTP handler, RPC call), not at the call site of every function.

### Channels for Communication, Mutexes for State

Go Proverb: *"Don't communicate by sharing memory; share memory by communicating."* In practice, both have their place.

```go
// ✓ Channel — producer/consumer, pipeline stage, cancellation signal
work := make(chan Job, 10)
go producer(work)
for job := range work {
    process(job)
}

// ✓ Mutex — shared data with localized access
type Counter struct {
    mu sync.Mutex
    n  int
}
func (c *Counter) Inc() { c.mu.Lock(); c.n++; c.mu.Unlock() }
```

**Heuristic:** if the value flows from one place to another, use a channel. If multiple goroutines read/write the same cell, use a mutex.

**Common channel mistakes:**

```go
// ✘ Unbuffered channel with no receiver — deadlock
ch := make(chan int)
ch <- 1   // blocks forever

// ✘ Sending on a closed channel — panic
close(ch)
ch <- 1

// ✘ Double close — panic
close(ch); close(ch)

// ✓ Only the sender closes; receivers use `v, ok := <-ch` or `for range ch`
```

### `sync.OnceFunc` / `OnceValue` / `OnceValues` (Go 1.21+)

**Stop hand-rolling `sync.Once` closures.**

```go
// ✘ OLD pattern — works but verbose
var (
    cfgOnce sync.Once
    cfg     *Config
    cfgErr  error
)

func getConfig() (*Config, error) {
    cfgOnce.Do(func() {
        cfg, cfgErr = loadConfig()
    })
    return cfg, cfgErr
}

// ✓ Go 1.21+ — concurrency-safe memoization in one line
var getConfig = sync.OnceValues(loadConfig)

// For side-effect-only:
var initLogger = sync.OnceFunc(func() {
    slog.SetDefault(slog.New(...))
})
```

`go fix` migrates the old pattern automatically.

### Loop Variables — Go 1.22+ Scope Fix

**Before Go 1.22, loop variables were shared across iterations.** After 1.22, each iteration gets its own copy. Delete shadow-copy workarounds.

```go
// ✓ Go 1.22+: each iteration has its own x — no workaround needed
for _, x := range xs {
    go process(x)
}

// ✘ Obsolete — delete this pattern in 1.22+ codebases
for _, x := range xs {
    x := x           // no longer necessary
    go process(x)
}
```

`go fix` removes these shadow copies automatically.

### Structured Concurrency with `errgroup`

**`golang.org/x/sync/errgroup` is the standard structured-concurrency primitive.** It bundles a `WaitGroup`, a shared cancellation context, and first-error propagation.

```go
// ✓ errgroup: cancel all on first error, wait for all to finish
func processAll(ctx context.Context, items []Item) error {
    g, ctx := errgroup.WithContext(ctx)
    g.SetLimit(8)   // bound concurrency
    for _, item := range items {
        g.Go(func() error {
            return process(ctx, item)
        })
    }
    return g.Wait()   // first non-nil error, or nil
}
```

For deduplication of concurrent identical work, use `golang.org/x/sync/singleflight`.

### Never Hold a Lock Across I/O or Channel Sends

**Locks are for short critical sections. Any operation that can block — I/O, `<-ch`, `ch <- v`, `time.Sleep` — should happen *outside* the lock.**

```go
// ✘ WRONG: HTTP call under the mutex blocks every other caller
func (c *Cache) Get(key string) (*Value, error) {
    c.mu.Lock()
    defer c.mu.Unlock()
    if v, ok := c.data[key]; ok {
        return v, nil
    }
    return c.fetch(key)   // network call holds the lock — disaster under load
}

// ✓ CORRECT: look up under lock, fetch outside, update under lock
func (c *Cache) Get(key string) (*Value, error) {
    c.mu.RLock()
    v, ok := c.data[key]
    c.mu.RUnlock()
    if ok {
        return v, nil
    }
    v, err := c.fetch(key)   // no lock held
    if err != nil {
        return nil, err
    }
    c.mu.Lock()
    c.data[key] = v
    c.mu.Unlock()
    return v, nil
}
```

For the "avoid thundering-herd fetches" part of this pattern, use `singleflight`.

### Deterministic Concurrency Tests with `testing/synctest`

**`testing/synctest` (experimental in Go 1.24, GA in 1.25)** gives you a fake clock and goroutine scheduler so concurrent tests become deterministic — no `time.Sleep`, no flakes.

```go
// ✓ Deterministic test — no real time passes, no sleeps
import "testing/synctest"

func TestCacheExpiry(t *testing.T) {
    synctest.Run(func() {
        c := NewCache(5 * time.Second)
        c.Set("k", "v")
        time.Sleep(4 * time.Second)
        synctest.Wait()   // wait for all goroutines to block
        if _, ok := c.Get("k"); !ok {
            t.Fatal("should still be present")
        }
        time.Sleep(2 * time.Second)
        synctest.Wait()
        if _, ok := c.Get("k"); ok {
            t.Fatal("should have expired")
        }
    })
}
```

Inside `synctest.Run`, `time.Now`, `time.Sleep`, and timer-based code run against a virtual clock that advances only when all goroutines are blocked on time-based operations.

---

## Summary

- **DO** give every goroutine a waiter and a canceller
- **DO** thread `context.Context` as the first parameter of every blocking/I/O function
- **DO** use `errgroup.Group` for structured concurrency
- **DO** use `sync.OnceFunc` / `OnceValue` / `OnceValues` instead of hand-rolled `sync.Once`
- **DO** delete `x := x` shadow copies in Go 1.22+ code
- **DO** use `testing/synctest` for deterministic concurrent tests
- **DO** use channels for flow, mutexes for shared state
- **DON'T** fire-and-forget goroutines — they leak
- **DON'T** store `context.Context` in struct fields (with narrow exceptions)
- **DON'T** hold a lock across I/O or channel operations
- **DON'T** close channels from the receiver side — only the sender closes

---

## Related Files

- [test.md](test.md) - `testing/synctest`, `t.Context()`, concurrent test patterns
- [modernization.md](modernization.md) - `sync.OnceFunc` migration, loop-variable fix
- [errors.md](errors.md) - `errors.Join` for multi-goroutine error aggregation

## References

- [Effective Go — Concurrency](https://go.dev/doc/effective_go#concurrency)
- [Go Memory Model](https://go.dev/ref/mem) - Happens-before rules
- [context package](https://pkg.go.dev/context) - Cancellation and deadlines
- [errgroup](https://pkg.go.dev/golang.org/x/sync/errgroup) - Structured concurrency
- [singleflight](https://pkg.go.dev/golang.org/x/sync/singleflight) - Coalesce duplicate calls
- [testing/synctest](https://pkg.go.dev/testing/synctest) - Deterministic concurrent testing
- [Go 1.22 loop-variable change](https://go.dev/blog/loopvar-preview) - Scope fix rationale
- [Share memory by communicating](https://go.dev/blog/codelab-share) - Proverb explained
