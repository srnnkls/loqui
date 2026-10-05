---
paths: "**/*.zig, **/build.zig.zon"
---

# Zig Design and Performance

The design should make valid state, ownership, and resource consumption visible together.
Start with a concrete domain model; introduce abstraction when it simplifies that model.

## Compose Around the Domain

Organize modules by feature. Keep the representation, operations, and tests of a concept close.
Avoid `utils`, `common`, and layers that force one transition to span unrelated directories.
Use plain functions for transformations and structs for state with a meaningful lifecycle.

Separate policy decisions from effect execution. Pass time, randomness, storage, and transport
through explicit inputs or narrow interfaces so the same decisions can run deterministically in
tests. Keep platform details and foreign interfaces at the boundary.

For modern Zig effects and task lifetimes, use the version-checked [async/I/O guide](async-io.md).
An I/O call can allow other work to progress; recheck state when an invariant spans such a call.

Prefer concrete types and direct calls. Use a tagged union for a closed set of runtime alternatives. A
function-pointer interface is appropriate for an open runtime boundary, with documented lifetime,
reentrancy, and ownership rules.

For generics, reflection, and specialization decisions, follow the [comptime chapter](comptime.md).

## Centralize State Transitions

Let one function own a transition's branching and state updates. Let leaf helpers calculate from
explicit inputs. Keep the precondition, mutation, and postcondition close enough to review as one
unit. Extract coherent helpers to stay within 70 lines; do not distribute a state machine merely
to satisfy the count.

For each event, define the accepted source states, destination state, and effects. Publish the
new state only after its required data is ready. A callback or fallible I/O call can expose
intermediate state: establish the contract before crossing that boundary.

Process external events through owned queues or batches where the architecture allows it. A
completion should identify the operation or generation it belongs to, so cancellation and reuse
cannot apply an old result to new state. Define shutdown, draining, cancellation, and late arrivals.

Prefer one owner for mutable state. When sharing is necessary, specify synchronization and which
invariant the lock protects. Atomic fields do not by themselves preserve multi-field invariants.
`volatile` is for volatile accesses, not inter-thread synchronization.

## Bound Resources Before Optimizing

Write a small budget for each component:

| Resource | Design question |
|----------|-----------------|
| Memory | Maximum live items × bytes per item, buffers, scratch space, allocator overhead? |
| CPU | Maximum work per item and per turn, including malformed-input paths? |
| I/O | Bytes and operations per request; batching, latency, and concurrency limits? |
| Time | Deadline, retry count, backoff cap, cancellation response time? |

A finite input is not a useful bound if its permitted size can exhaust the process. Enforce
limits before allocation or traversal. Bound decompressed output as well as compressed input.
Tree traversal should use a bounded explicit stack; any recursion exception needs a demonstrated
depth limit and stack budget independent of untrusted input.

A service loop may run indefinitely, but each turn must yield bounded work and have defined idle
and shutdown behavior. An assertion that a loop is infinite does not prove progress or fairness.
Capacity exhaustion is an ordinary condition with an explicit response, not an assertion failure.

## Design First, Then Measure

Estimate bandwidth and latency for network, disk, memory, and CPU, weighted by operation frequency.
Address the dominant cost first. Include worst-case work and tail latency, not only averages.

Batch expensive operations with both a maximum batch size and a maximum wait. Prefer contiguous
data and predictable traversal where they match the access pattern. Keep allocation and unrelated
control flow out of hot loops. Pass the required slices and scalar values directly when it makes
the loop's dependencies clearer.

Once runnable, benchmark representative sizes, full capacities, contention, and failure paths.
Compare the production optimization mode and target hardware. Record the workload and result with
the change. Do not remove checks, add caches, force inlining, or introduce SIMD on intuition alone.
A cache needs an invalidation invariant and a memory bound as well as a benchmark.

## Related

- [Priorities and Tiger Style policy](README.md), [ownership](memory.md), [testing](test.md).
- [Comptime policy](comptime.md) and
  [Zig reference: volatile](https://ziglang.org/documentation/0.16.0/#volatile).
