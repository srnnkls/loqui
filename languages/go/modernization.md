---
paths: "**/*.go, **/go.mod, **/go.work"
---

# Go Modernization

Baseline: Go 1.27, checked with Go 1.27.1 on 14 September 2026. Choose modern facilities by their contracts, and verify unfamiliar APIs with the installed documentation and compiler. Generated code deserves the same checks as handwritten code.

## Toolchain and compatibility

Use a supported patch toolchain for development. Decide the module's minimum version separately: raising its `go` directive changes the contract for consumers. A compiler upgrade alone does not require that change. File build constraints can also affect the language/API baseline used by tools. See [modules.md](modules.md).

Check the environment before migrating:

```sh
go version
go env GOVERSION GOTOOLCHAIN GOWORK
go doc errors.AsType
```

Use [release notes](https://go.dev/doc/devel/release) and the [source catalog](resources.md) to verify feature availability. Do not reject a released feature merely because an older guide omits it.

## Applying go fix

Go 1.26 rebuilt `go fix` around analyzers for code modernization. Inspect the analyzers in the installed toolchain; their names and coverage can change between releases.

```sh
go tool fix help
go tool fix help any
go fix -diff ./...
```

`-diff` previews changes without writing source. It exits with status 1 when a patch is available, so account for that in automation. Review the preview, then apply the intended fixes from a clean or otherwise clearly isolated working state:

```sh
go fix ./...
git diff
go test ./...
go vet ./...
```

Select an analyzer with a flag named after it, or disable one with its boolean flag:

```sh
go fix -diff -any ./...
go fix -any ./...
go fix -diff -any=false ./...
```

Do not use the legacy `-fix=name` syntax to select a current analyzer. On Go 1.27.1 that obsolete flag is ignored with a warning, and the default suite can still modify unrelated code.

The Go 1.27.1 suite includes `any`, `forvar`, `errorsastype`, `newexpr`, `stringsseq`, `waitgroupgo`, and other specific analyzers. It does not include a Once conversion, a `tools.go` to tool-directive migration, or `slicesclone`. The `fmtappendf` analyzer present in Go 1.26 was removed in Go 1.27. Treat the installed help as authoritative for selection.

Fixers are designed to preserve behavior, but overlapping transformations can require manual repair. A run covers selected packages in the active build configuration and skips fixes touching generated files. Check other supported build tags and platforms when they contain affected code. Change a generator when generated output needs modernization.

The source-level inliner uses `//go:fix inline` directives for supported API migrations. It only reaches analyzed call sites; it does not guarantee migration of every platform-specific file or every downstream consumer. Preserve public compatibility while consumers update. [Go fix usage and limitations](https://go.dev/blog/gofix)

## Match replacement semantics

The table lists candidates, not unconditional substitutions. The version identifies availability, not a requirement to rewrite otherwise suitable code.

| Facility                                 | Since | Conditions to preserve                                                                                                                                                         |
| ---------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `strings.Cut`                            | 1.18  | Splits at the first separator; check the found result.                                                                                                                         |
| `fmt.Appendf`                            | 1.19  | Appends to existing bytes and may allocate. Use a fresh destination if the previous code created a fresh result.                                                               |
| `errors.Join`, multiple `%w`             | 1.20  | Preserve error identity, formatting expectations, and intentional exposure of causes. See [errors.md](errors.md).                                                              |
| `slices.Sort` / `SortFunc`               | 1.21  | Mutates the slice. Preserve ordering and stability requirements; use stable sorting when required.                                                                             |
| `slices.Clone` / `maps.Clone`            | 1.21  | Shallow copies. Nilness and references nested inside elements remain part of the contract.                                                                                     |
| Sort plus `slices.Compact`               | 1.21  | Deduplicates adjacent equal elements after sorting; changes order and storage. A set may still be the right data structure.                                                    |
| `min` / `max`                            | 1.21  | Floating-point NaN/infinity behavior differs from `math.Min`/`math.Max` in some cases.                                                                                         |
| `clear`                                  | 1.21  | Clears a map or zeros slice elements. Clearing a map also removes NaN keys that an equality-based delete loop cannot remove.                                                   |
| `cmp.Ordered`                            | 1.21  | Includes strings and ordered numeric types, not complex numbers or every desired numeric constraint.                                                                           |
| Once helpers                             | 1.21  | Cache results and errors; repeat panics on later calls, unlike `Once.Do`. See [concurrency.md](concurrency.md).                                                                |
| `log/slog`                               | 1.21  | Preserve required logging levels, fields, handlers, and output behavior.                                                                                                       |
| `cmp.Or`                                 | 1.22  | Chooses the first non-zero argument. Arguments are evaluated before the call; this is not lazy fallback evaluation.                                                            |
| `math/rand/v2`                           | 1.22  | Recheck seeding and reproducibility contracts. Use `crypto/rand` for security-sensitive randomness.                                                                            |
| Range-over-function, `iter`, `maps.Keys` | 1.23  | Define errors, order, lifetime, restartability, and mutation. Map iteration does not promise order.                                                                            |
| `unique.Make`                            | 1.23  | Canonicalizes comparable values through handles. Measure benefits and keep handle/value lifetime semantics clear.                                                              |
| `structs.HostLayout`                     | 1.23  | Requests host ABI layout; it is not a field-packing optimizer and does not recursively change other struct layouts.                                                            |
| Generic aliases, tool directives         | 1.24  | Aliases preserve type identity; tool directives change module dependency management.                                                                                           |
| `strings.SplitSeq` / `FieldsSeq`         | 1.24  | Useful when only traversal is needed; a materialized slice can suit repeated access better.                                                                                    |
| `t.Context`, `B.Loop`                    | 1.24  | Preserve cancellation timing, worker joins, and the benchmark's measurement unit. See [test.md](test.md).                                                                      |
| `os.Root`                                | 1.24  | Provides traversal-resistant directory-relative operations, not a complete process sandbox. Follow platform and resource-lifetime contracts.                                   |
| `runtime.AddCleanup`                     | 1.24  | Cleanup may be delayed or never run before process exit. Avoid retaining the object through the cleanup closure or argument; use explicit close for bounded resource lifetime. |
| Stable `synctest.Test`                   | 1.25  | Use the bubble's durable-blocking rules; fake time does not repair arbitrary races or external I/O timing.                                                                     |
| `WaitGroup.Go`                           | 1.25  | Joins callbacks that must not panic; adds neither cancellation nor error propagation.                                                                                          |
| `new(expr)`, `errors.AsType`             | 1.26  | Initialized pointers and typed error extraction; preserve the operation's data and error contracts.                                                                            |

One small counterexample explains why numerical replacements need care:

```go
package example

import (
	"fmt"
	"math"
)

func Example() {
	negativeInfinity, nan := math.Inf(-1), math.NaN()
	fmt.Println(math.Min(negativeInfinity, nan))
	fmt.Println(min(negativeInfinity, nan))
	// Output:
	// -Inf
	// NaN
}
```

Similarly, `slices.Clone` of a nil slice stays nil, whereas appending it to a non-nil empty slice produces a non-nil result. Preserve observable nilness when serialization or callers distinguish it. These are API semantics, not reasons to avoid modern functions when their behavior fits.

## Loop semantics since Go 1.22

The change gives variables declared by the loop a distinct instance each iteration. It matters when retaining an address or capturing a variable in a closure. Variables declared outside the loop and assigned with `=` are still shared.

```go
package example

import "fmt"

func Example() {
	var declared []func() int
	for _, value := range []int{1, 2, 3} {
		declared = append(declared, func() int { return value })
	}

	var assigned []func() int
	var value int
	for _, value = range []int{1, 2, 3} {
		assigned = append(assigned, func() int { return value })
	}

	fmt.Println(declared[0](), declared[1](), declared[2]())
	fmt.Println(assigned[0](), assigned[1](), assigned[2]())
	// Output:
	// 1 2 3
	// 3 3 3
}
```

With the older language semantics, the first row would also be `3 3 3`. By contrast, `go process(value)` evaluates `value` before the goroutine begins, including before Go 1.22. Remove shadow copies only where they are redundant under the effective language version and the actual capture pattern; the `forvar` analyzer handles eligible cases.

## Stable Go 1.27 additions

Generic methods can declare their own type parameters; interface methods cannot. The complete example and restriction are in [generics.md](generics.md). `go test` also runs the `stdversion` vet check by default, reinforcing the distinction between the installed compiler and a module's declared API baseline. [Go 1.27 release notes](https://go.dev/doc/go1.27)

`encoding/json/v2` and `encoding/json/jsontext` are stable in Go 1.27. v2 uses stricter defaults, including rejecting duplicate object names and invalid UTF-8. v1 remains supported. A migration must account for data compatibility and the behavior options, rather than replacing an import mechanically. [JSON v2 API](https://pkg.go.dev/encoding/json/v2@go1.27.1)

```go
package example

import (
	jsonv1 "encoding/json"
	jsonv2 "encoding/json/v2"
	"fmt"
)

func Example() {
	input := []byte(`{"name":"first","name":"second"}`)
	var legacy, strict map[string]string
	oldErr := jsonv1.Unmarshal(input, &legacy)
	newErr := jsonv2.Unmarshal(input, &strict)
	fmt.Println(oldErr == nil, newErr != nil)
	// Output: true true
}
```

For tests, `synctest.Sleep` combines fake sleep and waiting for quiescence, and `httptest.NewTestServer` offers an in-memory network suitable for synctest. See [test.md](test.md).

The stable `goroutineleak` profile identifies a class of permanently blocked goroutines through reachability analysis. It can miss leaks whose blocking objects remain reachable, so it supplements lifecycle design and tests rather than proving their completeness. [Go 1.27 runtime changes](https://go.dev/doc/go1.27#runtime)

## Performance and experimental work

Go 1.26 enabled the Green Tea garbage collector by default. Go 1.27 adds allocation improvements. Treat published benchmark percentages as workload-dependent observations; measure the application before promising a benefit. [Go 1.26 runtime changes](https://go.dev/doc/go1.26#runtime), [Go 1.27 runtime changes](https://go.dev/doc/go1.27#runtime)

As of 14 September 2026, portable `simd` remains experimental behind `GOEXPERIMENT=simd`. Keep experimental APIs separate from a stable compatibility promise. [SIMD experiment](https://go.dev/doc/go1.27)

For a 2027 planning horizon, follow Go 1.28 development and subsequent release notes. The six-month release cadence suggests February and August release windows, not guaranteed feature dates. Extensible analyzer sidecars remain an open backlog item; do not document them as installed `go fix` functionality. [Release cycle](https://go.dev/wiki/Go-Release-Cycle), [Go 1.28 development](https://github.com/golang/go/issues/79581), [analysis-sidecar discussion](https://github.com/golang/go/issues/59869)

Related guidance: [modules](modules.md), [quality](quality.md), and the versioned [source catalog](resources.md).
