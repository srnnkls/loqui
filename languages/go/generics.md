---
paths: "**/*.go, **/go.mod, **/go.work"
---

# Go Generics

Use a concrete type when it expresses the operation. Use an interface for a behavioral contract. Add type parameters when they preserve a useful relationship among arguments, results, or stored values. These approaches compose.

## Preserve type relationships

A collection helper can preserve its element type without a runtime assertion at the call site. `any` remains appropriate for heterogeneous values, reflection, or a protocol that intentionally accepts arbitrary data.

```go
package example

// First returns the first element, or the zero value and false for an empty slice.
func First[T any](items []T) (T, bool) {
	if len(items) == 0 {
		var zero T
		return zero, false
	}
	return items[0], true
}
```

A function that only calls `Read` will usually be simpler with an `io.Reader` parameter than with a type parameter constrained by `io.Reader`. A method constraint can still be useful when other parts of the signature must preserve the concrete type. Do not decide between interfaces and generics solely from the number of methods or whether users can add implementations.

Generic code is not guaranteed to be faster than interface-based code. Measure performance in the operation that matters. A type switch may indicate an unnecessary type parameter, but a deliberate specialization does not erase every other benefit of preserving `T`.

## Constraints and inference

`cmp.Ordered` covers ordered integer and floating-point types and strings; it does not mean all numeric types and excludes complex numbers. Go has no general standard-library `Integer` constraint. Define the bounds the operation actually needs. Use `~` to admit defined types with the specified underlying type.

```go
package example

// Integer includes Go's integer types and defined types with those underlying types.
type Integer interface {
	~int | ~int8 | ~int16 | ~int32 | ~int64 |
		~uint | ~uint8 | ~uint16 | ~uint32 | ~uint64 | ~uintptr
}

// Sum adds items using T's arithmetic, including its overflow behavior.
func Sum[T Integer](items []T) T {
	var total T
	for _, item := range items {
		total += item
	}
	return total
}
```

Let inference supply type arguments when that keeps the call clear. Specify them when inference cannot find them or when an intentional instantiation is clearer. There is no `slices.Map` in the standard library; a local mapping helper can demonstrate inference:

```go
package example

import "fmt"

// Map applies f in order and returns a new, non-nil slice, including for empty input.
// Elements returned by f may still contain references shared with the input.
func Map[T, U any](items []T, f func(T) U) []U {
	out := make([]U, len(items))
	for i, item := range items {
		out[i] = f(item)
	}
	return out
}

type User struct {
	Name string
}

func ExampleMap() {
	users := []User{{Name: "Ada"}, {Name: "Grace"}}
	names := Map(users, func(user User) string { return user.Name })
	fmt.Println(names)
	// Output: [Ada Grace]
}
```

## Containers and aliases

A generic type is useful when callers need the same data structure with different element types. Do not add parameters that neither the implementation nor its consumers need. Public generic APIs can be useful even when the defining package currently has only one instantiation.

Generic aliases, stable since Go 1.24, give another name to a type without creating a distinct type. A defined type has its own identity; neither mechanism automatically adds a runtime allocation.

```go
package example

// StringMap names a map whose keys are strings.
type StringMap[V any] = map[string]V

// Result groups a value and its error for storage or transport as one value.
type Result[T any] struct {
	Value T
	Err   error
}
```

Prefer `(T, error)` for direct function returns. A `Result[T]` struct can be appropriate as a channel or collection element. Likewise, `func New[T Storage]() T` returns its instantiated `T`, which may be concrete; evaluate how the constructor creates the value instead of assuming every constraint produces an interface value.

## Self-type relationships

An ordinary generic interface can relate a result to a type argument. This form has been expressible since Go 1.18:

```go
package example

// Builder describes builders that preserve a chosen result type.
type Builder[Self any] interface {
	Build() Self
	With(key, value string) Self
}
```

Go 1.26 additionally permits a generic type to refer to itself in its own type-parameter list:

```go
package example

// Adder relates the operand and result type of Add to the implementing type.
type Adder[A Adder[A]] interface {
	Add(A) A
}
```

The second example demonstrates the newer recursive constraint. Ordinary fluent interfaces and self-type relationships did not generally require unsafe code before it. Use these relationships where they clarify a real API.

## Generic methods in Go 1.27

Methods can declare their own type parameters. This can place a generic operation on the object whose state it uses. Interface methods cannot declare type parameters, and generic methods do not implement interface methods.

```go
package example

import "fmt"

// Batch limits how many elements of a borrowed slice are selected.
type Batch struct {
	Limit int
}

// Take returns a view of at most Limit elements; non-positive limits return an empty view.
func (b Batch) Take[T any](items []T) []T {
	return items[:min(max(b.Limit, 0), len(items))]
}

func ExampleBatch() {
	fmt.Println((Batch{Limit: 2}).Take([]int{1, 2, 3}))
	// Output: [1 2]
}
```

## Typed pools need a precise contract

A wrapper around `sync.Pool` still needs a runtime type assertion internally. Returning arbitrary `T` using `p.Get().(T)` fails when the stored interface is nil. A typed nil pointer and a nil interface are different cases.

Prefer a concrete pool when only one resource type is needed; see the buffer example in [concurrency.md](concurrency.md). If a generic wrapper is warranted, constrain its representation so every promised value can be stored, or use a non-nil holder for values including nil interfaces. Document initialization and ownership on return to the pool. Benchmark before adding a pool: it is an allocation optimization, not persistent storage.

See [composition.md](composition.md) for interfaces and aliasing, and [resources.md](resources.md) for reference sources. [When to use generics](https://go.dev/blog/when-generics), [`cmp`](https://pkg.go.dev/cmp@go1.27.1), [Go 1.26 language changes](https://go.dev/doc/go1.26#language), and [generic-method restrictions](https://github.com/golang/go/issues/77273) explain the underlying decisions and constraints.
