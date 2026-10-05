---
paths: "**/*.go, **/go.mod, **/go.work"
---

# Go Reference Sources

Use the language specification and the selected toolchain's package contracts for technical facts. Use style guides for design defaults and real implementations for examples of tradeoffs. An implementation example does not establish a universal rule.

This catalog was checked on 14 September 2026. The Go examples target Go 1.27 and were validated with Go 1.27.1. The repository currently has no Go sources configured in `phora.toml`; links below identify upstream references, not local vendored checkouts.

## Language and API contracts

| Source                                                                                                                                           | Read it for                                                                                                                     |
| ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| [Go specification](https://go.dev/ref/spec)                                                                                                      | Method sets, type parameters, assignment, and loop semantics. Use the matching release source when historical behavior matters. |
| [Go 1.27.1 source](https://github.com/golang/go/tree/go1.27.1/src)                                                                               | A versioned implementation and its API comments and tests.                                                                      |
| [Go toolchains](https://go.dev/doc/toolchain), [module reference](https://go.dev/ref/mod)                                                        | Language baselines, toolchain selection, tool dependencies, and workspaces.                                                     |
| [`io`](https://pkg.go.dev/io@go1.27.1), [`bufio.Scanner`](https://pkg.go.dev/bufio@go1.27.1#Scanner), [`iter`](https://pkg.go.dev/iter@go1.27.1) | Partial reads, scanner errors, iterator lifetimes, and stopping iteration.                                                      |
| [`sync`](https://pkg.go.dev/sync@go1.27.1), [`context`](https://pkg.go.dev/context@go1.27.1), [memory model](https://go.dev/ref/mem)             | Synchronization, cancellation, Once panic behavior, and pool ownership.                                                         |
| [`testing`](https://pkg.go.dev/testing@go1.27.1), [`testing/synctest`](https://pkg.go.dev/testing/synctest@go1.27.1)                             | Cleanup order, test contexts, benchmarks, and durable blocking.                                                                 |
| [Go doc comments](https://go.dev/doc/comment)                                                                                                    | API documentation that explains behavior, rather than only implementation rationale.                                            |
| [Release history](https://go.dev/doc/devel/release), [Go 1.27 notes](https://go.dev/doc/go1.27)                                                  | Release status and changes that older educational material cannot establish.                                                    |

The installed source and documentation are useful even without a reference checkout:

```sh
go version
go env GOROOT
go doc sync.OnceValues
go doc testing.T.Context
go tool fix help
```

## Design guidance

| Source                                                                  | Scope and limitation                                                                                                                           |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| [Effective Go](https://go.dev/doc/effective_go)                         | Core language conventions. Its own introduction says it is not actively updated and omits modern generics, modules, and library additions.     |
| [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments)       | Common defaults for receivers, interfaces, names, errors, and synchronous APIs. Apply them with the API's concrete requirements.               |
| [When to use generics](https://go.dev/blog/when-generics)               | Choosing type parameters for useful type relationships, without replacing every behavioral interface.                                          |
| [Google Go decisions](https://google.github.io/styleguide/go/decisions) | Organizational choices and examples; distinguish those choices from language restrictions.                                                     |
| [Uber Go guide](https://github.com/uber-go/guide/blob/master/style.md)  | Practical boundary-copy and ownership examples. Copying is one way to provide independent data, not the only valid API contract.               |
| [Go fix design and usage](https://go.dev/blog/gofix)                    | Analyzer selection, preview behavior, build-configuration coverage, and migration limitations. Check the installed suite because names change. |

## Concrete implementation examples

The storage references below are pinned to commits, so their contracts remain reviewable as their upstream branches move. The catalog uses selected APIs, not a blanket endorsement of every implementation choice.

| Source                                                                                                            | Contract illustrated                                                                                                                             | Related guide                                     |
| ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------- |
| [Pebble Reader and DB](https://github.com/cockroachdb/pebble/blob/13596f1e1cea9196defa14dec5c2ac9d90120010/db.go) | `Get` returns a read-only byte view whose lifetime ends when its associated closer is closed. Successful callers must close that resource.       | [Ownership and iterators](composition.md)         |
| [bbolt Bucket](https://github.com/etcd-io/bbolt/blob/c93ba6647e844212948a2064b916360daebc5f50/bucket.go)          | `Get` returns database-owned bytes valid for the transaction's lifetime. Copy when retaining them longer or needing mutable independent storage. | [Ownership](composition.md), [cleanup](errors.md) |
| [Go file-descriptor writes](https://github.com/golang/go/blob/go1.27.1/src/internal/poll/fd_unix.go)              | A write lock can legitimately span I/O to maintain serialization.                                                                                | [Concurrency](concurrency.md)                     |
| [Go time values](https://github.com/golang/go/blob/go1.27.1/src/time/time.go)                                     | Value receivers for marshaling coexist with pointer receivers for unmarshaling. Receiver consistency is a default, not a language restriction.   | [Composition](composition.md)                     |
| [Go environment access](https://github.com/golang/go/blob/go1.27.1/src/syscall/env_unix.go)                       | Synchronization of environment access does not stop tests from interfering through shared process state.                                         | [Testing](test.md)                                |

When using implementation code as a reference, read its surrounding lifetime, error, and concurrency contract. Do not infer independent ownership from a slice return, or a general performance guarantee from a specialized implementation.
