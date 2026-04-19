---
paths: "**/*.go, **/go.mod"
---

# Go Modernization

Modern Go features (1.20 → 1.26), the `go fix` modernizers, and how to keep AI-generated code current.

---

## AI Drift Warning

**AI agents — this one included — systematically generate obsolete Go.** Two forces drive this:

1. **Training cutoff.** A model's weights freeze at some date; anything landed in Go after that date is literally unknown.
2. **Frequency bias.** Even for features the model *does* know, years of pre-generics Go in the training data outweigh the few months of modern idioms. The model defaults to what it has seen most often.

The practical effect: agents produce code that *compiles and passes tests* but uses patterns that have been superseded for years — `interface{}` where generics belong, hand-rolled multi-error types instead of `errors.Join`, `for i, x := range xs { x := x; ... }` shadow copies after 1.22 made them unnecessary, `tools.go` instead of `go.mod` tool directives.

**Mandatory habit for every code-gen session:**

```bash
# From a clean git state:
go fix ./...        # apply modernizers
go test ./...       # confirm nothing broke
git diff            # review the diff — it's usually obvious and safe
git commit
```

Run this **after every significant generation** — not just after toolchain upgrades. Modernizers are behavior-preserving by design, so the diff is easy to trust.

For Claude Code sessions, invoke the `go-modern-guidelines` skill (`/use-modern-go`) if available — it primes the model against frequency bias for the duration of the session.

---

## `go fix` Modernizers

Go 1.24 rewrote `go fix` to be the canonical, push-button home for code modernization. The command ships with dozens of *modernizers* that update a codebase to current language and standard-library idioms.

```bash
# Preview diffs without writing
go fix -diff ./...

# Apply fixes in place
go fix ./...

# Run a specific fixer only
go fix -fix=slicesclone ./...

# List available fixers for your toolchain
go fix -help
```

**What the fixer suite covers** (toolchain-dependent; the list grows with each release):

- Pre-generics patterns → generic `slices` / `maps` calls
- `sort.Slice` → `slices.SortFunc`
- Hand-rolled `for` search loops → `slices.Contains` / `slices.Index`
- Old `for i := 0; i < n; i++` counters → `for range n` (1.22)
- Shadow-copy `x := x` workarounds inside loops (obsolete since 1.22)
- `interface{}` → `any`
- `sync.Once` + closure → `sync.OnceFunc` / `OnceValue` (1.21)
- `tools.go` blank imports → `go.mod` tool directives (1.24)
- `ptr[T]` helpers / address-of-literal hacks → `new(expr)` (1.26)

**Source-level inliner.** Beyond the built-in modernizers, `go fix` now supports inlining your *own* API migrations: mark a deprecated function with `//go:fix inline` and provide a replacement; `go fix` rewrites every call site across a codebase. This is the correct tool for library migrations — far safer than a `gorename` script or ad-hoc `sed`.

---

## Stdlib-First Replacements

The 1.21–1.26 window moved a lot of ecosystem churn into stdlib. Before reaching for a third-party package, check whether stdlib now covers it.

| Old pattern | Modern replacement | Since |
|---|---|---|
| `hashicorp/go-multierror` | `errors.Join` | 1.20 |
| Single `%w` + manual concatenation | `fmt.Errorf` with multiple `%w` | 1.20 |
| Hand-rolled sort with `sort.Slice` | `slices.SortFunc` | 1.21 |
| `for _, x := range xs { if x == t ... }` | `slices.Contains` | 1.21 |
| `map[K]struct{}` sets for dedup | `slices.Compact` after sort | 1.21 |
| `math.Min` / `math.Max` | `min` / `max` builtins | 1.21 |
| `for k := range m { delete(m, k) }` | `clear(m)` | 1.21 |
| `log` package / 3rd-party loggers | `log/slog` | 1.21 |
| `sync.Once` + captured variables | `sync.OnceFunc` / `OnceValue` / `OnceValues` | 1.21 |
| Hand-written Ordered constraint | `cmp.Ordered` | 1.21 |
| Nested `if a != "" { return a } ... ` fallback | `cmp.Or` | 1.22 |
| `math/rand` with global seed | `math/rand/v2` | 1.22 |
| `x := x` inside range loops | Delete — 1.22 per-iteration scope fixes it | 1.22 |
| Returning `[]T` when caller only iterates | `iter.Seq[T]` / `iter.Seq2[K,V]` | 1.23 |
| Manual string interning | `unique.Make` | 1.23 |
| `tools.go` blank imports | `go.mod` tool directive | 1.24 |
| `context.WithCancel` in tests | `t.Context()` | 1.24 |
| `b.N` loops in benchmarks | `testing.B.Loop` | 1.24 |
| Concurrent tests with `time.Sleep` | `testing/synctest` | 1.24 (exp), 1.25 (GA) |
| `ptr := func[T any](v T) *T { return &v }` | `new(expr)` | 1.26 |

---

## Language Feature Tour

### Go 1.20 (Feb 2023)

- **`errors.Join`** — combine multiple errors into one value; `errors.Is` / `errors.As` walk the tree.
- **Multi-`%w` `fmt.Errorf`** — `fmt.Errorf("a: %w; b: %w", e1, e2)`.

### Go 1.21 (Aug 2023) — **major quality-of-life release**

```go
// Builtins
x := min(a, b, c)       // replaces math.Min in most cases
y := max(a, b)
clear(m)                // delete all map keys in one call
clear(s)                // zero all slice elements

// slices + maps packages
import "slices"
slices.Sort(xs)
slices.Contains(xs, target)
ys := slices.Clone(xs)
slices.SortFunc(users, func(a, b User) int { return cmp.Compare(a.Name, b.Name) })

import "maps"
keys := slices.Collect(maps.Keys(m))     // 1.23+ idiom; see iterators below
maps.Copy(dst, src)

// log/slog — stdlib structured logging
import "log/slog"
slog.Info("request", "method", r.Method, "path", r.URL.Path)

// sync.OnceFunc / OnceValue / OnceValues
var load = sync.OnceValue(func() *Config {
    return loadConfigOnce()
})
cfg := load()    // runs loader exactly once, concurrency-safe

// cmp.Ordered constraint for generics
func Max[T cmp.Ordered](a, b T) T { ... }
```

### Go 1.22 (Feb 2024)

```go
// Per-iteration loop variables — each iteration gets a new x
for _, x := range xs {
    go process(x)   // pre-1.22, this captured the shared x; now each goroutine sees its own
}
// Delete any x := x shadow copies in existing code.

// for range N — count without a counter variable
for range 5 {
    doThing()
}

// cmp.Or — fall-through to first non-zero value
name := cmp.Or(req.Name, user.Name, "anonymous")

// math/rand/v2 — better API, default is ChaCha8 (not deterministic global seed)
import "math/rand/v2"
n := rand.IntN(100)
```

### Go 1.23 (Aug 2024)

```go
// Range-over-function — iterators are first-class
func Lines(r io.Reader) iter.Seq[string] {
    return func(yield func(string) bool) {
        s := bufio.NewScanner(r)
        for s.Scan() {
            if !yield(s.Text()) {
                return
            }
        }
    }
}

for line := range Lines(r) {    // consume it like a slice
    fmt.Println(line)
}

// iter.Seq2 for key/value iteration
func Entries[K comparable, V any](m map[K]V) iter.Seq2[K, V] { ... }

// unique package for canonicalization
import "unique"
h := unique.Make("repeated string")  // all Make("repeated string") calls share storage
```

### Go 1.24 (Feb 2025)

```go
// Generic type aliases
type Ints = []int                   // was already allowed
type Pair[K, V any] = struct { K K; V V }   // NEW: generic alias

// go.mod tool directive (replaces tools.go)
tool github.com/golangci/golangci-lint/cmd/golangci-lint
// Then: go tool golangci-lint run

// testing.B.Loop — no more b.N book-keeping
func BenchmarkX(b *testing.B) {
    for b.Loop() {
        doWork()
    }
}

// t.Context() — test-scoped context, cancelled on t.Cleanup
func TestThing(t *testing.T) {
    ctx := t.Context()
    client.Do(ctx, ...)
}

// testing/synctest (experimental in 1.24, GA in 1.25)
// Deterministic fake clock + goroutine scheduling for concurrent code
synctest.Run(func() {
    go producer()
    synctest.Wait()   // until all goroutines block
    assertState(t)
})

// Swiss-table map internals — maps are now ~30% faster with no API change
// weak package — weak pointers for caches
```

### Go 1.25 (Aug 2025)

- `testing/synctest` graduated to GA (no more `GOEXPERIMENT=synctest`).
- Experimental green tea garbage collector (`GOEXPERIMENT=greenteagc`).
- Container-aware default `GOMAXPROCS` inside Linux cgroups.
- Runtime trace flight recorder for on-demand tracing in production.

### Go 1.26 (Feb 2026)

```go
// new() accepts expressions — no more ptr[T] helper
p := new(42)                        // *int pointing at 42
deadline := new(time.Now().Add(5 * time.Second))   // *time.Time

// Delete any utility like:
//   func ptr[T any](v T) *T { return &v }
// go fix can migrate automatically.

// Recursive generic type parameters — a type parameter can now reference itself
// in its own constraint, enabling cleaner builder/fluent patterns and self-referencing
// data structures.
```

---

## Upgrade Checklist

When bumping your toolchain:

```bash
# 1. Clean working tree — you want a reviewable diff
git status

# 2. Update go directive and toolchain
go mod edit -go=1.26

# 3. Apply all modernizers
go fix ./...

# 4. Verify nothing regressed
go test ./...
go vet ./...

# 5. Review and commit
git diff
git commit -m "chore: modernize to Go 1.26 idioms"
```

Repeat this after every toolchain bump and after any large AI-generated change.

---

## Summary

- **DO** run `go fix ./...` after every code-gen session and every toolchain upgrade
- **DO** prefer stdlib (`slices`, `maps`, `slog`, `errors.Join`, `cmp`) over third-party equivalents
- **DO** target the current Go toolchain; old idioms are a tax, not a compatibility win
- **DO** use `sync.OnceFunc` / `OnceValue`, not hand-rolled `sync.Once` closures
- **DO** replace `b.N` benchmark loops with `testing.B.Loop` (1.24+)
- **DO** use `t.Context()` in tests (1.24+) instead of building a fresh `context.Background`
- **DO** use `new(expr)` (1.26+) instead of `ptr[T]` helpers
- **DON'T** reach for `hashicorp/go-multierror` — `errors.Join` exists
- **DON'T** keep `tools.go` files — migrate to `go.mod` tool directives
- **DON'T** copy `x := x` shadowing patterns forward — Go 1.22 fixed the underlying issue
- **DON'T** trust AI-generated Go blindly — frequency bias pulls it toward obsolete patterns

---

## Related Files

- [generics.md](generics.md) - Type parameters, constraints, and when to prefer generics
- [concurrency.md](concurrency.md) - Modern concurrency primitives and `testing/synctest`
- [test.md](test.md) - `t.Context()`, `testing.B.Loop`, `testing/synctest`
- [errors.md](errors.md) - `errors.Join`, multi-`%w` wrapping
- [modules.md](modules.md) - `go.mod` tool directives, workspaces

## References

- [go fix documentation](https://pkg.go.dev/cmd/go#hdr-Update_packages_to_use_modern_features) - Modernizer command
- [Go release notes](https://go.dev/doc/devel/release) - Canonical per-version feature list
- [Go 1.20 release notes](https://go.dev/doc/go1.20) - `errors.Join`, multi-`%w`
- [Go 1.21 release notes](https://go.dev/doc/go1.21) - `slices`, `maps`, `slog`, `min`/`max`/`clear`
- [Go 1.22 release notes](https://go.dev/doc/go1.22) - Loop semantics, `for range N`
- [Go 1.23 release notes](https://go.dev/doc/go1.23) - Iterators, `iter.Seq`
- [Go 1.24 release notes](https://go.dev/doc/go1.24) - Tool directives, `testing.B.Loop`, generic aliases
- [log/slog blog post](https://go.dev/blog/slog) - Structured logging rationale
- [Range-over-func proposal](https://go.dev/blog/range-functions) - Iterator design
- [go-modern-guidelines (JetBrains)](https://github.com/JetBrains/go-modern-guidelines) - AI-drift mitigation
