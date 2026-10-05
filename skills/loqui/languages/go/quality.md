---
paths: "**/*.go, **/go.mod, **/go.work"
---

# Go Quality

Make names, contracts, and control flow easy to read. Prefer the simplest implementation that meets the API's requirements, and use native tools to check it.

## Naming and organization

Use clear names suited to their scope. Short names work for short-lived indexes and familiar receivers; longer names help when values travel farther. Use consistent initialisms such as `HTTPClient`, `PRRef`, and `userID`. Receiver names should identify the type; a one- or two-letter abbreviation is common, not a hard length limit.

A property accessor is often called `Name` rather than `GetName`. Keyed lookup names such as `Get` can be meaningful, and setters are appropriate when mutation is part of the API. Prefer method names that express the operation and preserve invariants.

Keep related code together. Split a file when its responsibilities are easier to navigate separately, not merely because it crosses a fixed line count or contains a section comment. Prefer package names that convey a purpose over a growing `utils` collection. [modules.md](modules.md) covers package boundaries.

## Documentation is part of the API

Document exported packages, types, functions, and other names. Explain observable behavior: units, ownership, mutation, concurrency, errors, resource lifetime, and meaningful zero values. Internal packages can benefit from package documentation too. Put an extensive package overview in `doc.go`; a small package can put it in another source file.

Implementation comments should explain non-obvious decisions, invariants, or constraints. Avoid restating obvious syntax. This preference does not eliminate the need for API documentation about what an operation does.

```go
// Package snapshot provides independent byte snapshots of caller-owned data.
package snapshot

import "bytes"

// Copy returns an independent copy of data, preserving nil input as nil.
func Copy(data []byte) []byte {
	return bytes.Clone(data)
}
```

Names cannot communicate every aliasing or failure rule. Use an executable example when a short usage sequence makes the contract clearer. See [Go doc comments](https://go.dev/doc/comment) and the concrete storage contracts in [resources.md](resources.md).

## Zero values and construction

Make zero values useful when that fits the type. Nil slices support appending; a zero `sync.Mutex` is usable. A map must be initialized before assignment. A type needing a network client or validated configuration may reasonably require a constructor. Document the requirement and handle invalid construction deliberately.

Avoid copying values containing a used mutex, WaitGroup, or other no-copy synchronization state. Pointer receivers often support that design, but receiver consistency alone cannot prevent copying a containing struct. Follow [composition.md](composition.md).

## Standard-library choices and measurement

Check whether the standard library supplies the operation before adding a dependency. Match its semantics to the existing contract. `slices`, `maps`, `strings`, `cmp`, `errors`, and `log/slog` cover many useful cases; specialized dependencies can still provide necessary behavior.

`fmt.Appendf` appends formatted data to a byte slice. It may grow the buffer or allocate while formatting. Measure allocations for the intended buffer capacity and workload; it does not promise zero allocations.

```go
package example

import "fmt"

func Example() {
	buffer := make([]byte, 0, 64)
	buffer = append(buffer, "status: "...)
	buffer = fmt.Appendf(buffer, "version=%d", 27)
	fmt.Println(string(buffer))
	// Output: status: version=27
}
```

Use structured logging when callers need searchable fields and context. A logging migration should preserve levels, output contracts, and handler behavior. Do not log secrets or large payloads simply because structured fields make it convenient.

For access relative to a directory, Go 1.24's `os.Root` provides traversal-resistant operations. It enforces path containment through its APIs; it is not a complete process sandbox or authorization policy. Follow its platform restrictions, close the root and opened resources, and choose operations that preserve the intended file semantics. [Root contract](https://pkg.go.dev/os@go1.27.1#Root)

Report performance changes with the toolchain, platform, workload, and measurement method. A runtime benchmark improvement is not a guaranteed percentage for every application. Profile before adding pools, unsafe conversions, or architecture-specific code.

## Control flow and errors

Prefer early returns when they keep the successful path clear. Check errors before using invalid results. Named results can document meaning or allow deferred cleanup to amend an error; explicit return expressions are easier to follow in long functions.

Expected failures belong in errors. Document deliberate panic preconditions or `Must` APIs instead of declaring every library panic invalid. Use lowercase composable error messages while preserving proper nouns and protocol spelling. Follow [errors.md](errors.md) for wrapping, partial results, and cleanup failures.

## Native validation

Use `gofmt` for formatting. `goimports` can additionally organize imports when it is part of the project's tooling. Run checks appropriate to the change and the project's supported build configurations:

```sh
gofmt -w .
go vet ./...
go test ./...
go test -race ./...
```

The race detector observes executed paths and requires a supported target; a clean run is not a proof about unexecuted code. Use focused tests during development and complete required project checks before publishing.

Preview and review `go fix` changes when modernizing, including after a toolchain update. Its exact flags, build-configuration scope, and semantic caveats are documented once in [modernization.md](modernization.md). Avoid a hook that silently mixes broad modernization with an unrelated commit.

Additional references: [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments), [`fmt.Appendf`](https://pkg.go.dev/fmt@go1.27.1#Appendf), and [the source catalog](resources.md).
