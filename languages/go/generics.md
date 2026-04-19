---
paths: "**/*.go, **/go.mod"
---

# Go Generics

Type parameters, constraints, and when to prefer generics over interfaces or `any`.

Generics landed in Go 1.18. They are no longer new — treat them as a first-class tool. The decision tree is: *concrete type when you can, generics when behavior is uniform across types, interface when dispatch needs to happen at runtime.*

---

## Core Guidelines

### Prefer Generics Over `any`

`any` (alias for `interface{}`) discards compile-time type information. Generics preserve it.

```go
// ✘ WRONG: any erases the type
func First(xs []any) any {
    if len(xs) == 0 {
        return nil
    }
    return xs[0]
}
// Caller must type-assert: First(xs).(User) — runtime cost, runtime panic potential

// ✓ CORRECT: generic preserves T
func First[T any](xs []T) (T, bool) {
    var zero T
    if len(xs) == 0 {
        return zero, false
    }
    return xs[0], true
}
// Caller: user, ok := First(users) — no assertion, fully type-safe
```

**`any` is still correct for genuine heterogeneity:** JSON decoding into unknown shapes, reflection, heterogeneous containers, function receivers that truly don't constrain T. Don't use it as the default.

### Prefer Generics Over Single-Method Interfaces

If an interface exists only to abstract behavior over a fixed set of types with a shared operation, generics often read cleaner.

```go
// ✘ Interface indirection when the set is closed
type Number interface{ Add(Number) Number }

// ✓ Generic function — no interface needed
func Sum[T cmp.Ordered](xs []T) T {
    var total T
    for _, x := range xs {
        total += x
    }
    return total
}
```

**Keep interfaces when:** you need runtime polymorphism (dispatch based on value), the set of implementers is open (users can add new ones), or the abstraction hides substantial behavior differences.

### Use `cmp.Ordered` and `constraints` for Common Bounds

Don't hand-roll constraint interfaces. Go 1.21 moved the common ones into `cmp`.

```go
import "cmp"

// ✓ Stdlib constraint
func Max[T cmp.Ordered](a, b T) T {
    if a > b {
        return a
    }
    return b
}

// ✓ Union constraint for custom bounds
type Integer interface {
    ~int | ~int32 | ~int64 | ~uint | ~uint32 | ~uint64
}

func SumInts[T Integer](xs []T) T { ... }
```

The `~` means "any type whose underlying type is …" — essential for accepting user-defined wrapper types like `type UserID int64`.

### Type Inference: Let Go Figure It Out

Avoid explicit type arguments unless inference fails.

```go
// ✘ Redundant
result := slices.Map[User, string](users, User.Name)

// ✓ Let inference work
result := slices.Map(users, User.Name)
```

Specify type arguments only for: constructors of generic types (`NewSet[string]()`), when inference genuinely fails, or when a nil literal breaks inference (`First[User](nil)`).

### Generic Functions: Small, Total, Mechanical

Generic functions work best when the body treats `T` as an opaque value — compared with `cmp.Ordered`, moved, passed, stored. If the body has a type-switch on `T`, generics aren't buying you anything.

```go
// ✓ CORRECT: mechanical, no inspection of T
func Map[T, U any](xs []T, f func(T) U) []U {
    out := make([]U, len(xs))
    for i, x := range xs {
        out[i] = f(x)
    }
    return out
}

// ✘ WRONG: type-switch inside generic body — just take an interface instead
func Describe[T any](x T) string {
    switch v := any(x).(type) {
    case int:
        return fmt.Sprintf("int: %d", v)
    case string:
        return fmt.Sprintf("string: %s", v)
    }
    return "unknown"
}
```

### Generic Types: Containers and State Machines

Generic *types* shine when the whole data structure is parametric and behavior is uniform over `T`.

```go
// ✓ Typed set — no interface{} casts at use sites
type Set[T comparable] struct {
    m map[T]struct{}
}

func NewSet[T comparable]() *Set[T] {
    return &Set[T]{m: make(map[T]struct{})}
}

func (s *Set[T]) Add(x T)           { s.m[x] = struct{}{} }
func (s *Set[T]) Contains(x T) bool { _, ok := s.m[x]; return ok }
func (s *Set[T]) Len() int          { return len(s.m) }

// Usage
ids := NewSet[UserID]()
ids.Add(42)
if ids.Contains(42) { ... }
```

### Generic Type Aliases (Go 1.24+)

Type aliases can now carry type parameters, letting you rename or partially-apply generic types.

```go
// ✓ Rename a long generic type at package boundary
type Result[T any] = struct {
    Value T
    Err   error
}

// ✓ Partial application — fix one parameter, expose another
type StringMap[V any] = map[string]V

func Lookup(m StringMap[User], key string) (User, bool) {
    u, ok := m[key]
    return u, ok
}
```

Aliases don't create a new type — they're sugar. Use them to shorten call sites or provide domain vocabulary without the cost of a wrapper struct.

### Recursive Generic Parameters (Go 1.26+)

A type parameter can now refer to itself in its own constraint list, which unlocks self-referencing data structures and fluent builder patterns that previously required workarounds.

```go
// ✓ Self-typed builder — chain methods preserve the concrete subtype
type Builder[Self any] interface {
    Build() Self
    With(k, v string) Self
}

// Before 1.26, this kind of pattern required unsafe interface tricks or code generation.
```

Use sparingly — the vast majority of generic code does not need recursive constraints.

### Common Patterns

**Typed `sync.Pool`:**

```go
// ✓ Type-safe pool — no assertion in Get
type Pool[T any] struct {
    p sync.Pool
}

func NewPool[T any](new func() T) *Pool[T] {
    return &Pool[T]{p: sync.Pool{New: func() any { return new() }}}
}

func (p *Pool[T]) Get() T  { return p.p.Get().(T) }
func (p *Pool[T]) Put(x T) { p.p.Put(x) }
```

**Optional value:**

```go
// ✓ Two-return pattern — idiomatic for "might not be there"
func Find[T any](xs []T, pred func(T) bool) (T, bool) {
    for _, x := range xs {
        if pred(x) {
            return x, true
        }
    }
    var zero T
    return zero, false
}
```

**Result-like wrapper:** don't do it. Go's `(T, error)` convention is the idiomatic result type. Avoid inventing `Result[T]` just because other languages have it.

---

## Anti-Patterns

```go
// ✘ Generic-for-generic's-sake — only ever called with one concrete type
func ProcessUsers[T any](users []T) { ... }   // T is always User — drop the parameter

// ✘ Type-switch inside generic body — use sum types via interface instead
func Handle[T any](x T) {
    switch v := any(x).(type) { ... }    // defeats the point of generics
}

// ✘ Overuse of constraints when `any` is fine
type HasID interface{ ID() string }
func ByID[T HasID](xs []T) map[string]T { ... }
// If only one concrete type in scope, just write the non-generic version.

// ✘ Generic constructors returning interface types
func New[T Storage]() T { ... }
// Constructors should return concrete types. If T is constrained to an interface,
// you've contorted the type system to reinvent factories.

// ✘ Exporting parameterized types when a single concrete type would do
type Cache[K comparable, V any] struct { ... }   // Fine if users really parameterize
// But if every consumer calls NewCache[string, *User], just ship CacheUser.
```

---

## Summary

- **DO** prefer generics over `any` when the type is known at compile time
- **DO** prefer generics over single-method interfaces for closed, uniform behavior
- **DO** use `cmp.Ordered` and `~T` underlying-type constraints from stdlib
- **DO** let type inference work — avoid explicit type arguments at call sites
- **DO** keep generic bodies mechanical — no type-switches on `T`
- **DO** use generic type aliases (1.24+) to shorten long types at package boundaries
- **DO** use recursive type parameters (1.26+) for self-typed builders — sparingly
- **DON'T** write `interface{}` / `any` when you mean "any type, uniformly"
- **DON'T** add type parameters when there is only ever one concrete type
- **DON'T** invent `Result[T]` — Go's `(T, error)` is the idiomatic result type
- **DON'T** return interface types from generic constructors

---

## Related Files

- [composition.md](composition.md) - Interfaces vs generics, structural design
- [modernization.md](modernization.md) - `cmp.Ordered`, 1.24 aliases, 1.26 features
- [quality.md](quality.md) - Why `any` is still an anti-pattern by default

## References

- [Go Generics tutorial](https://go.dev/doc/tutorial/generics) - Official intro
- [Type parameters proposal](https://go.googlesource.com/proposal/+/refs/heads/master/design/43651-type-parameters.md) - Design rationale
- [cmp package](https://pkg.go.dev/cmp) - `Ordered`, `Compare`, `Or`
- [slices package](https://pkg.go.dev/slices) - Canonical generic utilities
- [Go 1.24 release notes — generic aliases](https://go.dev/doc/go1.24#language)
- [When to use generics](https://go.dev/blog/when-generics) - Ian Lance Taylor
