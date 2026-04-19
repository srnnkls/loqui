---
paths: "**/*.go, **/go.mod"
---

# Go Testing

Test organization, table-driven tests, helpers, benchmarks, fuzzing, and deterministic concurrency testing.

---

## Core Guidelines

### Test Organization

**Tests live next to production code, in a `_test.go` file in the same package.**

```
internal/github/
├── client.go
├── client_test.go       # white-box: package github
├── export_test.go       # optional: expose unexported for tests
└── testdata/            # golden files, fixtures — Go ignores this dir
    └── sample.json
```

**White-box vs black-box:**

```go
// White-box — same package, can access unexported identifiers
package github
func TestParseInternal(t *testing.T) { ... }

// Black-box — _test suffix, only uses public API
package github_test
import "example.com/internal/github"
func TestClient_Public(t *testing.T) { ... }
```

Prefer black-box (`_test` suffix) for tests of the public contract — it enforces that your package is usable through exported API only. Use white-box when you genuinely need to poke at internals.

The `testdata/` directory is Go-compiler-magical: it's excluded from the build. Put fixtures, golden files, and input corpora there.

### Table-Driven Tests with `t.Run`

**The canonical Go test pattern: a table of cases, each executed as a subtest.**

```go
// ✓ CORRECT: table + t.Run per case
func TestParsePRRef(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    PRRef
        wantErr bool
    }{
        {"full reference", "owner/repo#123", PRRef{"owner", "repo", 123}, false},
        {"missing number", "owner/repo", PRRef{}, true},
        {"empty", "", PRRef{}, true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := ParsePRRef(tt.input)
            if (err != nil) != tt.wantErr {
                t.Fatalf("err = %v, wantErr %v", err, tt.wantErr)
            }
            if got != tt.want {
                t.Errorf("got %+v, want %+v", got, tt.want)
            }
        })
    }
}
```

**Why:** subtests show per-case pass/fail, support `-run TestParsePRRef/empty` filtering, and isolate state. The `name` field should be a short prose description, not `case1`/`case2`.

**Note (Go 1.22+):** loop-variable-per-iteration scope means you no longer need `tt := tt` inside the loop. Delete the shadow copy.

### Test Helpers: `t.Helper()`, `t.Cleanup()`, `t.TempDir()`

```go
// ✓ t.Helper: error points at the caller, not the helper
func assertOK(t *testing.T, got, want string) {
    t.Helper()
    if got != want {
        t.Errorf("got %q, want %q", got, want)
    }
}

// ✓ t.Cleanup: runs in LIFO order on test exit (including failure)
func setupDB(t *testing.T) *DB {
    t.Helper()
    db := openTestDB(t)
    t.Cleanup(func() { db.Close() })
    return db
}

// ✓ t.TempDir: auto-cleanup, unique per test
func TestWriteConfig(t *testing.T) {
    dir := t.TempDir()
    writeConfig(filepath.Join(dir, "config.yaml"))
    // no manual cleanup; dir is removed after the test
}
```

### `t.Context()` (Go 1.24+)

**Use `t.Context()` instead of building a fresh `context.Background` in every test.** It's cancelled on `t.Cleanup`, so goroutines spawned from the test exit automatically.

```go
// ✓ Go 1.24+: test-scoped context with automatic cancellation
func TestClient_Do(t *testing.T) {
    ctx := t.Context()
    got, err := client.Do(ctx, req)
    // when the test returns, ctx is cancelled for you
}

// ✘ OLD pattern — manual cancellation boilerplate
func TestClient_Do(t *testing.T) {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()
    // ...
}
```

### Benchmarks with `testing.B.Loop` (Go 1.24+)

**`testing.B.Loop` replaces the `b.N` loop idiom.** The old pattern had footguns: setup inside the loop inflated measurements, and `b.ResetTimer` was easy to forget.

```go
// ✓ Go 1.24+: Loop handles timer and setup boundary for you
func BenchmarkParse(b *testing.B) {
    data := readLargeInput(b)   // setup: not timed
    b.ReportAllocs()
    for b.Loop() {
        if _, err := Parse(data); err != nil {
            b.Fatal(err)
        }
    }
}

// ✘ OLD pattern — still works but verbose and error-prone
func BenchmarkParse(b *testing.B) {
    data := readLargeInput(b)
    b.ResetTimer()
    b.ReportAllocs()
    for i := 0; i < b.N; i++ { ... }
}
```

Keep a single hot operation per benchmark. Use `b.Run(name, ...)` for sub-benchmarks and `b.StopTimer`/`b.StartTimer` around any in-loop setup.

### Fuzzing

**Fuzz tests surface edge cases automatically.** Use them for parsers, codecs, string manipulation, and anything taking untrusted input.

```go
// ✓ Fuzz test — runs forever with `go test -fuzz=FuzzParse`
func FuzzParsePRRef(f *testing.F) {
    // Seed corpus — representative inputs
    f.Add("owner/repo#123")
    f.Add("")
    f.Add("only-one-slash/")

    f.Fuzz(func(t *testing.T, input string) {
        got, err := ParsePRRef(input)
        if err == nil {
            // Round-trip invariant: a successfully parsed ref must re-serialize to itself
            if got.String() != input {
                t.Errorf("round-trip mismatch: %q → %+v → %q", input, got, got.String())
            }
        }
        // Must not panic regardless of input — the fuzz target itself asserts that.
    })
}
```

Failing inputs are saved under `testdata/fuzz/FuzzParsePRRef/` and become regression cases. Commit them.

### Deterministic Concurrent Tests with `testing/synctest`

**Experimental in Go 1.24, GA in 1.25.** `testing/synctest` eliminates `time.Sleep` and flakiness from time-dependent concurrent tests.

```go
import "testing/synctest"

func TestRateLimiter(t *testing.T) {
    synctest.Run(func() {
        lim := NewRateLimiter(10, time.Second)
        for range 10 {
            if !lim.Allow() {
                t.Fatal("should allow first 10")
            }
        }
        if lim.Allow() {
            t.Fatal("should rate-limit the 11th")
        }
        time.Sleep(time.Second)   // virtual time
        synctest.Wait()
        if !lim.Allow() {
            t.Fatal("should allow after window resets")
        }
    })
}
```

`synctest.Wait()` blocks until every goroutine in the bubble is idle — no sleep-and-pray, no flakes.

### Test Doubles: Hand-Written Fakes, Not Mocks

**Go's zero-value interface satisfaction makes hand-written fakes trivial.** Prefer them over mocking frameworks.

```go
// ✓ Hand-written fake — readable, maintainable, no reflection
type fakeStore struct {
    data map[string][]byte
    err  error   // injectable for error-path tests
}

func (f *fakeStore) Save(key string, v []byte) error {
    if f.err != nil { return f.err }
    if f.data == nil { f.data = map[string][]byte{} }
    f.data[key] = v
    return nil
}

func (f *fakeStore) Load(key string) ([]byte, error) {
    if f.err != nil { return nil, f.err }
    v, ok := f.data[key]
    if !ok { return nil, ErrNotFound }
    return v, nil
}

// Usage
store := &fakeStore{}
svc := NewService(store)
// ... then inspect store.data for assertions
```

**When mocks are appropriate:** large interfaces with many methods where most are irrelevant per test. Use `go.uber.org/mock` with generated mocks in those cases — never hand-roll mocks with `gomock.Call{...}` literals.

### Assertions: Stdlib First, `testify` When It Reads Better

Go's testing package is intentionally spartan. Use `t.Errorf` for most checks; reach for `github.com/stretchr/testify/require` only when it demonstrably improves the diagnostic.

```go
// ✓ Plain stdlib — perfectly fine
if got != want {
    t.Errorf("got %d, want %d", got, want)
}

// ✓ testify when the assertion is nontrivial
require.ElementsMatch(t, got, want)   // order-insensitive list compare
require.JSONEq(t, expected, actual)   // structural JSON compare
```

**`require` vs `assert`:** `require` fails-fast (`t.FailNow`), `assert` continues. Use `require` for preconditions (setup succeeded), `assert` only when you want multiple independent checks on one object.

### Golden Files for Large Fixtures

**When expected output is larger than a few lines, store it in `testdata/` and compare.**

```go
// ✓ Golden-file pattern
func TestRender(t *testing.T) {
    got := Render(input)

    goldPath := filepath.Join("testdata", "render.golden")
    if *update {
        os.WriteFile(goldPath, []byte(got), 0644)
    }
    want, err := os.ReadFile(goldPath)
    if err != nil { t.Fatal(err) }
    if got != string(want) {
        t.Errorf("output differs from golden; re-run with -update to regenerate")
    }
}

var update = flag.Bool("update", false, "update golden files")
```

---

## Anti-Patterns

```go
// ✘ time.Sleep for synchronization — flake magnet
time.Sleep(100 * time.Millisecond)   // use channels or synctest

// ✘ Testing unexported helpers directly — tests the implementation, not the behavior
func TestInternal_helper(t *testing.T) { ... }

// ✘ Shared mutable fixtures across tests — order-dependent, parallel-hostile
var sharedState *State
func TestA(t *testing.T) { sharedState.Do() }
func TestB(t *testing.T) { sharedState.Do() }

// ✘ t.Parallel without considering shared deps
func TestA(t *testing.T) {
    t.Parallel()
    os.Setenv("X", "1")   // concurrent env mutation — data race
}

// ✘ Loose assertions that don't localize failure
if !reflect.DeepEqual(got, want) { t.Fail() }   // gives no diagnostic
```

---

## Summary

- **DO** use table-driven tests with `t.Run` per case
- **DO** use `t.Helper()`, `t.Cleanup()`, `t.TempDir()`, `t.Context()` (1.24+)
- **DO** use `testing.B.Loop` (1.24+) for benchmarks — skip `b.N`/`b.ResetTimer`
- **DO** fuzz parsers and codecs
- **DO** use `testing/synctest` for concurrent/time-dependent tests
- **DO** prefer hand-written fakes over mocking frameworks
- **DO** store fixtures in `testdata/`
- **DON'T** use `time.Sleep` for synchronization
- **DON'T** test unexported helpers — test behavior through the public API
- **DON'T** share mutable state across tests
- **DON'T** use `reflect.DeepEqual` without a diagnostic — compare fields or use `cmp.Diff`

---

## Related Files

- [concurrency.md](concurrency.md) - `testing/synctest` patterns in depth
- [modernization.md](modernization.md) - `t.Context()`, `testing.B.Loop` migration
- [errors.md](errors.md) - Testing error-returning functions

## References

- [testing package](https://pkg.go.dev/testing) - Stdlib reference
- [testing/synctest](https://pkg.go.dev/testing/synctest) - Deterministic concurrent tests
- [Fuzzing tutorial](https://go.dev/doc/tutorial/fuzz) - Official fuzz intro
- [Go 1.24 release notes — testing](https://go.dev/doc/go1.24#testing) - `t.Context`, `B.Loop`
- [Table-driven tests](https://go.dev/wiki/TableDrivenTests) - Canonical pattern
- [testify](https://github.com/stretchr/testify) - `require`/`assert` helpers
