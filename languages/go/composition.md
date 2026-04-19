---
paths: "**/*.go, **/go.mod"
---

# Go Composition

Structuring behavior, structs vs interfaces vs packages, and composition patterns.

## Core Commands

### NO Inheritance - Use Composition

**Go has no inheritance. This is intentional and correct.**

```go
// ✓ Composition via embedding
type Reader interface {
    Read(p []byte) (n int, err error)
}

type BufferedReader struct {
    reader Reader
    buf    []byte
}

// ✓ Struct embedding (use sparingly)
type LoggedWriter struct {
    io.Writer  // Embedded interface
    logger *log.Logger
}

func (lw *LoggedWriter) Write(p []byte) (n int, err error) {
    lw.logger.Printf("Writing %d bytes", len(p))
    return lw.Writer.Write(p)  // Delegate to embedded
}
```

### Interfaces: Small and Focused

**Interfaces are the default abstraction. Keep them small.**

```go
// ✓ CORRECT: Focused interfaces
type Storage interface {
    Save(key string, value []byte) error
    Load(key string) ([]byte, error)
}

type Closer interface {
    Close() error
}

// ✓ Compose interfaces
type ReadCloser interface {
    Reader
    Closer
}

// ✘ WRONG: Fat interface
type Service interface {
    Save(key string, value []byte) error
    Load(key string) ([]byte, error)
    Delete(key string) error
    List() ([]string, error)
    Close() error
    Connect() error
    Disconnect() error
    // ... 10 more methods
}
```

**Accept interfaces, return structs** (usually).

```go
// ✓ CORRECT
func Process(r io.Reader) (*Result, error) { ... }

// ✘ Usually wrong: returning interface hides concrete type
func Process(r io.Reader) (io.Writer, error) { ... }
```

### ONLY Create Structs for State

**Structs exist when you need to group data or manage state.**

```go
// ✓ Struct managing mutable state
type MessageBuffer struct {
    messages []Message
    mu       sync.Mutex
}

func (mb *MessageBuffer) Add(msg Message) {
    mb.mu.Lock()
    defer mb.mu.Unlock()
    mb.messages = append(mb.messages, msg)
}

// ✓ Struct grouping immutable data
type PRRef struct {
    Owner  string
    Repo   string
    Number int
}

// ✘ WRONG: Empty struct as namespace
type MessageUtils struct{}

func (MessageUtils) ParseTags(tags string) []string { ... }

// ✓ CORRECT: Package-level function
func ParseTags(tags string) []string { ... }
```

### Package-Level Functions Are First-Class

**Don't create structs just to hold functions. Use packages.**

```go
// ✓ CORRECT: Package-level functions
package validation

func ValidateEmail(email string) error { ... }
func ValidateAge(age int) error { ... }

// ✘ WRONG: Unnecessary struct wrapper
package validation

type Validator struct{}

func (v Validator) ValidateEmail(email string) error { ... }
func (v Validator) ValidateAge(age int) error { ... }
```

### Methods vs Functions

**Add methods when:**
- Operating on struct's state
- Method belongs to the type's conceptual API
- Implementing an interface

**Use functions when:**
- Stateless operation
- Works on multiple types
- Doesn't conceptually "belong" to a type

```go
// ✓ Method: operates on state
func (c *Client) GetReview(id int64) (*Review, error) {
    return c.restClient.GetReview(c.ctx, id)
}

// ✓ Function: stateless transformation
func ParsePRRef(ref string) (*PRRef, error) {
    // ... parsing logic
}

// ✓ Function: operates on type but doesn't need state
func FormatReview(review *Review) string {
    return fmt.Sprintf("#%d: %s", review.ID, review.Body)
}
```

### Pointer vs Value Receivers

**Use pointer receivers when:**
- Method mutates the receiver
- Struct is large (avoid copying)
- Consistency: if any method needs pointer, all should use pointer

**Use value receivers when:**
- Method doesn't mutate
- Struct is small (few fields, no mutexes)
- Type is primitive-like (time.Time, etc.)

```go
// ✓ Pointer receivers for mutable state
type Client struct {
    token string
    cache map[string]*Review
}

func (c *Client) AddToCache(id string, review *Review) {
    c.cache[id] = review  // Mutates
}

func (c *Client) GetFromCache(id string) *Review {
    return c.cache[id]  // Doesn't mutate, but pointer for consistency
}

// ✓ Value receiver for immutable type
type PRRef struct {
    Owner  string
    Repo   string
    Number int
}

func (pr PRRef) String() string {
    return fmt.Sprintf("%s/%s#%d", pr.Owner, pr.Repo, pr.Number)
}
```

**CRITICAL: Be consistent within a type. Don't mix pointer and value receivers.**

### Generics as an Alternative to Interfaces

**Interfaces are for runtime polymorphism. Generics are for compile-time parametricity. Pick the right tool.**

When behavior is uniform across types — the function body treats `T` as an opaque value, never inspects it — prefer generics over an interface.

```go
// ✘ Interface indirection where a generic would read cleaner
type Summable interface{ Add(Summable) Summable }

// ✓ Generic — no interface to implement, full type safety
func Sum[T cmp.Ordered](xs []T) T {
    var total T
    for _, x := range xs {
        total += x
    }
    return total
}
```

**Keep interfaces when** the set of implementers is open, when dispatch needs to happen at runtime (value, not type), or when the abstraction hides substantial behavior differences.

See [generics.md](generics.md) for the full treatment.

### Iterator Pattern (Go 1.23+)

**`iter.Seq[T]` and `iter.Seq2[K, V]` let functions produce sequences without materializing a slice.** Use them when:
- The collection might be large
- The caller may short-circuit (break out early)
- The sequence is naturally lazy (streams, paginated APIs, file lines)

```go
// ✓ CORRECT: iterator — caller controls consumption
func Lines(r io.Reader) iter.Seq[string] {
    return func(yield func(string) bool) {
        s := bufio.NewScanner(r)
        for s.Scan() {
            if !yield(s.Text()) {
                return   // caller broke out
            }
        }
    }
}

for line := range Lines(file) {
    if strings.HasPrefix(line, "#") {
        continue
    }
    process(line)
}

// ✓ iter.Seq2 for key/value pairs
func Entries[K comparable, V any](m map[K]V) iter.Seq2[K, V] {
    return func(yield func(K, V) bool) {
        for k, v := range m {
            if !yield(k, v) {
                return
            }
        }
    }
}
```

**When to prefer returning `[]T` instead:** when the caller almost always wants the whole thing, when the collection is already in memory, or when you need random access. Iterators are not a universal replacement.

### Constructor Functions

**Use New* functions for initialization. Return concrete types.**

```go
// ✓ CORRECT
func NewClient(token string) (*Client, error) {
    if token == "" {
        return nil, errors.New("token required")
    }
    return &Client{
        token: token,
        cache: make(map[string]*Review),
    }, nil
}

// ✓ Variant constructors
func NewClientWithCache(token string, cache Cache) (*Client, error) { ... }

// ✘ WRONG: Returning interface hides implementation
func NewClient(token string) (ClientInterface, error) { ... }
```

**Go 1.26: `new(expr)`.** The built-in `new` now accepts an expression, not just a type. This retires the `ptr[T]` helper pattern that proliferated in pre-1.26 codebases.

```go
// ✓ Go 1.26+: inline pointer-to-literal
timeout := new(30 * time.Second)   // *time.Duration
pending := new("pending")          // *string

// ✘ Delete this helper — `go fix` can migrate for you
func ptr[T any](v T) *T { return &v }
p := ptr(42)
```

### Embedding: Use Sparingly

**Embedding is powerful but can be confusing. Prefer explicit fields.**

```go
// ✓ Embedding for interfaces (delegation)
type LoggedWriter struct {
    io.Writer
    logger *log.Logger
}

// ✓ Explicit field when clarity matters
type Client struct {
    rest    *rest.Client
    graphql *graphql.Client
}

// ✘ Embedding concrete types often confusing
type User struct {
    Person  // Promotes all Person fields - unclear ownership
    Role string
}

// ✓ BETTER: Explicit field
type User struct {
    Person Person  // Clear: User has a Person
    Role   string
}
```

---

## Architecture Layers

**Build from simple pieces:**

- **Data layer**: Structs with clear ownership (immutable when possible)
- **Function layer**: Package-level functions for stateless operations
- **Interface layer**: Small, focused interfaces for abstraction
- **Implementation layer**: Structs with methods implementing interfaces

---

## Summary

- **NEVER** try to emulate inheritance (Go doesn't have it intentionally)
- **DO** use small, focused interfaces (1-3 methods)
- **DO** accept interfaces, return structs (usually)
- **DO** use package-level functions for stateless operations
- **DO** use methods when operating on struct's state or implementing interfaces
- **DO** use pointer receivers consistently (all or value, no mixing)
- **DO** use New* constructor functions returning concrete types
- **DO** use embedding sparingly (interfaces yes, structs rarely)
- **DO** design types around behavior, not data hierarchy
- **DO** reach for generics (not `any`, not an interface) when behavior is uniform over types
- **DO** return `iter.Seq[T]` / `iter.Seq2[K,V]` (1.23+) for lazy/streaming sequences
- **DO** use `new(expr)` (1.26+) instead of `ptr[T]` helpers
- **DON'T** create empty structs as namespaces (use packages)
- **DON'T** create fat interfaces (split into smaller ones)
- **DON'T** mix pointer and value receivers on same type
- **DON'T** return interfaces from constructors (usually)

---

## Related Files

- **generics.md**: Type parameters, constraints, when to choose generics over interfaces
- **quality.md**: When methods belong on type vs extracted to functions
- **modules.md**: Organizing functions into cohesive packages
- **errors.md**: Error handling patterns, error types
- **modernization.md**: `new(expr)`, iterators, modernization guidance

## References

- [Effective Go - Methods](https://go.dev/doc/effective_go#methods)
- [Go Proverbs](https://go-proverbs.github.io/) - "The bigger the interface, the weaker the abstraction"
- [Accept Interfaces, Return Structs](https://bryanftan.medium.com/accept-interfaces-return-structs-in-go-d4cab29a301b)
- [Range-over-func](https://go.dev/blog/range-functions) - Iterator pattern (Go 1.23)
- [When to use generics](https://go.dev/blog/when-generics) - Generics vs interfaces
