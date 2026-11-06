---
paths: "**/*.zig, **/build.zig.zon"
---

# Zig Comptime

**Baseline: Zig 0.16.0, researched and checked against the released compiler on 2026-09-11.**
This chapter owns the guide's compile-time policy, examples, and verification rules.

## Model: Move Knowledge to the Earliest Valid Stage

Use compile-time knowledge to establish representation and reject invalid configurations before
execution. Keep runtime data, operating failures, and effects in runtime code. Specialization
should expose a contract that a reviewer can explain, with a bounded cost to compile and execute.

`comptime` requires evaluation at compile time; it is not a request for the optimizer to try harder.
An ordinary function can run at either stage if its operations permit it. A `comptime` parameter
requires that argument to be known at the call site, but other arguments and the function's work
can remain runtime values. The language reference describes this as partial evaluation.
See [compile-time parameters and expressions][evaluation].

Distinguish the mechanisms:

| Mechanism | Use it to express |
|-----------|-------------------|
| `comptime T: type` | A caller-selected type that determines an API or representation |
| `comptime capacity: usize` | A configuration value needed to form a type or specialize behavior |
| `comptime expression` or `comptime { ... }` | Work that must finish during compilation |
| `comptime var` | Mutable state used only during compile-time evaluation |
| `anytype` | An inferred parameter type; its value can still be runtime data |
| `const` | An immutable binding; a local `const` initialized from runtime data remains runtime |

Container-level initializers are evaluated at compile time. Inside a `comptime` block, ordinary
loops already execute at compile time. Adding `inline` there is usually redundant.

## Specialize Only What Changes the Design

Prefer concrete signatures. Introduce a type parameter for a real family of operations or data
structures. Make relationships visible with `comptime T: type, items: []const T` when the type is
part of the caller's choice. Use `anytype` when inference improves the call site and the required
operations remain small enough to document clearly.

Keep allocators, `std.Io`, payloads, deadlines, and user configuration runtime parameters unless a
specific representation requires otherwise. Turning every flag or threshold into a compile-time
parameter multiplies specializations and couples data changes to recompilation. A closed set of
runtime states usually belongs in an enum or tagged union.

Document a generic's accepted types, operations, ownership, errors, and size limits. `anytype` does
not erase ownership obligations or implement a runtime interface. Prefer the existing `Allocator`,
`Io`, or byte-stream interface when it already expresses the dependency.

## Establish Compile-Time Invariants

Reject unsupported types, impossible capacity relationships, and invalid fixed layouts with a
clear `@compileError` at the generic or configuration boundary. An error should explain the violated
contract. Avoid large trait-emulation frameworks that reproduce checks the actual operation would
already perform clearly.

This complete example fixes capacity in the type while keeping contents and exhaustion at runtime:

```zig
const std = @import("std");

fn BoundedBuffer(comptime T: type, comptime capacity: usize) type {
    if (capacity == 0) @compileError("BoundedBuffer capacity must be positive");
    if (capacity > 4096) @compileError("BoundedBuffer capacity exceeds the item budget");

    return struct {
        storage: [capacity]T = undefined,
        len: usize = 0,

        const Self = @This();

        fn append(buffer: *Self, value: T) error{Full}!void {
            std.debug.assert(buffer.len <= capacity);
            if (buffer.len == capacity) return error.Full;
            buffer.storage[buffer.len] = value;
            buffer.len += 1;
        }

        fn items(buffer: *const Self) []const T {
            std.debug.assert(buffer.len <= capacity);
            return buffer.storage[0..buffer.len];
        }
    };
}

test "capacity is fixed but exhaustion is a runtime outcome" {
    var bytes: BoundedBuffer(u8, 2) = .{};
    try bytes.append(7);
    try bytes.append(9);
    try std.testing.expectError(error.Full, bytes.append(11));
    try std.testing.expectEqualSlices(u8, &.{ 7, 9 }, bytes.items());

    var identifiers: BoundedBuffer(u32, 1) = .{};
    try identifiers.append(1000);
    try std.testing.expectEqual(@as(u32, 1000), identifiers.items()[0]);
}
```

The generic bounds item count; the caller must also budget `capacity * @sizeOf(T)` and placement.
It stores values without managing resources inside them. The returned slice borrows the buffer.
Those are ownership and budgeting contracts, not consequences of successful specialization.

For formats, check relationships among header sizes, bit widths, and capacities. Use `@bitSizeOf`
for bit-level representation, and `@sizeOf`/`@alignOf` for storage or ABI requirements. Such checks
do not make native layout a portable encoding; see [external byte boundaries](memory.md#bytes-at-external-boundaries).

## Reflection and Inline Control Flow

Use `@TypeOf` and `@typeInfo` to implement a small, explicit structural contract. Use `@field` when
the selected field name is known at compile time. Keep reflective adapters near the boundary;
ordinary domain code should use its domain's names and types.

`inline for` specializes the body for each iteration. It is useful for heterogeneous fields or
tuples whose types differ; the operations on the selected values can still run at runtime.
For ordinary homogeneous traversal, use `for`. The official guidance permits forced unrolling
when semantics require it or a benchmark demonstrates a benefit. See [inline loops][inline-for].

This complete example has a deliberately narrow contract: a struct with at most 32 `u32` counters.
Metadata is used at compile time; the counter values are read when the function executes:

```zig
const std = @import("std");

fn count_active_counters(counters: anytype) usize {
    const fields = switch (@typeInfo(@TypeOf(counters))) {
        .@"struct" => |info| info.fields,
        else => @compileError("count_active_counters requires a struct"),
    };
    if (fields.len > 32) @compileError("counter field count exceeds the schema budget");

    var active: usize = 0;
    inline for (fields) |field| {
        if (field.type != u32) @compileError("counter fields must have type u32");
        if (@field(counters, field.name) != 0) active += 1;
    }
    return active;
}

test "reflection preserves the runtime counter values" {
    const Counters = struct { accepted: u32, rejected: u32 };
    var counters: Counters = .{ .accepted = 8, .rejected = 0 };
    try std.testing.expectEqual(@as(usize, 1), count_active_counters(counters));
    counters.rejected = 1;
    try std.testing.expectEqual(@as(usize, 2), count_active_counters(counters));
}
```

An `if` or `switch` whose condition is known at compile time analyzes only the selected branch.
For runtime tagged-union dispatch that needs a specialized body per variant, consider `switch`
with inline prongs instead of generating an `if` chain followed by `unreachable`: the switch can
retain exhaustiveness checking. See [inline switch prongs][inline-switch].

`inline fn` is separate from compile-time evaluation: it forces inlining at call sites and changes
how known arguments participate in specialization. Leave functions ordinary unless those semantics
are required or measurements justify the change. See [inline functions][inline-fn].

## Generate Bounded Data, Keep Effects Outside

Small lookup tables and fixed schemas are suitable compile-time outputs. Build an array locally
and return it by value, so the result carries its storage rather than a pointer into temporary
mutable state. A container-level constant can hold the generated array:

```zig
const std = @import("std");
const digit_table = make_digit_table();

fn make_digit_table() [256]bool {
    var table = [_]bool{false} ** 256;
    for ('0'..'9' + 1) |byte| table[byte] = true;
    return table;
}

test "generated table follows the ASCII digit contract" {
    const boundaries = [_]u8{ '/', '0', '5', '9', ':', 255 };
    for (boundaries) |byte| {
        const expected = byte >= '0' and byte <= '9';
        try std.testing.expectEqual(expected, digit_table[byte]);
    }
}
```

Compile-time evaluation cannot perform arbitrary runtime I/O or call external runtime functions.
Use build steps with declared inputs and outputs for external code generation; use `@embedFile`
for a build input that belongs in the binary. Avoid dependencies on ambient machine state. The
compiler's work should be deterministic from the pinned toolchain, source, and declared inputs.

## Budget Compilation and Keep Versions Explicit

Bound schema size, table size, recursion depth, and specialization count. Compile-time work can
still exhaust memory or make every developer wait. Prefer iterative generation and algorithms
whose costs are easy to estimate. For growing generators, measure clean and incremental builds
as well as generated binary size.

`@setEvalBranchQuota` raises the evaluator's backward-branch allowance; it is not a performance
optimization or a general memory/time limit. Diagnose the algorithm first. Raise a quota only
locally, with a documented finite workload, rather than hiding unexpectedly expensive generation.
See [evaluation quota][quota].

Zig 0.16 replaced `@Type` with specific constructors including `@Int`, `@Tuple`, `@Struct`, and
`@Union`. For example, `@Int(.unsigned, 12)` creates `u12`. Prefer ordinary type syntax when the
shape is already known, and use a type-returning function with `return struct { ... }` before
reaching for low-level type construction. Check reflection fields and builtin signatures in the
pinned release instead of pasting older metaprogramming code. See the [0.16 migration][migration].

## Verify Compile-Time Contracts

Instantiate every supported generic shape and call the relevant methods. Lazy analysis means that
declaring a generic or importing its module does not demonstrate that all specializations compile.
When a function supports both evaluation stages, exercise both; compile-time success alone does
not verify runtime failure handling or ownership.

Compile expected-failure fixtures separately and require a nonzero exit plus the intended
diagnostic. For the examples above, force analysis with `comptime { _ = BoundedBuffer(u8, 0); }`
and with capacity `4097`; each must reject its configuration. A call using a non-`u32` counter
must reject the field type. Do not place intentionally failing fixtures in the normal test root.

Test generated data against independent constants or a simple reference implementation. Verify
boundary and invalid inputs, supported targets, and the shipping optimization mode through the
normal [test workflow](test.md#run-the-actual-build). Use `std.testing` expectations for tests;
runtime assertions can disappear in safety-disabled builds.

## Primary Sources

- [Zig 0.16.0 language reference: comptime][evaluation] — evaluation and generic semantics.
- [Inline loops][inline-for], [inline switch prongs][inline-switch], [inline functions][inline-fn],
  and [evaluation quota][quota] — distinct mechanisms and costs.
- [Zig 0.16.0 release notes][migration] — current type-creation APIs.
- The released compiler's `lib/std/meta.zig` and `lib/std/mem.zig` — examples of bounded reflection,
  explicit unsupported-type diagnostics, and specialization over field metadata.

[evaluation]: https://ziglang.org/documentation/0.16.0/#comptime
[inline-for]: https://ziglang.org/documentation/0.16.0/#inline-for
[inline-switch]: https://ziglang.org/documentation/0.16.0/#Inline-Switch-Prongs
[inline-fn]: https://ziglang.org/documentation/0.16.0/#inline-fn
[quota]: https://ziglang.org/documentation/0.16.0/#setEvalBranchQuota
[migration]: https://ziglang.org/download/0.16.0/release-notes.html#Type-Replaced-with-Individual-Type-Creating-Builtin-Functions
