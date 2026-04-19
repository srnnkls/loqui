---
paths: "**/*.go, **/go.mod"
---

# Go Quality

Naming, comments, documentation, and code conventions.

## Core Commands

### The 5x Rule: Naming Over Comments

**Spend 5x more time on names than comments.**

```go
// ✘ Comment for bad names
result := []string{}
for _, u := range users {
    if u.s == "active" {
        result = append(result, u.e)
    }
}

// ✓ Names eliminate comment
activeUserEmails := []string{}
for _, user := range users {
    if user.status == "active" {
        activeUserEmails = append(activeUserEmails, user.email)
    }
}
```

### Comments for WHY, Not WHAT

**Write comments ONLY for:** Non-obvious WHY, workarounds, performance choices, invariants

**DON'T write for:** WHAT code does, HOW it works, restating obvious

```go
// ✘ WRONG: Restates code
// GetUserByID gets user by ID
func GetUserByID(userID int) (*User, error) {
    return db.Query(User{}).Where("id = ?", userID).First()
}

// ✓ Self-documenting
func GetUserByID(userID int) (*User, error) {
    return db.Query(User{}).Where("id = ?", userID).First()
}

// ✓ Explains WHY
func ValidateAge(age int) error {
    // GDPR Article 8: reject under 16 to avoid consent flow complexity
    if age < 16 {
        return fmt.Errorf("must be 16 or older")
    }
    return nil
}
```

### NO Section Dividers - Split Into Files

**Section dividers = file too large. Split it.**

```go
// ✘ WRONG: Section dividers
// ======== Data Models ========
type User struct { ... }

// ======== Validation ========
func ValidateUser(user *User) error { ... }

// ✓ Split into files
// models.go
type User struct { ... }

// validation.go
func ValidateUser(user *User) error { ... }
```

**ASCII art dividers = immediate split signal.**

### Package Documentation: Use Sparingly

**Write ONLY for:** Public packages, complex behavior, critical context
**DON'T write for:** Self-explanatory exports, internal packages, restating names

```go
// ✘ Restates signature
// CreateUser creates a user with email and age
func CreateUser(email string, age int) *User {
    return &User{Email: email, Age: age}
}

// ✓ Self-explanatory
func CreateUser(email string, age int) *User {
    return &User{Email: email, Age: age}
}

// ✓ Adds context
// RetryWithBackoff retries fn with exponential backoff.
// backoffBase=2.0 means delays of 1s, 2s, 4s, ...
func RetryWithBackoff(fn func() error, backoffBase float64) error {
    ...
}
```

### Package Comments

**Every package needs a package comment in one file (typically doc.go for complex packages).**

```go
// ✓ Package comment
// Package github provides a unified client for GitHub REST and GraphQL APIs.
//
// The Client interface abstracts the dual-API surface, allowing commands
// to work with pending reviews without knowing whether to use REST or GraphQL.
package github
```

### Error Messages: Lowercase, No Punctuation

**Go convention: error messages start lowercase, no trailing punctuation.**

```go
// ✓ CORRECT
return fmt.Errorf("failed to parse PR reference: %s", ref)
return errors.New("no pending review found")

// ✘ WRONG
return fmt.Errorf("Failed to parse PR reference: %s", ref)
return errors.New("No pending review found.")
```

### Named Return Values: Use Sparingly

**Only use named returns when they add clarity (especially for documentation).**

```go
// ✓ Named returns add clarity
func Split(sum int) (x, y int) {
    x = sum * 4 / 9
    y = sum - x
    return
}

// ✓ Unnamed when obvious
func GetUser(id int) (*User, error) {
    return db.Find(id)
}

// ✘ Naked returns in long functions
func ProcessData(data []byte) (result []byte, err error) {
    // ... 50 lines of code ...
    return  // What am I returning? Have to scroll up.
}
```

---

### Stdlib First

**Before reaching for a third-party package or writing a helper, check stdlib.** The 1.21–1.26 window moved a lot of common patterns into the standard library.

```go
// ✓ CORRECT: stdlib covers it
import (
    "cmp"
    "log/slog"
    "slices"
    "maps"
)

sorted := slices.Clone(xs)
slices.Sort(sorted)

best := cmp.Or(req.Preferred, user.Default, "fallback")
n := max(a, b, c)

keys := slices.Collect(maps.Keys(users))

slog.Info("request", "method", r.Method, "path", r.URL.Path)

// ✘ WRONG: hand-rolled when stdlib exists
func sortInts(xs []int) []int {
    out := make([]int, len(xs))
    copy(out, xs)
    sort.Ints(out)
    return out
}
// Use slices.Clone + slices.Sort.
```

See [modernization.md](modernization.md) for the full migration table.

### Loop Variable Scoping (Go 1.22+)

**Delete `x := x` shadow copies inside `range` loops — they're obsolete.** Go 1.22 made each iteration a new scope, eliminating the old closure-capture footgun.

```go
// ✓ Go 1.22+: safe out of the box
for _, x := range xs {
    go process(x)
}

// ✘ Obsolete — `go fix` will remove this
for _, x := range xs {
    x := x
    go process(x)
}
```

### Generics Instead of `any` by Default

**`any` (a.k.a. `interface{}`) discards type information. Prefer generics.**

```go
// ✘ WRONG: any at boundaries — caller must type-assert
func First(xs []any) any { ... }

// ✓ CORRECT: generic — type flows through
func First[T any](xs []T) (T, bool) { ... }
```

`any` remains correct for JSON decoding of unknown shapes, reflection, and heterogeneous containers. Don't use it as a default for "I don't want to think about the type." See [generics.md](generics.md).

### Always Run `go fix` Before Committing

`go fix ./...` applies the stdlib's built-in modernizers — it's safe, behavior-preserving, and catches the drift AI agents introduce.

```bash
go fix ./...     # apply modernizers
go vet ./...     # static checks
gofmt -w .       # or `goimports -w .`
```

Add it to your commit hook or editor-on-save.

---

## Anti-Patterns Checklist

- ✘ Behavioral inheritance (Go doesn't have it, keep it that way)
- ✘ `any` / `interface{}` deep in application (use generics — see [generics.md](generics.md))
- ✘ Global mutable state
- ✘ Goroutine leaks (always ensure cleanup)
- ✘ Missing context.Context for cancellation
- ✘ Ignoring errors (`_ = foo()`)
- ✘ Pointer receiver inconsistency (all or none per type)
- ✘ Getters named GetX (just X in Go)
- ✘ Setters (favor immutability or explicit methods)
- ✘ Init functions with side effects
- ✘ Panic in library code (return errors)
- ✘ Comments that restate code
- ✘ Section divider comments (`// ====`)
- ✘ Shadow-copy `x := x` inside `range` loops (obsolete in Go 1.22+)
- ✘ `hashicorp/go-multierror` (use `errors.Join` — Go 1.20+)
- ✘ Hand-rolled loggers (use `log/slog` — Go 1.21+)

---

## Go-Specific Conventions

### Naming

```go
// ✓ CORRECT naming
type PRRef struct { ... }        // Acronyms: all caps when starting
type HTTPClient struct { ... }   // Acronyms: all caps
func (pr *PRRef) String() { ... }  // Acronym in middle: normal case

var ErrNotFound = errors.New("not found")  // Errors: Err prefix

// ✘ WRONG
type PrRef struct { ... }        // Inconsistent acronym
type HttpClient struct { ... }   // Inconsistent acronym
```

### Receiver Names

**Use consistent, short receiver names (1-2 letters), not "this" or "self".**

```go
// ✓ CORRECT
func (c *Client) GetReview(id int) (*Review, error) { ... }
func (pr *PRRef) String() string { ... }

// ✘ WRONG
func (this *Client) GetReview(id int) (*Review, error) { ... }
func (self *PRRef) String() string { ... }
func (client *Client) GetReview(id int) (*Review, error) { ... }  // Too verbose
```

### Zero Values

**Design types so their zero value is useful.**

```go
// ✓ Zero value is useful
type Buffer struct {
    buf []byte  // nil slice works, append works
}

// ✓ Sync.Mutex zero value is ready to use
var mu sync.Mutex
mu.Lock()

// ✘ Requires initialization
type Client struct {
    http *http.Client  // nil will panic on use
}
```

### Error Handling

**Check errors immediately, don't defer error handling.**

```go
// ✓ CORRECT
file, err := os.Open("file.txt")
if err != nil {
    return fmt.Errorf("failed to open file: %w", err)
}
defer file.Close()

// ✘ WRONG: Ignoring error
file, _ := os.Open("file.txt")
defer file.Close()
```

---

## Summary

- **DO** spend 5x time on naming vs comments
- **DO** write comments for WHY, not WHAT
- **DO** split files when you need section dividers
- **DO** use package comments (especially doc.go for complex packages)
- **DO** start error messages lowercase, no punctuation
- **DO** use named returns only when they add clarity
- **DO** design types for useful zero values
- **DO** use consistent receiver names (1-2 letters)
- **DO** check all errors immediately
- **DO** use context.Context for cancellation
- **DO** prefer stdlib (`slices`, `maps`, `slog`, `cmp`, `errors.Join`) over third-party
- **DO** prefer generics over `any` for uniform behavior
- **DO** run `go fix ./...` before committing to apply modernizers
- **DON'T** write comments that restate code
- **DON'T** use section dividers (`// ====`) - split into files
- **DON'T** write godoc that restates signatures
- **DON'T** use "this" or "self" as receiver names
- **DON'T** ignore errors with `_`
- **NEVER** use getters named GetX (just X)
- **NEVER** panic in library code (return errors)

---

## Related Files

- **composition.md**: Structs vs interfaces, when to use methods
- **generics.md**: When to prefer generics over `any`
- **modernization.md**: Stdlib migration table, 1.21–1.26 features
- **modules.md**: Package organization, internal vs public APIs
- **errors.md**: Error handling patterns, wrapping, sentinel errors

## References

- [Effective Go](https://go.dev/doc/effective_go) - Official Go style guide
- [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments) - Common review feedback
- [Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md) - Comprehensive style guide
- [Go 1.22 release notes — loop-variable change](https://go.dev/doc/go1.22#language)
- [log/slog blog post](https://go.dev/blog/slog) - Structured logging rationale
- [go fix documentation](https://pkg.go.dev/cmd/go#hdr-Update_packages_to_use_modern_features) - Modernizers
