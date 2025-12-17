---
paths: "**/*.go, **/go.mod"
---

# Go Errors - Imperative Skill

**When to invoke**: Error handling, error types, error wrapping, error checking patterns.

## Core Commands

### Errors Are Values

**In Go, errors are just values. Return them explicitly.**

```go
// ✓ CORRECT: Return errors explicitly
func GetUser(id int) (*User, error) {
    user, err := db.Query(id)
    if err != nil {
        return nil, fmt.Errorf("failed to get user: %w", err)
    }
    return user, nil
}

// Go has no exceptions - this is intentional
```

### Check Errors Immediately

**Always check errors right after they occur.**

```go
// ✓ CORRECT: Check immediately
file, err := os.Open("file.txt")
if err != nil {
    return fmt.Errorf("failed to open file: %w", err)
}
defer file.Close()

// Process file...

// ✘ WRONG: Ignoring errors
file, _ := os.Open("file.txt")
defer file.Close()

// ✘ WRONG: Deferred error checking
file, err := os.Open("file.txt")
// ... many lines ...
if err != nil {  // Too far from the call
    return err
}
```

### Error Wrapping with %w

**Use `%w` to wrap errors, preserving the original error.**

```go
// ✓ CORRECT: Wrap with context
func ProcessFile(path string) error {
    data, err := os.ReadFile(path)
    if err != nil {
        return fmt.Errorf("failed to process %s: %w", path, err)
    }
    // ...
}

// Caller can check the original error
err := ProcessFile("config.json")
if errors.Is(err, os.ErrNotExist) {
    // Handle missing file
}

// ✘ WRONG: Using %v loses error chain
return fmt.Errorf("failed to process %s: %v", path, err)
```

### Sentinel Errors

**Use `var` for errors that callers should check.**

```go
// ✓ CORRECT: Exported sentinel errors
var (
    ErrNotFound     = errors.New("not found")
    ErrInvalidInput = errors.New("invalid input")
    ErrUnauthorized = errors.New("unauthorized")
)

func GetUser(id int) (*User, error) {
    user, err := db.Find(id)
    if err != nil {
        if errors.Is(err, sql.ErrNoRows) {
            return nil, ErrNotFound
        }
        return nil, fmt.Errorf("database error: %w", err)
    }
    return user, nil
}

// Caller can check
user, err := GetUser(123)
if errors.Is(err, ErrNotFound) {
    // Handle not found case
}
```

**Naming convention:** `Err` prefix for sentinel errors.

### Custom Error Types

**Create custom error types when errors need structured data.**

```go
// ✓ Custom error type with data
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation failed for %s: %s", e.Field, e.Message)
}

func ValidateUser(user *User) error {
    if user.Email == "" {
        return &ValidationError{
            Field:   "email",
            Message: "email is required",
        }
    }
    return nil
}

// Caller can extract structured data
err := ValidateUser(user)
var validationErr *ValidationError
if errors.As(err, &validationErr) {
    fmt.Printf("Field: %s, Message: %s\n",
        validationErr.Field, validationErr.Message)
}
```

### errors.Is vs errors.As

**`errors.Is`: Check if error matches a sentinel error**
**`errors.As`: Extract specific error type**

```go
// ✓ errors.Is: Check sentinel errors
if errors.Is(err, os.ErrNotExist) {
    // Handle file not found
}

// ✓ errors.As: Extract error type
var validationErr *ValidationError
if errors.As(err, &validationErr) {
    // Access validationErr.Field, validationErr.Message
}

// ✘ WRONG: Direct comparison (breaks with wrapping)
if err == os.ErrNotExist {  // Won't work if error is wrapped
    // ...
}

// ✘ WRONG: Type assertion (breaks with wrapping)
if ve, ok := err.(*ValidationError); ok {  // Won't work if wrapped
    // ...
}
```

### Don't Panic in Library Code

**Libraries should return errors, not panic. Only panic for truly unrecoverable situations.**

```go
// ✓ CORRECT: Return error
func ParseConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("failed to read config: %w", err)
    }
    // ...
    return config, nil
}

// ✘ WRONG: Panic in library code
func ParseConfig(path string) *Config {
    data, err := os.ReadFile(path)
    if err != nil {
        panic(fmt.Sprintf("failed to read config: %v", err))
    }
    // ...
}

// ✓ OK: Panic for programming errors (use sparingly)
func process(data []byte) {
    if len(data) == 0 {
        panic("process called with empty data - this is a bug")
    }
}
```

**When panic is acceptable:**
- `init()` functions for fatal setup errors
- Programming errors that should never happen (assertions)
- Application main() for unrecoverable errors (convert to `log.Fatal`)

### Error Message Convention

**Error messages: lowercase, no punctuation, provide context.**

```go
// ✓ CORRECT
return fmt.Errorf("failed to parse PR reference: %w", err)
return errors.New("no pending review found")
return fmt.Errorf("invalid age %d: must be 18 or older", age)

// ✘ WRONG: Capitalized, punctuation
return fmt.Errorf("Failed to parse PR reference: %w", err)
return errors.New("No pending review found.")
```

**Exception:** Error messages that will be displayed to end users can be formatted differently.

### Multi-Error Handling

**When collecting multiple errors, use a multi-error type or return first error.**

```go
// ✓ Simple case: return first error
func ValidateFields(user *User) error {
    if user.Email == "" {
        return errors.New("email required")
    }
    if user.Age < 18 {
        return errors.New("must be 18 or older")
    }
    return nil
}

// ✓ Collect all errors (use package like hashicorp/go-multierror)
import "github.com/hashicorp/go-multierror"

func ValidateAllFields(user *User) error {
    var result error

    if user.Email == "" {
        result = multierror.Append(result, errors.New("email required"))
    }
    if user.Age < 18 {
        result = multierror.Append(result, errors.New("must be 18 or older"))
    }

    return result
}
```

### Don't Ignore Errors in Defer

**If a deferred function returns an error, handle it.**

```go
// ✓ CORRECT: Handle close error
func ProcessFile(path string) (err error) {
    file, err := os.Open(path)
    if err != nil {
        return fmt.Errorf("failed to open: %w", err)
    }
    defer func() {
        if closeErr := file.Close(); closeErr != nil && err == nil {
            err = fmt.Errorf("failed to close: %w", closeErr)
        }
    }()

    // Process file...
    return nil
}

// ✘ WRONG: Ignoring close error
defer file.Close()  // Error ignored
```

---

## Commands Summary

- **DO** return errors explicitly (no exceptions in Go)
- **DO** check errors immediately after they occur
- **DO** wrap errors with `fmt.Errorf("context: %w", err)`
- **DO** use `var ErrName = errors.New("message")` for sentinel errors
- **DO** create custom error types when errors need structured data
- **DO** use `errors.Is` to check sentinel errors
- **DO** use `errors.As` to extract error types
- **DO** start error messages lowercase, no punctuation
- **DO** handle errors from deferred Close() calls
- **DON'T** ignore errors (no `_ = foo()`)
- **DON'T** use `%v` when wrapping errors (use `%w`)
- **DON'T** compare errors directly with `==` (use `errors.Is`)
- **DON'T** use type assertions on errors (use `errors.As`)
- **NEVER** panic in library code (return errors)
- **NEVER** defer error checking (check immediately)

---

## Related Files

- **quality.md**: Error message conventions
- **composition.md**: When to create custom error types

## References

- [Error Handling in Go](https://go.dev/blog/error-handling-and-go)
- [Working with Errors in Go 1.13](https://go.dev/blog/go1.13-errors)
- [Don't just check errors, handle them gracefully](https://dave.cheney.net/2016/04/27/dont-just-check-errors-handle-them-gracefully)
