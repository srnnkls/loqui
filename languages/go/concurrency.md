---
paths: "**/*.go, **/go.mod, **/go.work"
---

# Go Concurrency

Start with an operation's lifetime and invariants. Prefer a synchronous API when it lets the caller choose concurrency. Use goroutines for work that benefits from overlapping execution, and bound concurrency when resource use can grow with input size.

## Goroutine lifetimes

For background work, identify its owner, termination condition, and any required join. Cancellation is useful when a caller must stop work early; a bounded computation can simply return. A goroutine without a cancel function is not automatically a leak.

`sync.WaitGroup` joins work but does not propagate errors or cancel it. Since Go 1.25, `WaitGroup.Go` starts a function and tracks its completion. Its callback must not panic. When the group is empty, start work before calling `Wait`; do not copy a WaitGroup after first use.

```go
package example

import (
	"fmt"
	"sync"
)

func Example() {
	var workers sync.WaitGroup
	results := make([]int, 3)
	for i := range results {
		workers.Go(func() { results[i] = i * i })
	}
	workers.Wait()
	fmt.Println(results)
	// Output: [0 1 4]
}
```

Each goroutine writes a different element, and the caller reads results after the join. The loop uses Go 1.22+ per-iteration variables. Returning from `Wait` provides the synchronization; adding a goroutine by itself does not make shared memory safe.

For related tasks that return errors, `golang.org/x/sync/errgroup.WithContext` supplies a group and a derived context canceled on the first non-nil task error or when `Wait` returns. `Wait` still waits for all tasks; tasks must observe cancellation to stop early. Use `SetLimit` where appropriate, and account for `Go` blocking while that limit is full. Plain `errgroup.Group` does not create a cancellation context. [errgroup contract](https://pkg.go.dev/golang.org/x/sync/errgroup)

## Cooperative cancellation

Pass a `context.Context` as the first parameter when the operation supports deadlines, cancellation, or request-scoped values. Propagate an existing context into downstream context-aware calls. Do not silently replace it with `context.Background()` or pass nil.

A context parameter does not make a mutex acquisition or an ordinary `io.Reader.Read` cancelable. Use the actual API's cancellation, deadline, or documented close mechanism. Put timeouts where the latency budget is owned; child operations may derive shorter deadlines when their contracts require them.

Usually pass contexts explicitly rather than storing them in a struct. A long-lived object owning background work needs an explicit lifecycle design; storing a request context as incidental object state risks retaining values and applying stale deadlines.

```go
package example

import "context"

// Forward copies values until input closes or ctx is canceled.
// It does not close either caller-owned channel.
func Forward(ctx context.Context, input <-chan int, output chan<- int) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case value, ok := <-input:
			if !ok {
				return nil
			}
			select {
			case <-ctx.Done():
				return ctx.Err()
			case output <- value:
			}
		}
	}
}
```

If multiple select cases are ready, selection is not a cancellation-priority guarantee. Define whether a concurrent cancellation may race with one more successful operation. Call the cancel functions returned by `WithCancel`, `WithTimeout`, and `WithDeadline` when their scope ends.

## Channels and shared state

Use channels to coordinate communication and mutexes to protect shared invariants; both are ordinary Go tools. A channel value can still point to shared mutable data. See [composition.md](composition.md) for ownership at these boundaries.

The code that closes a channel must know that no more sends can occur. With one producer, that is usually the producer. With several producers, a coordinator can wait for all of them and then close it. Receivers commonly use `for range` or the two-result receive to detect closure. Sending on or closing an already closed channel panics. A nil channel blocks sends and receives and disables that select case.

Keep critical sections small where possible, but preserve serialization and state transitions. Some operations must hold a lock across I/O to prevent interleaved writes; Go's file-descriptor implementation does this. Moving a cache fetch outside a lock can change duplicate-fetch and invalidation behavior. Recheck the relevant state or use a generation/version protocol when required. `singleflight` suppresses overlapping work for a key; it is not a cache or a complete invalidation policy. [File-descriptor write source](https://github.com/golang/go/blob/go1.27.1/src/internal/poll/fd_unix.go)

## Once helpers and panic behavior

Use `sync.OnceFunc`, `OnceValue`, or `OnceValues` when their function-based memoization fits the API. They cache results, including errors; they are not retry mechanisms. A `sync.Once` field can be appropriate when initialization belongs to an object's state.

Their panic behavior differs: after a recovered panic, `Once.Do` considers the function completed and later calls return without invoking it. The helper functions repeat the panic value on subsequent calls. Preserve that distinction when migrating code. Go 1.27.1's `go fix` suite does not provide a Once conversion.

```go
package example

import (
	"errors"
	"fmt"
	"sync"
)

func Example() {
	calls := 0
	unavailable := errors.New("unavailable")
	load := sync.OnceValues(func() (string, error) {
		calls++
		return "", unavailable
	})
	_, first := load()
	_, second := load()
	fmt.Println(calls, errors.Is(first, unavailable), errors.Is(second, unavailable))
	// Output: 1 true true
}
```

## Pools and ownership

Use `sync.Pool` only when measurements justify reusing temporary objects. The runtime may discard any pooled item; it is not storage with a retention guarantee. A pool must not be copied after first use.

This pool stores only non-nil `*bytes.Buffer` values, so the internal assertion has a concrete invariant. Returning a buffer transfers it back to the pool: callers must stop using it and any slices that alias it. The example excludes large buffers rather than retaining their capacity indefinitely.

```go
package example

import (
	"bytes"
	"sync"
)

var buffers = sync.Pool{New: func() any { return new(bytes.Buffer) }}

func acquireBuffer() *bytes.Buffer {
	return buffers.Get().(*bytes.Buffer)
}

func releaseBuffer(buffer *bytes.Buffer) {
	if buffer == nil || buffer.Cap() > 64<<10 {
		return
	}
	buffer.Reset()
	buffers.Put(buffer)
}
```

A generic wrapper promising arbitrary `T` must also handle nil interfaces; a bare `Get().(T)` does not. Do not generalize this concrete example without carrying its representation and ownership guarantees into the new API.

## Loop variables and tests

Go 1.22 changed variables declared by a loop to have per-iteration instances. The effective language version comes from the module and applicable file constraints. Variables declared outside the loop and assigned with `=` remain shared. `go process(value)` evaluates its arguments before starting the goroutine in older versions too; closures and retained addresses are what distinguish the loop-variable change.

See [modernization.md](modernization.md) for a complete closure example. See [test.md](test.md) for stable `synctest.Test`, fake-clock behavior, `t.Context` cleanup ordering, and race detection. Fake time does not make arbitrary concurrent code deterministic or repair a data race.

The [`sync`](https://pkg.go.dev/sync@go1.27.1), [`context`](https://pkg.go.dev/context@go1.27.1), and [memory model](https://go.dev/ref/mem) contracts are authoritative. Additional source examples are cataloged in [resources.md](resources.md).
