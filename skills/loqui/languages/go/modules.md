---
paths: "**/*.go, **/go.mod, **/go.work"
---

# Go Modules and Packages

A package is the unit of compilation, import, and unexported-name visibility. A module groups packages and records dependency and Go-version requirements. Keep these boundaries separate from filenames and layout conventions.

## Layout and names

Start with a flat package or module when that fits. `cmd/` is a common convention for several executables, and `internal/` has an enforced import rule. `pkg/` is optional and confers no special visibility. There is no universal Go-team-mandated repository tree.

```text
example.com/project/
    go.mod
    go.sum
    client.go
    client_test.go
    internal/
        protocol/
            decode.go
    cmd/
        project/
            main.go
```

Use short lowercase package names that describe their purpose and read well at a call site. Avoid stuttering and vague collections of unrelated helpers. Singular names are common, but meaningful plural names and compounds are normal too. Split by cohesive responsibility, invariants, or dependency direction; neither a strict layer rule nor an arbitrary file-size threshold determines every boundary.

## Visibility and dependencies

An exported identifier begins with an uppercase Unicode letter and is declared in an exportable context such as package scope, a field, or a method. Unexported package identifiers are accessible across the source files in that package. One source file does not import another source file.

Use package-level dependency diagrams:

```text
cmd/project  -> client
client       -> internal/protocol
```

`types.go` and `client.go` can refer to each other's package declarations directly. Moving them between files does not break a package import cycle. Resolve cycles by changing the package boundary, extracting a cohesive lower-level dependency, or depending on a consumer-defined interface.

Document the public package contract. Use an internal package when implementation details need a narrower import boundary, and preserve its own documentation when that helps maintainers.

## The internal import rule

An `internal` directory restricts imports to the tree rooted at its parent. In module mode, the rule is checked using import paths; it is not simply “inside the same module.” The Go command enforces this rule.

| Importer                                        | Imported package                              | Allowed?                                                                        |
| ----------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------- |
| `example.com/project/client`                    | `example.com/project/internal/protocol`       | Yes                                                                             |
| `example.com/other/client`                      | `example.com/project/internal/protocol`       | No                                                                              |
| `example.com/project/sibling`                   | `example.com/project/feature/internal/detail` | No, despite sharing a module                                                    |
| `example.com/project/feature/client`            | `example.com/project/feature/internal/detail` | Yes                                                                             |
| Separate module `example.com/project/extension` | `example.com/project/internal/protocol`       | Yes, when its dependency resolves; the import path is within the permitted tree |

Use nested internal directories when the intended boundary is narrower than the module. This is an import restriction, not a security boundary against someone who can copy or edit the source. [Internal directories](https://pkg.go.dev/cmd/go@go1.27.1#hdr-Internal_Directories)

## Go versions and tools

The module's `go` directive states its minimum required Go version and controls language semantics. A `toolchain` directive suggests a toolchain when the module is the main module; it does not replace the compatibility contract for consumers. Build constraints may affect the version applicable to a particular file.

```text
module example.com/project

go 1.27.0
```

Use the current supported patch toolchain for development while retaining an older minimum only when the project actually supports and checks it. Go 1.27 adds the `stdversion` vet check to the default checks run by `go test`, helping detect standard-library symbols newer than the file's declared baseline. Updating the compiler alone is not a reason to raise every library's `go` directive. [Go toolchains](https://go.dev/doc/toolchain)

For module-managed tools on Go 1.24+, use tool directives. For example, this command adds a tool requirement and its dependency version; inspect and commit the resulting `go.mod` and `go.sum` changes:

```sh
go get -tool golang.org/x/tools/cmd/stringer@latest
go tool stringer -help
```

Use an explicit selected version instead of `@latest` when reproducibility of the selection matters; subsequent invocations use the module's selected version. Tool dependencies participate in module dependency selection. Choose a tool release compatible with the project's baseline and account for dependency upgrades it requires.

After registering all tools and verifying the workflow, remove obsolete `tools.go` imports and their build tags. Go 1.27.1's `go fix` suite does not perform that module-file migration for you. Global editor tools or tools intentionally isolated from the module may need a different installation strategy. [Tool directives](https://go.dev/ref/mod#go-mod-file-tool)

## Multi-module workspaces

Use `go.work` to develop related modules together without adding local filesystem replacements to each module. A replace directive remains useful when an actual module substitution belongs to the main module's configuration.

```text
go 1.27.0

use (
    ./server
    ./shared
)
```

Usually keep a personal workspace file uncommitted. A repository whose modules are developed as a coordinated unit can intentionally commit it. Test individually released modules with `GOWORK=off` as well, so workspace-selected dependencies do not hide problems consumers will encounter.

`go work sync` can update member modules' dependency requirements using workspace-selected versions. Review those edits before committing. `go.work.sum` records additional workspace checksums; it does not replace member modules' `go.sum` files. [Workspace guidance](https://go.dev/ref/mod#workspaces)

## Executable boundaries

Keep process setup and exit policy in the executable. A small `main` can call an error-returning `run`, let its defers complete, then select an exit status. Lower-level packages should normally return errors instead of calling `os.Exit` or `log.Fatal`.

Document environment, configuration, and lifecycle requirements near the executable's entry point. Prefer explicit initialization over hidden package-level I/O when configuration and error recovery matter.

Related guidance: [composition](composition.md), [errors](errors.md), [modernization](modernization.md), and [reference sources](resources.md). See [package names](https://go.dev/blog/package-names) and [module documentation](https://go.dev/ref/mod) for the underlying conventions and commands.
