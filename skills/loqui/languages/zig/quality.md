---
paths: "**/*.zig, **/build.zig.zon"
---

# Zig Quality and Toolchain

Names and structure should expose the [model and priorities](README.md). Formatting is the final
mechanical pass; review begins with the contract.

## Naming and Layout

- Use `snake_case` for project functions, variables, fields, and files. Use `PascalCase` for types
  and preserve meaningful acronyms: `RequestID`. Type-returning functions use type-style names.
  This deliberately follows Tiger Style's function/file convention; Zig's general style uses
  camel case functions and Pascal case files when the file represents a type.
- Preserve names of standard library and external APIs at call sites. Do not wrap them solely to
  rename them. Prefer full domain words to abbreviations.
- Put units and qualifiers after the subject: `latency_ms_max`, `payload_bytes`, `request_count`.
  Make related names consistent so relationships are easy to compare.
- Use an options struct when same-typed arguments can be swapped or a boolean/null literal would
  be ambiguous. Specify options affecting correctness and performance explicitly at call sites.
- Put the main public operation near the top, with helpers following in reading order. Within
  structs, use fields, nested types/constants, then methods. Keep the public surface small.
- Prefer `const`; introduce `var` only for mutation. Declare values near use, within the smallest
  practical scope. Avoid redundant cached state unless its invariant and benefit are clear.
- Document public contracts with `///` and module purpose with `//!`. Explain ownership, invalidation,
  errors, bounds, and rationale. Comments should be complete sentences; omit narration of syntax.
- Run `zig fmt`. Use four spaces, at most 100 columns, and at most 70 lines per function for new
  code. The formatter does not enforce all of these design limits. Use braces for multiline bodies.

## Pin and Inspect the Toolchain

These examples target Zig 0.16.0. Each consuming repository must pin its own exact compiler in its
development and CI setup; `minimum_zig_version` in `build.zig.zon` is only a lower bound. Keep
dependency hashes and the compiler pin reproducible.

Before generating or updating Zig code, run `zig version`, inspect the repository's `build.zig`
and `build.zig.zon`, then consult the matching compiler's `lib/std` and versioned documentation.
Prefer the build system's existing steps to invented commands or copied build APIs.

Version drift deserves particular attention:

- Zig 0.16 moves I/O operations to the `std.Io` model, with an explicit I/O dependency. Check the
  release's file, networking, process, and cancellation APIs instead of pasting older examples.
  Follow [async-io.md](async-io.md) for the verified execution and ownership contracts.
- Check collection initialization, allocator arguments, and `deinit` against the pinned release.
  Managed and unmanaged collection examples are not interchangeable.
- Follow [comptime version guidance](comptime.md#budget-compilation-and-keep-versions-explicit)
  for reflection and type-creation APIs. `zig fmt` cannot repair semantic API mismatches.
- Match editor tooling to the supported compiler. Treat an upgrade as a migration with builds and
  tests, rather than changing the version label alone.

The [0.16.0 release notes](https://ziglang.org/download/0.16.0/release-notes.html) describe the I/O
migration. The [versioned reference](https://ziglang.org/documentation/0.16.0/) defines semantics.

## Dependencies and Build Behavior

Start with the standard library. Before adding a package, identify the capability it supplies,
why the platform is insufficient, its supported targets, and its ownership and failure model.
Keep dependency revisions reproducible and review build-script behavior as executable code.

Keep build logic small and explicit. Make tests discoverable through a documented build step.
Declare supported targets and optimization modes, and run relevant checks for each. Cross-compiling
alone does not validate runtime behavior on the target.

Prefer Debug for development and ReleaseSafe for shipping unless a measured, documented need
justifies another mode. Debug and ReleaseSafe enable runtime safety checks by default;
ReleaseFast and ReleaseSmall disable them by default. Validation and required state changes must
work in all supported modes. Avoid local `@setRuntimeSafety(false)` without a bounded argument and
measurements. Runtime safety checks are not a borrow checker or a proof of memory safety.

## Review Questions

- Can the reviewer describe the state machine and invariants without reconstructing hidden state?
- Are input checks performed before casts, allocation, slicing, and side effects?
- Are ownership transfer, cleanup, invalidation, and failure behavior explicit?
- Are work, memory, queues, retries, and waiting bounded with defined exhaustion behavior?
- Does each abstraction expose a domain concept and keep effects observable?
- Do tests exercise the contract's boundaries, errors, and production build mode?
- Do claimed performance improvements have estimates or measurements appropriate to this stage?

See [test.md](test.md) for validation commands and evidence.
