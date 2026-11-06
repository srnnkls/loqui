---
paths: "**/*.zig, **/build.zig.zon"
---

# Zig Invariants and Errors

An invariant is a property of valid state. State who establishes it, which operations preserve it,
and where it is checked. Begin with the [working model](README.md#working-model).

## Encode the Domain

Use a tagged union when each state carries different data. A request that is queued, running, or
finished should not be a collection of independent booleans and nullable payloads. Use exhaustive
`switch` statements so a new state forces each transition site to be reconsidered.

Distinguish identifiers and quantities with wrapper structs. `const AccountID = u64` is an alias,
not a distinct type. Use `const AccountID = struct { value: u64 };` when mixing IDs would be a bug.
Include units in names when the type does not carry them.

Constructors establish relationships that primitive types cannot express. **Zig struct fields are
accessible to callers**: a constructor is a contract, not an enforced privacy boundary. Document
permitted mutation and assert relationships at operations that rely on them. Use a handle-based
API when callers must not have direct access to the representation.

## Parse at the Boundary

External bytes, user configuration, filesystem contents, and remote messages may be invalid.
Return errors for invalid data before narrowing integers, indexing, allocating, or changing state.

This complete example parses a two-byte big-endian length followed by exactly one payload. Its
result borrows the input; the caller must keep those bytes alive and unchanged while using it.

```zig
const std = @import("std");
const assert = std.debug.assert;

const Frame = struct {
    payload: []const u8,

    const header_bytes: usize = 2;
    const payload_bytes_max: usize = 4096;
    const ParseError = error{ Truncated, PayloadTooLarge, TrailingBytes };

    fn parse(bytes: []const u8) ParseError!Frame {
        if (bytes.len < header_bytes) return error.Truncated;

        const payload_bytes = (@as(u16, bytes[0]) << 8) | @as(u16, bytes[1]);
        if (payload_bytes > payload_bytes_max) return error.PayloadTooLarge;

        const available = bytes.len - header_bytes;
        if (payload_bytes > available) return error.Truncated;
        if (payload_bytes < available) return error.TrailingBytes;

        const frame: Frame = .{ .payload = bytes[header_bytes..] };
        assert(frame.payload.len == payload_bytes);
        assert(frame.payload.len <= payload_bytes_max);
        return frame;
    }
};
```

The branches validate input in every build mode. The assertions state the established contract.
If a streaming protocol allows trailing frames, give its parser a consumed-byte count and a
separate incomplete-input result; do not silently change this parser's contract.

## Assert What the Model Requires

Assert preconditions, postconditions, and state relationships where they matter. Prefer separate
assertions for separate facts. Check a property at both production and consumption when that can
catch different mistakes. Derive checks independently where possible: repeating the same faulty
calculation on each side provides little protection.

For static contracts, see [compile-time invariants](comptime.md#establish-compile-time-invariants).
Use runtime assertions for internal state such as `count <= capacity` or a completion belonging to
the active operation. Never put mutation or other required work inside an assertion.

`std.debug.assert` is not input validation or a guarantee of a crash in every build mode.
`unreachable` declares that execution cannot arrive there; reaching it is illegal behavior, and
safety-disabled builds may optimize on that assumption. If a detected internal failure must stop
execution in every mode, use an explicit check and `@panic` (and define the application's panic
policy). Never catch a programming defect and continue with corrupted state.

## Make Arithmetic Part of the Contract

- Use fixed-width integers for formats, IDs, counters with a defined domain range, and persistent
  data. Use `usize` for slice lengths and local indexes; check conversions at the boundary.
- Distinguish indexes, element counts, and byte sizes. Check multiplication before allocation.
- Check `offset <= bytes.len`, then `length <= bytes.len - offset` before slicing. Testing an
  already-overflowed `offset + length` is too late.
- Use checked arithmetic or overflow builtins for quantities that may exceed their range.
  Wrapping and saturating arithmetic need a domain reason; they are not fixes for failing checks.
- `@intCast` asserts representability through safety checks; it does not return a recoverable
  error. Check external values first. `@truncate` intentionally discards bits.
- Specify rounding behavior for division. Use exact division only after establishing divisibility.

## Define Failure Semantics

Use small explicit error sets at stable domain boundaries. Inferred error sets are useful for
internal propagation; avoid exposing `anyerror` merely to avoid deciding what callers can handle.
Use `?T` for ordinary absence, `E!T` for failure, and a tagged union for meaningful domain outcomes.

`try` propagates a failure to its owner. `catch` should recover, translate, or add an intentional
boundary policy. Never use `catch {}`, `catch unreachable`, or success-shaped defaults to conceal
expected I/O, parse, or allocation failures.

For each fallible mutation, document whether failure leaves state unchanged or reports partial
progress. Reserve resources and validate first when an operation promises atomicity. `errdefer`
releases acquired resources; it does not automatically undo domain mutations or external writes.

Errors carry names, not arbitrary context payloads. Preserve useful context in a typed result or
at the reporting boundary. Log once where the failure is handled; do not log at every `try` site.

## Related

- [Memory and cleanup](memory.md), [state transitions](design.md), [failure tests](test.md).
- [Zig reference: errors](https://ziglang.org/documentation/0.16.0/#Errors),
  [illegal behavior](https://ziglang.org/documentation/0.16.0/#Illegal-Behavior), and
  [style guide](https://ziglang.org/documentation/0.16.0/#Style-Guide).
