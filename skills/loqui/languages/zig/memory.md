---
paths: "**/*.zig, **/build.zig.zon"
---

# Zig Memory and Ownership

Every resource has an owner. Every borrow has an expiration condition. Every allocation has a
budget and a failure policy. These are design obligations even when the compiler accepts the code.

## State Ownership in the API

Document whether arguments are borrowed, copied, or consumed, whether ownership transfers on
success only, and who releases the result. Specify which operations invalidate returned pointers.

| Representation | Contract it can express | What it does not prove |
|----------------|-------------------------|------------------------|
| `[]const u8` | A byte view read-only through this slice | Ownership, lifetime, or immutable aliases |
| `[]u8` | A writable byte view | Exclusive access or permission to free it |
| `*const T` | Read access through this pointer | Deep immutability or pointer stability |
| `*T` | Access to mutate this value | Unique ownership or absence of aliases |
| `?*T` | Pointer or absence | Whether a non-null pointer is still alive |

Use slices when length matters. Keep raw many-item pointers and C pointers inside adapters that
also establish extent, alignment, and lifetime. A pointer cast does not establish those facts.

## Choose the Lifetime Before the Allocator

Prefer caller-owned buffers for bounded output. For latency-sensitive components, reserve storage
during initialization and enforce capacity during steady-state work. Admission control must decide
what happens when full: reject, defer, or apply backpressure.

Use an arena when a group of allocations truly shares one lifetime. Arena reset invalidates every
borrow into it; nothing may escape into a longer-lived owner. Arena allocation is still allocation
and may grow backing storage unless bounded. Use a fixed buffer when the budget is a hard limit.

For general dynamic allocation, pass `std.mem.Allocator` explicitly. Return allocation failure to
an owner that can handle it. Store the allocator or require it at release according to the API;
deallocation must use the matching allocator and allocation extent.

## Pair Acquisition and Cleanup

Register `defer` for resources owned by the current scope. In a constructor, use `errdefer` while
building the result, then transfer ownership on success. Keep acquisition and cleanup adjacent.

This complete example owns a copy of a bounded nonempty payload:

```zig
const std = @import("std");

const Packet = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    const bytes_max: usize = 4096;
    const InitError = error{ Empty, TooLarge } || std.mem.Allocator.Error;

    fn init(allocator: std.mem.Allocator, source: []const u8) InitError!Packet {
        if (source.len == 0) return error.Empty;
        if (source.len > bytes_max) return error.TooLarge;

        const bytes = try allocator.alloc(u8, source.len);
        errdefer allocator.free(bytes);

        @memcpy(bytes, source);
        return .{ .allocator = allocator, .bytes = bytes };
    }

    fn deinit(packet: *Packet) void {
        packet.allocator.free(packet.bytes);
        packet.* = undefined;
    }
};

test "packet owns an independent copy" {
    var source = [_]u8{ 1, 2, 3 };
    var packet = try Packet.init(std.testing.allocator, &source);
    defer packet.deinit();

    source[0] = 9;
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, packet.bytes);
}
```

`deinit` is called exactly once. Assigning `undefined` documents that this value is dead; it does
not make double-free safe or invalidate other copies. The `errdefer` covers future fallible setup
after allocation; the successful return transfers responsibility to the caller.

## Copies and Pointer Stability

Assignment and by-value APIs do not provide a linear ownership discipline. Treat an owning value
as transferred by convention and stop using the old value, or make an explicit deep copy.
Never duplicate an owning container and later call `deinit` on both copies.

A growable container can relocate its allocation; insertion or removal can also shift elements.
Do not retain element pointers across invalidating operations. Reserve sufficient capacity when
that proves stability, or use stable storage or handles with generation checks. Indices survive
relocation but need a separate policy for reordering and deletion.

Initialize self-referential or address-sensitive objects at their final address using an out
pointer. The contract must forbid moving them afterwards, including moving a containing struct.
An out pointer alone does not make a Zig type immovable. Define cleanup of partially initialized
fields if initialization can fail.

Use `undefined` only when every read is preceded by initialization. Track initialized length
separately from capacity; expose and serialize only initialized bytes. Never return a slice into
a local stack array or a destroyed arena.

## Bytes at External Boundaries

Encode formats field by field with explicit endianness and lengths. Native struct layout can
include padding and is not a portable wire format. `extern struct` describes ABI layout;
`packed struct` does not settle endianness, versioning, or validity of incoming values.

Use `@memcpy` only for non-overlapping regions of equal extent. For possible overlap, use the
toolchain's overlap-safe copy operation. Never transmit unused capacity or uninitialized padding.

## Related

- [Error semantics](invariants.md#define-failure-semantics), [allocation failure tests](test.md).
- [Zig reference: memory](https://ziglang.org/documentation/0.16.0/#Memory) and
  [pointers](https://ziglang.org/documentation/0.16.0/#Pointers).
