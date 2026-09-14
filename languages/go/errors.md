---
paths: "**/*.go, **/go.mod, **/go.work"
---

# Go Errors

Return errors for expected operational failures. Check them before using results that are invalid on failure, and add the context a caller needs to act. Avoid logging an error at every layer while also returning it; choose a reporting boundary.

## Identity and wrapping

Use a sentinel when callers need a stable error category. Reuse the sentinel value: two calls to `errors.New` with identical messages still produce distinct errors. Use a structured error type when callers need fields or behavior.

`errors.Is` matches through an error tree, including wrapping and custom `Is` methods. Direct comparison is appropriate only when the API intentionally promises exact identity. `errors.AsType[T]` extracts a matching error type in Go 1.26+; use `errors.As` when supporting older versions. A direct type assertion inspects only the outer error.

Wrapping with `%w` exposes the underlying error for inspection. That becomes part of the API contract. Use `%v` when the underlying error should contribute text without exposing its type or identity; use neither merely as a reflex.

```go
package example

import (
	"errors"
	"fmt"
)

// ErrNotFound indicates that the requested record does not exist.
var ErrNotFound = errors.New("not found")

// ValidationError identifies a field whose value was rejected.
type ValidationError struct {
	Field   string
	Message string
}

func (e *ValidationError) Error() string {
	return fmt.Sprintf("%s: %s", e.Field, e.Message)
}

// Classify selects the response category for this API's errors.
func Classify(err error) string {
	if errors.Is(err, ErrNotFound) {
		return "missing"
	}
	if validation, ok := errors.AsType[*ValidationError](err); ok && validation != nil && validation.Field == "email" {
		return "invalid email"
	}
	return "other"
}

func ExampleClassify() {
	err := fmt.Errorf("create user: %w", &ValidationError{Field: "email", Message: "required"})
	fmt.Println(Classify(err))
	// Output: invalid email
}
```

A switch case needs an expression; it cannot contain an `if`-style short declaration. Bind results before the switch, or use the `if` initializer above. An error interface containing a typed nil pointer is non-nil; return a plain nil interface for success, and avoid producing typed nil errors.

## Collecting failures

Use `errors.Join` when the required contract is to retain multiple causes that callers can inspect. It discards nil arguments and returns nil when every argument is nil. Multiple `%w` verbs in `fmt.Errorf` can also expose several causes while adding a message.

```go
package example

import (
	"errors"
	"fmt"
)

// ErrEmailRequired indicates a missing email address.
var ErrEmailRequired = errors.New("email required")

// ErrAgeTooLow indicates an age below this application's minimum.
var ErrAgeTooLow = errors.New("age below minimum")

// ValidateFields returns every applicable validation error.
func ValidateFields(email string, age int) error {
	var errs []error
	if email == "" {
		errs = append(errs, ErrEmailRequired)
	}
	if age < 18 {
		errs = append(errs, ErrAgeTooLow)
	}
	return errors.Join(errs...)
}

func ExampleValidateFields() {
	err := ValidateFields("", 17)
	fmt.Println(errors.Is(err, ErrEmailRequired))
	fmt.Println(errors.Is(err, ErrAgeTooLow))
	// Output:
	// true
	// true
}
```

Return the first error when later work should stop on failure. Collect errors when independent checks or cleanup operations should all run. Replacing an existing multi-error package can change formatting, concrete types, ordering promises, or helper methods; migrate those contracts deliberately.

## Resource cleanup and partial progress

Close resources according to their API. For a read-only file, ignoring a close error after successful reading can be an intentional policy. For buffered output, a flush or close failure can mean the write did not succeed. If an earlier operation already failed, choose whether to preserve that error alone or report cleanup failure as well.

```go
package example

import (
	"errors"
	"fmt"
	"io"
	"os"
)

// WriteFile copies r into path and reports copy or close failures.
// A failure may leave path truncated or partially written; this is not an atomic update.
func WriteFile(path string, r io.Reader) (err error) {
	file, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("create %q: %w", path, err)
	}
	defer func() {
		if closeErr := file.Close(); closeErr != nil {
			err = errors.Join(err, fmt.Errorf("close %q: %w", path, closeErr))
		}
	}()
	if _, err := io.Copy(file, r); err != nil {
		return fmt.Errorf("write %q: %w", path, err)
	}
	return nil
}
```

Successful close does not by itself promise durable storage. Applications requiring atomic replacement or persistence need the appropriate file, synchronization, and directory operations for their platform.

Do not lose an error when adapting APIs. A scanner loop needs `Scanner.Err()` after exhaustion; a fallible iterator needs an error-returning contract. See [composition.md](composition.md). Do not discard a useful byte count merely because an `io.Reader` also returned an error: its contract permits data and an error in the same call.

## Panics and recovery

Expected conditions such as a missing file, invalid external input, or a timeout normally belong in an error return. A documented programmer precondition or deliberate `Must` API may panic. Do not treat every failed initialization as permission for a library to terminate the process.

Recover only at a boundary that can preserve a meaningful contract and state. `log.Fatal` and `os.Exit` terminate the process and skip deferred calls; they are not equivalent to panic. Keep process-exit policy in the executable, after application cleanup has run.

Prefer lowercase error messages without trailing punctuation when they will be composed into other messages. Preserve proper nouns and protocol spelling. End-user presentation can use full sentences independently of internal error formatting.

Related guidance: [testing](test.md), [concurrency and Once panic behavior](concurrency.md), and [reference sources](resources.md). The [`errors` package](https://pkg.go.dev/errors@go1.27.1) and [Go error-wrapping guidance](https://go.dev/blog/go1.13-errors) define inspection and abstraction behavior.
