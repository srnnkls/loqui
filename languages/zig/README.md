---
paths: "**/*.zig, **/build.zig.zon"
---

# Zig Style Guide

Write Zig as a system of bounded state transitions over explicitly owned memory. The code should
carry the domain model, the conditions that make it valid, and the cost of moving between states.

Our starting point is [Tiger Style][tiger-style]. We adopt its priority order and design discipline,
then apply loqui's principles: domain vocabulary, composition, parsing at boundaries, and explicit
effects. Read this page first; syntax recipes make sense only within that model.

## Priorities

1. **Safety and correctness.** Preserve domain invariants, memory validity, and resource bounds.
   Reject malformed input. Handle operating failures. Stop on internal corruption.
2. **Performance.** Design for bounded memory, bounded work, locality, and predictable latency.
   Estimate costs before implementation; measure them once an implementation exists.
3. **Developer experience.** Make ownership, control flow, and failure behavior easy to inspect.
   Spend time on names and small, useful abstractions that express the domain.

Use this order to resolve tradeoffs. A faster implementation that violates an invariant is
incorrect. Among correct designs, favor predictable resource use. Simplicity should improve all
three priorities by reducing the states and interactions we must understand.

Fix known violations of the model before building on them. Reduce scope when necessary; do not
quietly defer correctness or resource-bound failures as future cleanup.

## Working Model

```text
bytes / clock / I/O completion
              |
              v
adapter: check sizes, parse, establish ownership
              |
              v
bounded domain operation: preconditions -> transition -> postconditions
              |
              v
adapter: apply effects, observe failures, release resources
```

The adapter owns interaction with the outside world. The domain core receives explicit values and
computes decisions. The owner of state applies transitions and accounts for their resources.
In-place mutation is appropriate when its ownership and invariants are local and clear.

Before implementing a component, write down:

| Question | What the design must reveal |
|----------|-----------------------------|
| What does this represent? | Domain names, units, valid states, canonical representation |
| What must always hold? | Preconditions, postconditions, cross-field relationships |
| Who owns it? | Allocation, borrowing, transfer, destruction, pointer invalidation |
| How much can it consume? | Capacity, work per operation, retry budget, deadline |
| What happens on failure? | Errors, rollback or partial progress, observable state |
| How do we know? | Type constraints, runtime checks, assertions, independent tests |

Keep this contract beside the type or operation. Names express what; comments explain why a
constraint exists and what proves it. Good naming does not replace ownership or invariant
documentation.

## Core Rules

- Parse external values into domain types before using them. Use enums and tagged unions for
  alternatives, wrapper structs for distinct quantities, and checked constructors for constraints.
- Treat ownership as an API contract. Zig does not enforce borrow lifetimes or unique ownership.
  Copying an owning struct can duplicate responsibility for the same allocation.
- Keep control flow explicit. Prefer bounded iteration; use an explicit bounded stack for trees.
  Every queue, retry loop, input buffer, and batch needs a limit and a defined limit-hit behavior.
- Distinguish expected failures from programming mistakes. Return error unions for operating
  failures; assert internal invariants. Validation must survive the shipping optimization mode.
- Pass allocators and effectful dependencies explicitly. Prefer caller buffers or preallocated
  storage for steady-state work. Pair acquisition with cleanup immediately.
- Centralize state transitions. Helpers should compute results from explicit inputs; avoid hidden
  mutation, global dependencies, and callbacks that reenter partially updated state.
- Prefer the standard library and a small dependency surface. A dependency must earn its cost in
  capability, maintenance, memory, and failure behavior.
- Pin the compiler. Compile examples and consult the standard library shipped with that version.
  Do not combine APIs from different Zig releases.

## Guide Map

| Resource | When to use |
|----------|-------------|
| [invariants.md](invariants.md) | Domain types, validation, assertions, arithmetic, error contracts |
| [memory.md](memory.md) | Allocation, ownership, slices, cleanup, pointer stability |
| [design.md](design.md) | State machines, composition, I/O, bounded performance |
| [comptime.md](comptime.md) | Generics, reflection, compile-time invariants, specialization budgets |
| [async-io.md](async-io.md) | Modern `std.Io`, futures, concurrency, cancellation, readers/writers |
| [quality.md](quality.md) | Naming, layout, toolchain, dependencies, review criteria |
| [test.md](test.md) | Boundary cases, allocation failures, model tests, build modes |

## Applying Tiger Style

TigerBeetle's constraints serve a particular storage system. The following are loqui policy
decisions; they are not claims about what Zig requires.

| Tiger Style rule | Our application |
|------------------|-----------------|
| Safety, performance, developer experience | Same priority order |
| Bounded work and storage | Required; service loops also need bounded turns and shutdown |
| No recursion | Default; any exception must establish and test a small depth bound |
| No allocation after initialization | Default for latency-sensitive steady-state paths; elsewhere document budgets, lifetime, and allocation failure |
| Assert contracts, including at both ends of a boundary | Assert meaningful independent properties; no per-function assertion quota |
| Explicitly sized integers | Required for domain, wire, and persistent quantities; `usize` for local indexing and allocator interfaces |
| 70-line functions, 100-column lines | Design limits for new code; extract coherent helpers without scattering the state machine |
| Snake case functions and files | Adopt for project code; preserve external API names |
| Zero dependencies | Standard library first; justify each additional dependency |

Existing project contracts take precedence. Record deliberate departures and their rationale
locally so reviewers can evaluate whether the same guarantees still hold.

## References and Version

The examples use Zig **0.16.0**. For another compiler pin, recheck API signatures and build behavior
against that release. [quality.md](quality.md) describes the version discipline.
Async/I/O guidance was checked against the official release and its bundled standard-library
source on **2026-09-11**; it does not assume development-branch APIs.

- [Tiger Style][tiger-style] — primary design influence; snapshot from the supplied TigerBeetle
  checkout at `c6b3e95c9c117b541c6cb0d37cd2366b1a2e94c9`.
- [Zig 0.16.0 language reference](https://ziglang.org/documentation/0.16.0/) — language semantics.
- [Zig 0.16.0 release notes](https://ziglang.org/download/0.16.0/release-notes.html) — API migration.

[tiger-style]: https://github.com/tigerbeetle/tigerbeetle/blob/c6b3e95c9c117b541c6cb0d37cd2366b1a2e94c9/docs/TIGER_STYLE.md
