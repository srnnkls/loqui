---
paths: "**/*.zig, **/build.zig.zon"
---

# Modern Zig Async and I/O

**Baseline: Zig 0.16.0, verified 2026-09-11.** This guidance was checked against the official
release notes and `lib/std` bundled with the released compiler. The download index lists 0.17
development builds separately; do not mix those APIs into a 0.16 project.

## The Model: Explicit I/O, Owned Tasks

`std.Io` is an interface to I/O and concurrency. Pass `io: std.Io` into effectful operations, just
as you pass an allocator into allocating operations. The application selects and owns the
implementation; reusable libraries accept the interface. `std.process.Init` supplies `init.io`
for applications using that entry point. Tests can use `std.testing.io`.

`std.Io.Reader` and `std.Io.Writer` are byte-stream interfaces. A memory-backed reader needs no OS
I/O; a file reader stores the file and the `Io` dependency in its enclosing adapter. Pass a reader
or writer to parsing/encoding code that needs only a byte stream, rather than a whole file or
execution backend.

Ordinary Zig functions participate in this model. Use the current `io.async`, `io.concurrent`,
and future methods; do not generate historical `async`/`await` language-keyword or frame recipes.
Do not assume a particular scheduler, event loop, OS thread per task, or free task allocation.

## Asynchrony Is Weaker Than Concurrency

| API | Guarantee and obligation |
|-----|--------------------------|
| `io.async(function, args)` | Returns a future; may execute the function completely before returning |
| `io.concurrent(function, args)` | Provides concurrent progress; task creation can fail with `error.ConcurrencyUnavailable` |
| `future.await(io)` | Waits for completion and returns the task's result |
| `future.cancel(io)` | Requests cancellation, waits for completion, and returns the task's result |

Choose `async` when serial execution is correct. Choose `concurrent` when a producer, consumer,
server, or handshake must progress alongside its caller. Falling back to a direct call after
`ConcurrencyUnavailable` is wrong if that destroys the progress guarantee. Reject work or select
another explicitly valid architecture instead.

Task creation and task completion are separate failure sites. `try io.concurrent(...)` handles
creation failure; the future's result carries the worker's error. Limit live tasks and queued work
before spawning. Futures and groups are not admission control or a guarantee of allocation-free
steady-state execution.

## A Task May Not Outlive Its Borrows

Register cancellation immediately after obtaining a future, so every exit waits for the task.
Its arguments, buffers, allocator, and I/O implementation must outlive that wait. Do not copy an
active future or concurrently call its `await` and `cancel` methods; the methods are not threadsafe.

This complete test demonstrates independent bounded tasks. Serial execution is valid. Each worker
returns only a scalar or cancellation, so cleanup can discard the scalar and handle cancellation
without losing an owned result:

```zig
const std = @import("std");
const Io = std.Io;

fn sum_bytes(io: Io, bytes: []const u8) Io.Cancelable!u64 {
    std.debug.assert(bytes.len <= 4096);
    var total: u64 = 0;
    for (bytes, 0..) |byte, index| {
        if (index % 256 == 0) try io.checkCancel();
        total += byte;
    }
    return total;
}

test "independent tasks finish within the borrowing scope" {
    const io = std.testing.io;
    const left = [_]u8{ 1, 2, 3 };
    const right = [_]u8{ 4, 5 };

    var left_task = io.async(sum_bytes, .{ io, &left });
    defer _ = left_task.cancel(io) catch |err| switch (err) {
        error.Canceled => {},
    };

    var right_task = io.async(sum_bytes, .{ io, &right });
    defer _ = right_task.cancel(io) catch |err| switch (err) {
        error.Canceled => {},
    };

    try std.testing.expectEqual(@as(u64, 6), try left_task.await(io));
    try std.testing.expectEqual(@as(u64, 9), try right_task.await(io));
}
```

For a task returning an owned file or allocation, cancellation may return success because the task
already completed. That successful result still needs cleanup. Assign one owner to release it.
In 0.16, `await` and `cancel` are idempotent and return the stored result again: freeing an awaited
result and then freeing the successful result of deferred cancellation is a double-free. Either
let one deferred owner release the result, or explicitly track transfer and release only unclaimed
results during teardown.

## Cancellation Is a Protocol

Propagate `error.Canceled` out of ordinary worker logic. Cancellation is observed at cancellation
points, not by forcibly stopping arbitrary instructions. In 0.16 a request is delivered once;
swallowing it can let a task continue indefinitely. Long CPU work needs bounded chunks and explicit
`io.checkCancel()` points. Cleanup must preserve invariants even when cancellation occurs between
two fallible operations.

Cancellation is not a timeout guarantee or rollback. A task may finish successfully, an external
write may already have happened, and a cancellation wait may take time. Define commit points,
partial-progress semantics, and the maximum interval between cancellation points. Keep any use of
`Io.CancelProtection` small and justified; never shield an unbounded operation.

Use `Io.Mutex`, `Io.Condition`, `Io.Event`, and the other I/O-aware synchronization primitives when
coordinating I/O tasks. Do not mechanically retain `std.Thread` synchronization while migrating a
thread pool: blocking a thread can prevent the chosen backend from making progress. Do not hold
locks across arbitrary I/O or callbacks without an explicit ordering and cancellation argument.

## Groups, Deadlines, and Batches

Use `Io.Group` for tasks sharing one owner and lifetime. Initialize with `.init`, immediately
register `defer group.cancel(io)`, add bounded work, and `try group.await(io)` before consuming its
results. `Group.async` has the same serial-execution caveat as `io.async`; `Group.concurrent` can
fail during task creation.

Group workers return a value coercible to `Io.Cancelable!void`. A group is not an arbitrary result
or worker-error collector: record application outcomes through owned result slots or a bounded
queue, or use futures when results belong to individual calls. Child cancellation is absorbed at
the group boundary; `group.await` is not evidence that every child succeeded. Avoid detached tasks
and unbounded growth of work even though completed group tasks release their task resources.

Use deadlines measured against a suitable monotonic clock for elapsed-time budgets. Carry one
operation deadline through retries rather than restarting a fresh timeout after each attempt.
The 0.16 `Io.Operation`, `io.operateTimeout`, and `Io.Batch` APIs support only their declared
operation set; do not assume every high-level file or network call accepts a timeout.

Use `Io.Batch` when several supported operations can be submitted together and measurements show
that task overhead matters. It operates below the function-level future abstraction. Bound its
storage and keep operation buffers alive until completion or cancellation. For a timeout race
built with tasks or `Io.Select`, cancellation and disposal of losing results are part of the
operation, including resources returned successfully after the deadline.

## Buffered I/O Has Its Own Ownership and Failure Rules

Use caller-owned buffers with a lifetime covering the reader/writer and outstanding operations.
Keep the enclosing file adapter at a stable address while using its `.interface` pointer. Borrowed
reader slices can be invalidated by refill or rebasing; copy data that must survive further reads.
Do not share mutable reader/writer state between tasks without serialization.

Handle framing and short I/O explicitly. Use bounded lengths or `Io.Limit` where supported before
reading untrusted input. An unrestricted read-to-end or stream-to-end can violate both memory and
time budgets. A full buffer, end of stream, and transport failure are different outcomes.

Flush output explicitly and observe failure before reporting success. A successful write into a
buffer is not delivery; flushing a file writer is not a durability guarantee. Generic stream errors
can hide the underlying cause: file adapters retain it in `.err`, including cancellation. Recover
that error at the adapter boundary when callers need to distinguish it.

This complete program separates encoding from the stdout adapter and tests encoding in memory:

```zig
const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    var buffer: [256]u8 = undefined;
    var output = Io.File.stdout().writer(init.io, &buffer);

    write_status(&output.interface, 42) catch |err| return output.err orelse err;
    try output.flush();
}

fn write_status(writer: *Io.Writer, item_count: u32) Io.Writer.Error!void {
    try writer.print("processed {d} items\n", .{item_count});
}

test "status encoding uses a caller-owned buffer" {
    var buffer: [64]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);
    try write_status(&writer, 42);
    try std.testing.expectEqualStrings("processed 42 items\n", writer.buffered());
}
```

Here `File.Writer.flush` returns the underlying file error. For adapters without that convenience,
translate `ReadFailed`/`WriteFailed` using the adapter's documented error state. Do not turn a
canceled operation into a generic retryable transport failure.

## Validate the Execution Contract

Test serial-valid tasks with a backend configured to avoid concurrency when supported. For
concurrency-required tasks, test creation failure and demonstrate progress without timing-based
sleep guesses. Exercise cancellation before work, during I/O, and after successful resource
creation, plus parent failure while siblings are active. Check that every task finishes before its
borrowed storage is destroyed and each returned resource is released exactly once.

Memory-backed stream tests cover encoding and parsing. Add adapter tests for fragmented reads,
short writes, flush failures, bounded input, and cancellation-error translation. Test the actual
backend and target separately; passing with `std.testing.io` does not certify all implementations.

## Primary Sources

- [Official download index](https://ziglang.org/download/index.json) — release/development versions.
- [Zig 0.16.0 release notes](https://ziglang.org/download/0.16.0/release-notes.html) — I/O migration.
- [Zig 0.16.0 standard library](https://ziglang.org/documentation/0.16.0/std/) — inspect `Io`,
  `Io.Future`, `Io.Group`, `Io.Reader`, `Io.Writer`, `Io.File`, and `process.Init`.
- The official compiler archive's `lib/std/Io.zig`, `lib/std/Io/File/Reader.zig`,
  `lib/std/Io/File/Writer.zig`, and `lib/std/process.zig` — source contracts used for this guide.

See [memory.md](memory.md) for ownership, [invariants.md](invariants.md) for failure semantics,
and [test.md](test.md) for validation commands.
