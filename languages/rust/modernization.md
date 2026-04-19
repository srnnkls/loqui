---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Modernization

Modern Rust features (1.80 → 1.95), `cargo fix --edition`, and how to keep AI-generated code current.

---

## AI Drift Warning

**AI agents — this one included — systematically generate pre-2024-edition Rust.** Two forces drive this:

1. **Training cutoff.** A model's weights freeze at some date; anything stabilized after that date is literally unknown.
2. **Frequency bias.** Years of pre-generics, pre-edition-2024 Rust outweigh the relatively recent let chains, async closures, `LazyLock`, native async in traits, `use<>` capture syntax. The model defaults to what it has seen most often.

Practical symptoms in AI output:

- `lazy_static!` / `once_cell::sync::Lazy` instead of `std::sync::LazyLock`
- `#[async_trait]` where native `async fn` in traits suffices
- Pyramids of nested `if let` instead of let chains
- `extern "C" { … }` without the required 2024-edition `unsafe` prefix
- `unsafe fn` bodies without the inner `unsafe {}` block (warn-by-default in 2024)
- Manual `Captures<'a>` trick in return-position `impl Trait`
- `cfg_if!` from the `cfg-if` crate instead of the stdlib `cfg_select!` macro

**Mandatory habit for every code-gen session:**

```bash
# From a clean git state:
cargo fix --edition        # migrate to current edition if not already
cargo clippy --fix         # apply machine-applicable clippy suggestions
cargo test                 # confirm nothing broke
git diff                   # review — these fixers are behavior-preserving
git commit
```

Run this **after every significant generation**, not just edition transitions. The diff is usually surgical.

---

## `cargo fix` and Clippy Modernizers

Rust's modernization story is split across two tools:

- **`cargo fix --edition`** — authoritative migration between editions. Handles RPIT capture, `unsafe extern`, `unsafe_op_in_unsafe_fn`, match-ergonomics, prelude additions.
- **`cargo clippy --fix`** — applies machine-applicable clippy suggestions (many modernizers live here): `needless_return`, `redundant_clone`, `manual_let_else`, `or_fun_call`, `option_map_or_none`, plus hundreds more.

```bash
# Preview-only (prints diffs):
cargo fix --edition --allow-dirty 2>&1 | head -50
cargo clippy --fix --allow-dirty --allow-staged

# In a clean tree, drop --allow-dirty / --allow-staged and review normally.
```

**Compose them:** `cargo fix --edition` first (structural), then `cargo clippy --fix` (idiomatic).

---

## Stdlib-First Replacements

The 1.80–1.95 window moved several community crates into stdlib. Before adding a dependency, check whether stdlib now covers it.

| Old pattern / crate | Modern replacement | Since |
|---|---|---|
| `lazy_static::lazy_static!` | `std::sync::LazyLock::new(…)` | 1.80 |
| `once_cell::sync::Lazy` | `std::sync::LazyLock` | 1.80 |
| `once_cell::sync::OnceCell` | `std::sync::OnceLock` | 1.70 |
| `once_cell::unsync::Lazy` | `std::cell::LazyCell` | 1.80 |
| `cfg-if::cfg_if!` | `cfg_select!` macro | 1.95 |
| `fs2::FileExt::try_lock_exclusive` | `std::fs::File::lock` | 1.89 |
| Ad-hoc OS pipe wrappers | `std::io::pipe` | 1.87 |
| `async_trait::async_trait` on a trait (not `dyn`) | native `async fn` in traits | 1.75 |
| `Captures<'a>` RPIT workaround | `+ use<'a>` precise capture | 2024 edition |
| `#[deny(unsafe_op_in_unsafe_fn)]` opt-in | warn-by-default in 2024 | 2024 edition |
| Pyramid of `if let` … `if let` | Let chains | 1.88 (2024 edition) |
| Manual CPU-feature dispatch via `unsafe` | Safe `#[target_feature]` | 1.86 |
| `ptr::read(&x)` / transmute gymnastics | `Vec::pop_if` / `Vec::extract_if` | 1.86 / 1.87 |
| `itertools::Itertools::tuple_windows::<[_; N]>` | `slice::array_windows::<N>()` | 1.94 |
| `#[allow(lint)]` that might go stale | `#[expect(lint)]` (warns when lint stops firing) | 1.81 |
| `rand` for crypto | Always use `rand` only for non-crypto; use `rand_chacha` / `ring` / `rustls::crypto` for crypto | — |

---

## Language Feature Tour

### Rust 1.80 (July 2024)

```rust
// LazyLock — stdlib replaces lazy_static!
use std::sync::LazyLock;

static CONFIG: LazyLock<Config> = LazyLock::new(|| Config::load().unwrap());

// LazyCell — single-threaded equivalent (for thread_local! { … })
use std::cell::LazyCell;
thread_local! {
    static CACHE: LazyCell<HashMap<String, u32>> = LazyCell::new(HashMap::new);
}
```

### Rust 1.81 (September 2024)

```rust
// #[expect(lint)] — warns when the lint STOPS firing
// (so stale allows don't rot silently)
#[expect(clippy::cast_possible_truncation, reason = "value is clamped to u32 above")]
let n = clamped_value as u32;
```

### Rust 1.82 (October 2024)

```bash
# cargo info — inspect a crate from the terminal
cargo info serde
# version, description, license, features, download count
```

### Rust 1.84 (January 2025)

**MSRV-aware dependency resolver.** If your `Cargo.toml` declares `rust-version`, Cargo 1.84+ prefers dependency versions whose own MSRV is compatible — no more random breakage from a transitive dep that bumped its MSRV.

```toml
[package]
rust-version = "1.85"
```

### Rust 1.85 (February 2025) — **Rust 2024 Edition stable**

This is the largest edition ever shipped. See [edition.md](edition.md) for the full migration guide.

```rust
// Async closures — capture across await points
async fn retry<F, T>(f: F) -> T
where
    F: AsyncFn() -> T,
{
    loop {
        if let Ok(v) = f().await { return v; }
    }
}

// Call with async closure:
retry(async || fetch().await).await;

// #[diagnostic::do_not_recommend] — hide misleading trait-impl suggestions
#[diagnostic::do_not_recommend]
impl<T: PrivateTrait> MyTrait for T { … }
```

### Rust 1.86 (April 2025)

```rust
// Trait object upcasting — at last
trait Animal { fn speak(&self); }
trait Dog: Animal { fn fetch(&self); }

fn make_sound(a: &dyn Animal) { a.speak(); }

let d: &dyn Dog = &Labrador;
make_sound(d);   // dyn Dog coerces to dyn Animal

// Safe #[target_feature]
#[target_feature(enable = "avx2")]
fn fast_path(data: &[f32]) -> f32 { … }   // now safe — caller in an AVX2 context

// Vec::pop_if
let top = v.pop_if(|x| *x > threshold);
```

### Rust 1.87 (May 2025)

```rust
// std::io::pipe — stdlib replaces ad-hoc pipe crates
let (mut reader, mut writer) = std::io::pipe()?;

// Vec::extract_if / HashMap::extract_if — drain-by-predicate, returning an iterator
let evens: Vec<i32> = v.extract_if(.., |x| *x % 2 == 0).collect();
```

### Rust 1.88 (June 2025)

```rust
// Let chains — 2024 edition only
if let Some(channel) = release_info()
    && let Channel::Stable(v) = channel
    && v.major == 1
    && v.minor >= 88
{
    println!("let chains!");
}
```

Cargo also gained automatic cache GC in 1.88: no more disk-filling `~/.cargo`.

### Rust 1.89 (August 2025)

```rust
// Const generic _ inference
fn identity<const N: usize>(arr: [i32; N]) -> [i32; N] { arr }
let r = identity::<_>([1, 2, 3]);   // compiler infers N

// File::lock — cross-platform advisory file locking in stdlib
let f = File::open("config.toml")?;
f.lock()?;
// … work ...
f.unlock()?;

// Result::flatten
let nested: Result<Result<i32, &str>, &str> = Ok(Ok(42));
assert_eq!(nested.flatten(), Ok(42));
```

Cross-compiled doctests also landed in 1.89 — doctests now run under the `--target` you configured.

### Rust 1.90 (September 2025)

**LLD default linker on `x86_64-unknown-linux-gnu`.** No configuration needed. ~40% faster incremental builds, ~20% faster from-scratch on typical Linux dev boxes.

```toml
# Opt out in .cargo/config.toml if you hit edge cases:
[target.x86_64-unknown-linux-gnu]
rustflags = ["-C", "linker-features=-lld"]
```

### Rust 1.91–1.94

- **1.91** — Windows ARM64 (`aarch64-pc-windows-msvc`) promoted to Tier 1.
- **1.93** — Stable C-style variadic declarations (`fn vprintf(fmt: *const c_char, args: ...) -> c_int`).
- **1.94** — `slice::array_windows::<N>()` — overlapping const-size windows returning `[T; N]` not `&[T]`.

```rust
let data = [1u8, 2, 3, 4, 5];
for w in data.array_windows::<3>() {
    assert!(w.len() == 3);   // w is [u8; 3] by type
}
```

### Rust 1.95 (April 2026) — Current

```rust
// cfg_select! — stdlib replacement for the cfg-if crate
cfg_select! {
    unix    => { fn platform_fn() { /* unix */ } }
    windows => { fn platform_fn() { /* windows */ } }
    _       => { fn platform_fn() { /* fallback */ } }
}

// if let guards in match arms
match value {
    Some(x) if let Ok(y) = compute(x) => {
        // both x and y are bound here
    }
    _ => {}
}
```

---

## Upgrade Checklist

When bumping toolchain or migrating to the 2024 edition:

```bash
# 1. Clean working tree so the diff is reviewable
git status

# 2. Update toolchain
rustup update stable
rustc --version   # expect 1.95+ in April 2026

# 3. Bump MSRV (if you ship a library)
# Cargo.toml:
#   rust-version = "1.85"   # or later
#   edition = "2024"

# 4. Automated edition migration
cargo fix --edition            # structural
cargo clippy --fix             # idiomatic

# 5. Verify
cargo test --all-targets
cargo clippy --all-targets -- -D warnings

# 6. Review and commit
git diff
git commit -m "chore: modernize to Rust 1.95 / 2024 edition"
```

Repeat after every toolchain bump and after any significant AI-generated change.

---

## Summary

- **DO** run `cargo fix --edition` and `cargo clippy --fix` after every code-gen session
- **DO** target the 2024 edition (stable since 1.85) — it unlocks let chains, async closures, `use<>` capture
- **DO** prefer stdlib over community crates where they now overlap (`LazyLock`, `OnceLock`, `File::lock`, `std::io::pipe`, `cfg_select!`)
- **DO** use native `async fn` in traits — reach for `#[async_trait]` only when you need `dyn`
- **DO** use `#[expect(lint)]` instead of `#[allow(lint)]` so stale allows warn
- **DO** declare `rust-version` to get MSRV-aware dependency resolution
- **DO** leave LLD as the default linker on Linux (1.90+) — big build-speed win
- **DON'T** reach for `lazy_static!` / `once_cell::sync::Lazy` — stdlib has `LazyLock`
- **DON'T** keep the `Captures<'a>` RPIT workaround — 2024 edition auto-captures
- **DON'T** use pyramids of nested `if let` — let chains exist
- **DON'T** trust AI-generated Rust blindly — frequency bias pulls it toward pre-2024 idioms

---

## Related Files

- [edition.md](edition.md) - Rust 2024 edition migration in depth
- [traits.md](traits.md) - Trait object upcasting, native async in traits, GATs
- [async-io.md](async-io.md) - Async closures, Axum 0.8, actor pattern
- [types.md](types.md) - `LazyLock`, `OnceLock`, `Vec::extract_if`, `array_windows`
- [unsafe.md](unsafe.md) - 2024 edition unsafe changes
- [quality.md](quality.md) - Let chains, `#[expect(lint)]`, workspace lints

## References

- [Rust 2024 Edition Guide](https://doc.rust-lang.org/edition-guide/rust-2024/) - Authoritative migration reference
- [Cargo `fix --edition` docs](https://doc.rust-lang.org/cargo/commands/cargo-fix.html)
- [Rust release blog](https://blog.rust-lang.org/) - Per-version release announcements
- [releases.rs](https://releases.rs/) - Searchable API stabilization timeline
- [Rust 1.85 release notes](https://blog.rust-lang.org/2025/02/20/Rust-1.85.0.html) - 2024 edition + async closures
- [Rust 1.86 release notes](https://blog.rust-lang.org/2025/04/03/Rust-1.86.0.html) - Trait upcasting, safe `#[target_feature]`
- [Rust 1.88 release notes](https://blog.rust-lang.org/2025/06/26/Rust-1.88.0.html) - Let chains, naked functions
- [Rust 1.90 release notes](https://blog.rust-lang.org/2025/09/18/Rust-1.90.0.html) - LLD default on Linux
- [Rust 1.95 release notes](https://blog.rust-lang.org/2026/04/16/Rust-1.95.0.html) - `cfg_select!`, `if let` guards
