---
paths: "**/*.go, **/go.mod, **/go.work"
---

# Go Composition

Choose boundaries around behavior, state, ownership, and invariants. A package is a namespace and dependency boundary; a struct represents related state or implements a useful protocol. A stateless implementation such as an `io.Writer` can still reasonably be a struct.

## Interfaces and constructors

Define small interfaces around what the consumer needs. A single-method interface such as `io.Reader` remains a useful abstraction. Combine interfaces when a consumer needs the combined contract, rather than giving every consumer one large service interface.

Prefer concrete parameters when no abstraction is useful. Accept an interface when multiple implementations or a protocol boundary make it useful. [Generics](generics.md) preserve relationships among types; they do not automatically improve a function that only calls an interface method.

Returning a concrete type is a useful default for constructors because callers retain access to its capabilities. Returning an interface can deliberately hide representation: `io.NopCloser` returns `io.ReadCloser`. Choose the public contract intentionally. Returning `T` from a generic constructor does not itself mean returning an interface value.

Embedding promotes fields and methods; it does not provide virtual dispatch or behavioral inheritance. Prefer a named field when the embedded type's methods should not become part of the public API. In particular, keep implementation mutexes private.

## Ownership of mutable data

Go passes arguments by value. A slice value contains a reference to backing storage; copying a map, pointer, or interface can also preserve access to shared data. A channel send does not automatically make the receiver the only owner.

For APIs accepting or returning mutable data, specify:

- Whether the callee retains the data after the call.
- Whether callers or the callee may mutate it, including concurrently.
- Whether a returned view remains valid after the next operation, a close, or a transaction ending.
- Whether the caller must copy data to retain it longer.

Copy when the contract requires independent storage. Borrow when the lifetime and mutation rules permit sharing. `slices.Clone`, `maps.Clone`, and ordinary struct assignment are shallow; nested pointers, slices, and maps may still share data. Preserving nil versus non-nil empty values can matter to callers and encoders.

```go
package example

import "bytes"

// Blob owns its byte storage. Its methods do not support concurrent mutation.
type Blob struct {
	data []byte
}

// NewBlob copies data; callers may modify their input after this call.
func NewBlob(data []byte) *Blob {
	return &Blob{data: bytes.Clone(data)}
}

// Bytes returns an independent copy that the caller may modify.
func (b *Blob) Bytes() []byte {
	return bytes.Clone(b.data)
}
```

A copying API is not always the right design. Pebble returns a view whose lifetime is tied to a closer; bbolt returns database-owned bytes valid during a transaction. Those APIs deliberately avoid a copy and document the restrictions. See the pinned examples in [resources.md](resources.md).

## Pointer and value receivers

Use a pointer receiver when the method mutates the receiver itself, when copying is undesirable, or when the type contains synchronization state that must not be copied after use. A value receiver suits a small value type when copying matches its semantics.

Consistency within a type is a good default. It is not a language rule: `time.Time` uses value receivers for operations such as `MarshalJSON` and a pointer receiver for `UnmarshalJSON`. Preserve the method sets needed by callers and interfaces. A value receiver containing a slice can still mutate shared elements; it does not promise immutability.

Design useful zero values where possible. A constructor remains appropriate when an API needs a non-nil dependency, validated configuration, or initialized resources. Document a constructor requirement rather than allowing an accidental nil dereference to define it.

## Iterators with failures

Use `iter.Seq` or `iter.Seq2` when incremental traversal or avoiding materialization benefits callers. A returned slice is often simpler when callers need indexing, repeated traversal, or an owned snapshot. State whether an iterator can be restarted, used concurrently, or retained after its owner closes.

An iterator over I/O needs an error channel in its API. For a scanner-backed iterator, distinguish EOF from `Scanner.Err()`. This example keeps the scanner's default token limit, approximately 64 KiB including any delimiter; a longer line is an error. Applications needing a different limit should configure `Scanner.Buffer` or choose another reader API.

```go
package example

import (
	"bufio"
	"io"
	"iter"
)

// Lines consumes r and yields each line without its line ending.
// On scan failure it yields one final empty string with a non-nil error.
// It uses bufio.Scanner's default token limit and does not close r.
// Treat the result as single-use; do not invoke it concurrently.
func Lines(r io.Reader) iter.Seq2[string, error] {
	return func(yield func(string, error) bool) {
		scanner := bufio.NewScanner(r)
		for scanner.Scan() {
			if !yield(scanner.Text(), nil) {
				return
			}
		}
		if err := scanner.Err(); err != nil {
			yield("", err)
		}
	}
}
```

Consumers check the error before using a yielded line. If a consumer ends iteration early, this function cannot report a later, unobserved read error. Respect a false return from `yield`: do not call it again or launch work that outlives that iteration without an explicit lifetime contract. A scanner-style object with an `Err()` method or a callback function returning an error may fit an existing API better than `Seq2`.

## Optional values and initialization

Use `(T, bool)` when a lookup can miss without failing. Use `(T, error)` for an operation that can fail. A pointer can represent optional data when nil has a clear meaning, for example an omitted configuration field.

Go 1.26's `new(expr)` creates a pointer to an initialized value. It is useful when that representation fits the API; it is not a reason to turn ordinary value fields into pointers. See [modernization.md](modernization.md).

Keep side-effectful initialization explicit where callers need to choose configuration, handle errors, or control lifetime. Avoid introducing `init`-time I/O merely to shorten construction.

Related guidance: [errors](errors.md), [concurrency](concurrency.md), [modules](modules.md), and [reference contracts](resources.md). The [`io`](https://pkg.go.dev/io@go1.27.1), [`iter`](https://pkg.go.dev/iter@go1.27.1), and [`bufio.Scanner`](https://pkg.go.dev/bufio@go1.27.1#Scanner) documentation defines the relevant standard-library contracts.
