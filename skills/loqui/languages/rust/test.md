---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Testing

Test observable contracts and meaningful failure modes. Use native Rust and Cargo facilities before adding helpers, and choose focused tests that can detect a realistic regression.

## Unit, Integration, and Documentation Tests

Keep unit tests near the implementation when private details or small algorithms need coverage:

```rust
fn doubled(value: u32) -> Option<u32> {
    value.checked_mul(2)
}

#[cfg(test)]
mod tests {
    use super::doubled;

    #[test]
    fn reports_overflow() {
        assert_eq!(doubled(u32::MAX), None);
        assert_eq!(doubled(3), Some(6));
    }
}

assert_eq!(doubled(u32::MAX), None);
```

Put public API integration tests in `tests/`. Each integration-test target is a separate crate, so it exercises downstream visibility. Share helpers through `tests/common/mod.rs` when useful, and avoid many tiny targets that needlessly increase linking time.

Use rustdoc examples to verify normal usage and important type constraints. Include imports and complete setup; keep intentional failures distinct from runnable examples:

```rust,compile_fail
fn move_then_read() {
    let text = String::from("hello");
    drop(text);
    println!("{text}");
}
```

A `compile_fail` test succeeds for any compiler error; inspect the diagnostic to ensure it fails for the intended reason. Use a UI-test tool such as `trybuild` when stable diagnostic snapshots or a larger set of compile-pass/fail cases are part of the API contract.

## Routine Validation

```bash
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace --all-targets
cargo test --workspace --doc
```

These commands do not rewrite source files. Cargo still writes build artifacts and may resolve dependencies; add `--locked` when a job must reject lockfile changes. Run the supported feature combinations and platforms for the project rather than blindly enabling incompatible features.

`--all-targets` selects unit, integration, example, benchmark, and binary targets as applicable; it excludes doctests. A normal `cargo test` includes doctests for eligible library targets, but the explicit pair above avoids ambiguity when target flags are added.

Nextest can improve scheduling, isolation, and reporting for larger suites. It does not run doctests as part of a normal run:

```bash
cargo nextest run --workspace
cargo test --workspace --doc
```

Use Cargo's built-in runner when it meets the project's needs. Cross-compiled doctests are supported on current Rust, but executing them still requires a runnable target or a configured runner. See [`cargo test`](https://doc.rust-lang.org/cargo/commands/cargo-test.html) and [nextest's doctest guidance](https://nexte.st/docs/running/#doctests).

## Fixtures and Repeatability

Use small deterministic fixtures for specific scenarios. Builders help when tests repeatedly construct a large object, but should not hide the field that makes the case significant. Give tests independent temporary directories, ports, and database state where needed.

Property-based tests are useful for invariants such as round trips, ordering, or equivalence between implementations. Use a framework that records failing inputs and supports shrinking; preserve regression cases. Reproducibility requires more than an arbitrary seed when the generator algorithm or dependency version can change.

Snapshot tests can make large structured outputs reviewable. Remove irrelevant timestamps, paths, and ordering noise, and inspect proposed changes with tools such as `cargo insta review`. Do not accept a snapshot update solely because the implementation changed.

`rstest` can reduce repetitive parameter and fixture code; ordinary helper functions and table-driven loops are often sufficient. Prefer explicit data over a complex fixture lifecycle when the tests are small.

## Assert the Contract

Use `assert_eq!` for values with useful debug output and `assert_matches!` for variants and guards. The latter is stable since 1.96 and needs an explicit import:

```rust
use core::assert_matches;

let parsed = "42".parse::<u32>();
assert_matches!(parsed, Ok(value) if value > 0);
assert_eq!(parsed.unwrap(), 42);
```

Avoid depending on unordered map iteration. Sort results when order is irrelevant, or compare through the collection's semantic equality. Test both success and meaningful boundary cases instead of merely calling every helper.

If thread-safety is a public contract, assert it at compile time:

```rust
use std::sync::Arc;

fn require_send_sync<T: Send + Sync>() {}
require_send_sync::<Arc<String>>();
```

Check async future bounds separately from receiver bounds. A `Send + Sync` service can still return a non-`Send` future; [traits](traits.md#async-methods-decide-the-future-contract) includes both positive and negative examples.

## Async Tests

Use the runtime's test support and keep spawned tasks accounted for. Tokio's paused clock is useful for deterministic timer tests; it requires `test-util` and a current-thread runtime:

```rust
use tokio::time::{sleep, Duration, Instant};

#[tokio::main(flavor = "current_thread")]
async fn main() {
    tokio::time::pause();
    let start = Instant::now();
    sleep(Duration::from_secs(30)).await;
    assert!(Instant::now() - start >= Duration::from_secs(30));
}
```

In a test target, use `#[tokio::test(start_paused = true)]` for this setup. Timer granularity can make a sleep complete slightly after its requested duration, so avoid exact elapsed-time equality. Paused time does not virtualize external I/O. Prefer explicit synchronization to real sleeps for task ordering, and reserve real deadlines for detecting hangs.

Test cancellation and recovery where they are part of the contract: closed channels, a dropped response receiver, partial I/O, and shutdown with active tasks. Do not assume a timeout undoes completed effects. [Tokio's channel error tests and types](../../resources/languages/rust/tokio/tokio/src/sync/mpsc/error.rs) and [select contract](../../resources/languages/rust/tokio/tokio/src/macros/select.rs) provide useful reading paths.

## Unsafe and Macro Tests

Exercise safe interfaces to unsafe code with valid boundary cases. Miri can detect many undefined behaviors on exercised executions; it cannot prove a whole abstraction sound, and not all platform or FFI code is supported. Never run deliberately invalid raw-pointer examples as ordinary tests. See [unsafe](unsafe.md).

For macros, test downstream use, renamed dependencies, helper visibility, input syntax, and generated trait bounds. Expansion output is a diagnostic aid; compiling and running the result provides stronger evidence than inspecting expansion text alone. See [macros](macros.md).

## Validation Scope

Run relevant tests for the change, then required project checks. Use supported feature and platform combinations, and test the MSRV when it is promised. Apply source fixes deliberately and review them before verification; `cargo fix` is not a test command.

Keep lint exceptions local. `unwrap` is often appropriate in tests because unexpected errors should fail the case. If a lint policy objects, choose a narrow, explained exception rather than turning every assertion into error plumbing.

## Related

- [Quality](quality.md): examples and lint policy
- [Modules](modules.md): workspace validation
- [Async I/O](async-io.md): task and cancellation contracts
- [Source catalog](resources.md): pinned real-world implementations
