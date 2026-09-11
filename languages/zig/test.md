---
paths: "**/*.zig, **/build.zig.zon"
---

# Zig Testing

Tests challenge the model. Assertions encode the implementation's understanding; tests should use
independent expectations to find where that understanding is wrong.

## Exercise the Contract

Place focused tests near the component. Import all tested modules into the test root: a successful
`zig test` can miss code that was never discovered or analyzed. Follow
[compile-time contract verification](comptime.md#verify-compile-time-contracts) for generics and
expected compilation failures. Exercise target-specific branches on their supported targets.

For each invariant, cover ordinary valid data, its boundaries, and violations. Include zero, one,
maximum, and just-over-maximum sizes; truncated input; invalid tags; full queues; duplicate and
late completions; and exhausted retry budgets where relevant.

For the [frame parser](invariants.md#parse-at-the-boundary), append this test to its example:

```zig
test "frame parsing enforces the declared extent" {
    const frame = try Frame.parse(&.{ 0, 2, 7, 8 });
    try std.testing.expectEqualSlices(u8, &.{ 7, 8 }, frame.payload);
    try std.testing.expectEqual(@as(usize, 0), (try Frame.parse(&.{ 0, 0 })).payload.len);

    try std.testing.expectError(error.Truncated, Frame.parse(&.{}));
    try std.testing.expectError(error.Truncated, Frame.parse(&.{0}));
    try std.testing.expectError(error.Truncated, Frame.parse(&.{ 0, 2, 7 }));
    try std.testing.expectError(error.TrailingBytes, Frame.parse(&.{ 0, 1, 7, 8 }));
    try std.testing.expectError(error.PayloadTooLarge, Frame.parse(&.{ 0x10, 0x01 }));

    var maximum = [_]u8{0} ** (2 + 4096);
    maximum[0] = 0x10;
    try std.testing.expectEqual(@as(usize, 4096), (try Frame.parse(&maximum)).payload.len);
}
```

The expected limit and byte sequences come from the format contract, rather than reproducing the
parser's calculation. For an encoder/decoder pair, use known byte fixtures as well as round trips:
two mutually consistent bugs can pass a round-trip test.

## Prove Cleanup and Failure Behavior

Use `std.testing.allocator` in allocation tests so the test runner can detect leaks. Exercise
allocation failure at each allocation point with the pinned release's allocation-failure testing
facility (such as `std.testing.checkAllAllocationFailures`) or an injected failing allocator.

Check more than the returned error: ownership must remain unambiguous, earlier resources must be
released, and state must satisfy the promised rollback or partial-progress contract. Include
failure after earlier acquisitions, not only the first allocation. Test exact-capacity success
and capacity exhaustion for caller buffers and preallocated containers.

See [async-io.md](async-io.md#validate-the-execution-contract) for futures, cancellation, groups,
and buffered I/O tests. Task cleanup and cleanup of a successful task result are separate duties.

Inject I/O failures, short reads/writes, cancellation, and shutdown where supported. Temporary
files, worker tasks, and handles must be cleaned up by the test that creates them. Do not rely on
process exit to hide lifecycle defects.

## Test State Machines Independently

For nontrivial transitions, compare the implementation with a small reference model. Generate
event sequences and assert the contract after each step. Inject time, randomness, and completions
so failures can be reproduced from a seed and event trace.

Fuzz parsers with bounded input and output sizes. Fuzz state machines with legal and illegal
event sequences, including cancellation and reuse. Keep minimized regression cases. Simulation
and fuzzing find counterexamples; they do not prove correctness or replace a reviewable model.

## Run the Actual Build

For a standalone component (replace `component.zig` with its path):

```sh
zig fmt --check component.zig
zig test component.zig
zig test component.zig -O ReleaseSafe
```

For a repository, use its documented format and test steps. `zig build test` works only if
`build.zig` defines that step; confirm what modules it runs. Also test the shipping optimization
mode if it differs, so behavior does not accidentally depend on enabled assertions. Compilation
without execution is useful target coverage, but should be reported as such.

Record the exact compiler version, modes, targets, and tests actually run. A document example is
verified only when its complete context has been compiled and its tests executed.

## References

- [Zig reference: tests](https://ziglang.org/documentation/0.16.0/#Zig-Test).
- [Zig reference: build modes](https://ziglang.org/documentation/0.16.0/#Build-Mode).
- [Memory ownership](memory.md) and [invariants](invariants.md).
