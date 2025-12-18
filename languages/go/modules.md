---
paths: "**/*.go, **/go.mod"
---

# Go Modules

Package structure, organization, and public API design.

## Core Commands

### Standard Go Project Layout

**For applications (cmd + internal):**

```
project-root/
├── cmd/
│   └── myapp/
│       └── main.go           # Application entry point
├── internal/
│   ├── github/               # Domain package
│   │   ├── client.go
│   │   ├── types.go
│   │   └── auth.go
│   ├── templates/            # Another domain package
│   │   └── templates.go
│   └── ui/                   # Presentation layer
│       └── table.go
├── go.mod
├── go.sum
└── README.md
```

**For libraries (pkg + internal):**

```
project-root/
├── pkg/
│   └── mylib/                # Public API
│       ├── client.go
│       └── types.go
├── internal/                 # Private implementation
│   └── parser/
│       └── parser.go
├── go.mod
└── go.sum
```

**Key conventions:**
- `cmd/`: Application entry points (main packages)
- `internal/`: Private packages (Go enforces this - can't be imported outside module)
- `pkg/`: Public library code (optional - root works too for simple libs)

### Feature-Based Package Organization

**Organize by domain feature, NOT by technical layer.**

```go
// ✓ CORRECT: Feature-based
internal/
├── github/                   # GitHub domain
│   ├── client.go            # Client implementation
│   ├── types.go             # Domain types (PRRef, Review, Comment)
│   ├── auth.go              # Authentication logic
│   └── graphql.go           # GraphQL queries
├── templates/                # Template domain
│   └── templates.go         # Template registry and logic
└── ui/                       # UI domain
    └── table.go              # Table rendering

// ✘ WRONG: Layer-based organization
internal/
├── models/                   # All types mixed together
│   ├── prref.go
│   ├── review.go
│   └── template.go
├── services/                 # All business logic mixed
│   ├── github_service.go
│   └── template_service.go
└── utils/                    # Grab bag
    ├── auth.go
    └── table.go
```

### Package Naming

**Packages are lowercase, single word, no underscores.**

```go
// ✓ CORRECT
package github
package templates
package ui

// ✘ WRONG
package GitHub          // Capital letters
package github_client   // Underscores
package githubclient    // Confusing compound (split into packages)
```

**Package names should be:**
- Short, clear, evocative
- Singular (not plural): `template`, not `templates` (exception: when package contains collection)
- Not overly generic: avoid `util`, `common`, `base`

### Public vs Private (Exported vs Unexported)

**Capitalization determines visibility:**

```go
// ✓ Public API
type Client struct { ... }           // Exported type
func NewClient() *Client { ... }     // Exported function
func (c *Client) GetReview() { ... } // Exported method

// ✓ Private implementation
type clientImpl struct { ... }       // Unexported type
func parseToken() string { ... }     // Unexported function
func (c *Client) validateCache() { ... } // Unexported method

// ✓ Struct fields
type PRRef struct {
    Owner  string  // Exported: can be accessed outside package
    Repo   string  // Exported
    Number int     // Exported
}

type client struct {
    token string  // Unexported: private to package
    cache map[string]*Review
}
```

### File Organization Within Package

**Keep related code together. Split at ~500 lines or by logical concern.**

```go
// ✓ CORRECT: Related code in same file
// github/types.go
type PRRef struct { ... }
type Review struct { ... }
type Comment struct { ... }

func ParsePRRef(ref string) (*PRRef, error) { ... }

// github/client.go
type Client struct { ... }
func NewClient() *Client { ... }
func (c *Client) GetReview() (*Review, error) { ... }

// github/auth.go
func GetGitHubToken() (string, error) { ... }
```

**When to split:**
- File exceeds ~500 lines
- Distinct concerns within package (auth, parsing, rendering)
- Multiple implementations of same interface

**DON'T split prematurely** (< 100 lines per file is too fragmented).

### Package Documentation

**Every package needs a doc comment on the package clause.**

```go
// ✓ CORRECT: Package documentation
// Package github provides a unified client for GitHub REST and GraphQL APIs.
//
// The Client interface abstracts the dual-API surface, allowing commands
// to work with pending reviews without knowing whether to use REST or GraphQL.
//
// Example usage:
//
//     client, err := github.NewClient(token)
//     if err != nil {
//         log.Fatal(err)
//     }
//     review, err := client.GetPendingReview(ctx, prRef)
package github
```

**Place in:**
- `doc.go` for complex packages with extensive documentation
- Any `.go` file in simple packages (conventionally the main file)

### Internal Packages

**Use `internal/` to enforce package privacy.**

```go
// Enforced by Go compiler:
module github.com/user/myapp

// ✓ Can import
github.com/user/myapp/internal/github        // Within same module

// ✘ CANNOT import (compiler error)
github.com/other/app imports github.com/user/myapp/internal/github
```

**When to use internal/:**
- Implementation details you want to hide
- Packages that shouldn't be imported by external code
- Experimental APIs not ready for public use

### Dependencies Flow Toward Domain Core

**Inner packages have fewer dependencies. Outer packages depend on inner.**

```go
// ✓ CORRECT: Dependencies flow inward
internal/github/
    types.go          // No internal dependencies (just stdlib)
    client.go         // Imports types.go
    auth.go           // Imports types.go

cmd/drafts/
    main.go           // Imports internal/github, internal/templates
    commands.go       // Imports internal/github, internal/ui

// ✘ WRONG: Circular dependencies
// github/client.go imports ui/table.go
// ui/table.go imports github/types.go
// Creates import cycle
```

**Prevent cycles:**
- Extract shared types to lower-level package
- Use interfaces to invert dependencies
- Rethink package boundaries

### Main Package

**Every executable needs exactly one `main` package with `main()` function.**

```go
// ✓ CORRECT: cmd/drafts/main.go
package main

import (
    "github.com/spf13/cobra"
    "github.com/srnnkls/drafts/internal/github"
)

func main() {
    rootCmd := &cobra.Command{
        Use:   "drafts",
        Short: "Manage GitHub PR review drafts",
    }

    rootCmd.AddCommand(listCmd())
    rootCmd.AddCommand(addCmd())

    if err := rootCmd.Execute(); err != nil {
        os.Exit(1)
    }
}
```

**Keep main.go thin:**
- Parse flags
- Initialize dependencies
- Call into internal packages
- Handle top-level errors

### Avoid Utils/Common Packages

**"Utils" and "common" are code smells. Use specific names.**

```go
// ✘ WRONG: Vague package names
internal/utils/
    strings.go
    time.go
    http.go

internal/common/
    types.go
    errors.go

// ✓ CORRECT: Specific package names
internal/parsing/
    prref.go          // PR reference parsing

internal/formatting/
    table.go          // Table formatting

internal/github/
    types.go          // GitHub-specific types
    errors.go         // GitHub-specific errors
```

---

## Summary

- **DO** use standard layout: `cmd/` for apps, `internal/` for private code
- **DO** organize by feature/domain, NOT technical layer
- **DO** keep package names lowercase, single word, no underscores
- **DO** use capitalization for public/private (exported/unexported)
- **DO** keep related code together in same file/package
- **DO** split files at ~500 lines or by logical concern
- **DO** write package documentation on package clause
- **DO** use `internal/` to enforce privacy
- **DO** ensure dependencies flow toward domain core
- **DO** keep main.go thin (orchestration only)
- **DON'T** use "utils" or "common" packages
- **DON'T** organize by technical layer (models/, services/)
- **DON'T** split prematurely (< 100 lines per file)
- **NEVER** create circular dependencies

---

## Related Files

- **composition.md**: When to use packages vs structs
- **quality.md**: When to split files (section dividers = split signal)
- **errors.md**: Package-specific error types

## References

- [Standard Go Project Layout](https://github.com/golang-standards/project-layout)
- [Go Package Best Practices](https://go.dev/blog/package-names)
- [Internal Packages](https://go.dev/doc/go1.4#internalpackages)
