---
paths: "**/*.go, **/go.mod, **/go.work"
---

# Go Testing

Test observable contracts and failure modes with the native `testing` package. Keep each test's setup, action, and assertions understandable. Choose tables when cases share a structure; separate tests can be clearer when the behavior or setup differs.

## Organization and assertions

Put tests next to the package in `_test.go` files. External test packages such as `client_test` exercise exported APIs. Same-package tests can directly check a private algorithm or invariant. Export visibility alone does not determine whether a test is valuable.

Put fixtures and fuzz seeds under `testdata/`; the Go command ignores that directory when discovering packages. Use `t.Helper` in helpers so failures point to their callers. Use `Fatal` when a failed precondition makes later assertions invalid, and `Error` for independent failures. Include inputs, observed values, and expected values in diagnostics.

```go
package example

import (
	"strings"
	"testing"
)

func TestCut(t *testing.T) {
	tests := []struct {
		name, input, key, value string
		found                   bool
	}{
		{"pair", "mode=fast", "mode", "fast", true},
		{"empty value", "mode=", "mode", "", true},
		{"no separator", "mode", "mode", "", false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			key, value, found := strings.Cut(test.input, "=")
			if key != test.key || value != test.value || found != test.found {
				t.Errorf("Cut(%q) = (%q, %q, %t), want (%q, %q, %t)",
					test.input, key, value, found, test.key, test.value, test.found)
			}
		})
	}
}
```

Variables declared by the loop have per-iteration instances with the Go 1.22+ language semantics. Older module language versions and variables assigned with `=` need separate consideration; see [modernization.md](modernization.md).

Use ordinary comparisons when they explain the contract. A structural comparison library can improve diagnostics for complicated values. Avoid assertions about incidental formatting or iteration order unless that is what the API promises. `FailNow`, `Fatal`, and helpers that use them must run in the test goroutine; return worker failures to it for reporting.

## Cleanup and context lifetime

Use `t.TempDir` for temporary files and `t.Cleanup` to register cleanup that runs after the test and its subtests complete, in reverse registration order. Handle resource-close errors according to the resource's contract. Ordinary function defers run earlier, when their function returns.

`t.Context`, introduced in Go 1.24, is canceled just before cleanup callbacks run. Workers must observe cancellation; it does not terminate them automatically. Join workers in cleanup when they depend on that automatic cancellation:

```go
package example

import "testing"

func TestWorkerShutdown(t *testing.T) {
	ctx := t.Context()
	done := make(chan struct{})
	go func() {
		defer close(done)
		<-ctx.Done()
	}()
	t.Cleanup(func() { <-done })
}
```

An ordinary defer waiting for `done` would block before the automatic cancellation in this arrangement. Use `context.WithCancel(t.Context())` when the test needs to trigger cancellation earlier. Register resource and worker cleanup in an order that preserves their lifetime dependencies.

Parallel tests must isolate mutable state. Go's `os.Setenv` implementation synchronizes access, but tests can still overwrite each other's process environment. Use `t.Setenv` for restoration and obey its prohibition on parallel tests or tests with parallel ancestors. Avoid sharing mutable fixtures merely to save setup code.

## Virtual-time concurrency tests

The stable `testing/synctest` API, available since Go 1.25, uses `synctest.Test`. The earlier experimental `Run` API is no longer the stable entry point. Each Test creates a bubble containing its test goroutine and the goroutines started within it.

Go 1.27's `synctest.Sleep` combines sleeping with waiting for other goroutines to become durably blocked. On Go 1.25–1.26, use `time.Sleep` followed by `synctest.Wait` for that sequence.

```go
package example

import (
	"context"
	"testing"
	"testing/synctest"
	"time"
)

func TestDeadline(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		ctx, cancel := context.WithTimeout(t.Context(), time.Hour)
		defer cancel()

		synctest.Sleep(time.Hour - time.Nanosecond)
		if err := ctx.Err(); err != nil {
			t.Fatalf("before deadline: %v", err)
		}
		synctest.Sleep(time.Nanosecond)
		if err := ctx.Err(); err != context.DeadlineExceeded {
			t.Fatalf("at deadline: %v, want %v", err, context.DeadlineExceeded)
		}
	})
}
```

The bubble's fake clock advances when all goroutines in it are durably blocked. Certain channel operations, `Cond.Wait`, associated `WaitGroup.Wait`, and sleeps qualify. Mutex acquisition, ordinary external I/O, and system calls do not. `Wait` waits for the other goroutines in the bubble to become durably blocked. Keep tests self-contained; use a fake network where appropriate. Go 1.27's `httptest.NewTestServer` supports an in-memory network suitable for this use.

Use explicit synchronization before reading shared state. A fake clock does not repair data races or make all scheduling deterministic. Run the race detector on relevant tests as well. [Stable synctest contract](https://pkg.go.dev/testing/synctest@go1.27.1), [NewTestServer](https://pkg.go.dev/net/http/httptest@go1.27.1#NewTestServer)

## Benchmarks

Prefer `B.Loop` for ordinary sequential benchmarks on Go 1.24+. It handles the timing boundary around setup and cleanup and protects the loop body from certain unwanted optimizations. Keep the exact `for b.Loop()` form. Setup inside the loop is still measured unless the timer is explicitly stopped.

```go
package example

import (
	"strconv"
	"testing"
)

func BenchmarkParse(b *testing.B) {
	input := "123456789"
	b.ReportAllocs()
	for b.Loop() {
		if _, err := strconv.ParseInt(input, 10, 64); err != nil {
			b.Fatal(err)
		}
	}
}
```

`b.N` remains supported and can still be appropriate. Parallel benchmarks use `b.RunParallel` and `pb.Next`; do not mechanically replace those with `B.Loop`. Choose the benchmark unit to match the question, and report toolchain, platform, workload, and allocation measurements. [Benchmark API](https://pkg.go.dev/testing@go1.27.1#B.Loop)

## Fuzz contracts, including normalization

Fuzz parsers and codecs using properties their APIs promise. When a parser accepts multiple spellings, reformatting may produce a canonical spelling rather than the original bytes. Check the parsed value's round-trip instead:

```go
package example

import (
	"strconv"
	"testing"
)

func FuzzInteger(f *testing.F) {
	f.Add("00123")
	f.Add("-7")
	f.Add("")
	f.Fuzz(func(t *testing.T, input string) {
		value, err := strconv.ParseInt(input, 10, 64)
		if err != nil {
			return
		}
		canonical := strconv.FormatInt(value, 10)
		roundTrip, err := strconv.ParseInt(canonical, 10, 64)
		if err != nil || roundTrip != value {
			t.Fatalf("round trip of %q via %q = %d, %v; want %d", input, canonical, roundTrip, err, value)
		}
	})
}
```

Ordinary `go test` executes seed cases; active fuzzing needs `-fuzz` and can use a bounded `-fuzztime`. Preserve useful minimized failure cases as regression inputs. Review their content before committing them. [Fuzzing documentation](https://go.dev/doc/security/fuzz/)

## Fakes and golden files

A small fake often makes an interface's expected behavior clearer than a generated mock. Interface satisfaction comes from method sets, not from the implementation having a usable zero value. Make a fake's ownership, error, and concurrency behavior match what its consumers rely on. Generated mocks can be appropriate when they improve a test's clarity.

Use golden files for substantial outputs whose exact representation is contractual. Make updates explicit and check the write error. Do not run update mode concurrently against the same fixture.

```go
package example

import (
	"os"
	"testing"
)

func checkGolden(t *testing.T, path, got string, update bool) {
	t.Helper()
	if update {
		if err := os.WriteFile(path, []byte(got), 0o644); err != nil {
			t.Fatalf("update golden %q: %v", path, err)
		}
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read golden %q: %v", path, err)
	}
	if got != string(want) {
		t.Errorf("golden %q: got %q, want %q", path, got, want)
	}
}
```

Large-output comparisons may benefit from a focused diff instead of printing every byte. Do not regenerate expected output merely to silence a failure; verify that the contract changed intentionally.

Related guidance: [concurrency](concurrency.md), [errors](errors.md), [quality](quality.md), and [resources](resources.md). The [`testing` package](https://pkg.go.dev/testing@go1.27.1) defines cleanup, parallelism, and test-goroutine requirements.
