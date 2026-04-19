---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Unsafe

Guidelines for writing and reviewing unsafe code.

## Core Principles

### Unsafe is a Boundary, Not a Mode

**Keep unsafe blocks minimal. Provide safe abstractions.**

```rust
// ✓ CORRECT: Safe wrapper that encapsulates raw pointer handling
use std::ptr::NonNull;
use std::marker::PhantomData;

pub struct RawSlice<T> {
    ptr: NonNull<T>,
    len: usize,
    _marker: PhantomData<T>,
}

impl<T> RawSlice<T> {
    /// Creates a slice view from a raw pointer.
    ///
    /// # Safety
    /// - `ptr` must be non-null and properly aligned for `T`
    /// - `ptr` must be valid for reads of `len * size_of::<T>()` bytes
    ///   for the lifetime of the returned `RawSlice`
    /// - `len * size_of::<T>()` must not exceed `isize::MAX`
    /// - The memory must not be mutated while this slice exists
    pub unsafe fn from_raw(ptr: *const T, len: usize) -> Self {
        Self {
            ptr: NonNull::new_unchecked(ptr as *mut T),
            len,
            _marker: PhantomData,
        }
    }

    // Safe API: internal unsafe is minimal and auditable
    pub fn as_slice(&self) -> &[T] {
        // SAFETY: Invariants established by from_raw()
        unsafe { std::slice::from_raw_parts(self.ptr.as_ptr(), self.len) }
    }
}

// ✘ WRONG: Large unsafe block
unsafe fn do_everything(ptr: *mut u8, len: usize) {
    // 100 lines of code, hard to audit
    // Which operations actually need unsafe?
}

// ✓ CORRECT: Isolate unsafe to the boundary
fn do_everything_safe(ptr: *mut u8, len: usize) {
    let slice = unsafe {
        // SAFETY: Caller ensures ptr is valid for len bytes
        std::slice::from_raw_parts_mut(ptr, len)
    };

    // Rest is safe Rust - no unsafe needed
    process_slice(slice);
}
```

**Don't reimplement safe APIs with unsafe:**

```rust
// ✘ WRONG: This is just slice.get() with extra risk
fn bad_get(slice: &[u8], i: usize) -> Option<u8> {
    if i < slice.len() {
        Some(unsafe { *slice.get_unchecked(i) })
    } else {
        None
    }
}

// ✓ CORRECT: Use the safe API
fn good_get(slice: &[u8], i: usize) -> Option<u8> {
    slice.get(i).copied()
}

// ✓ CORRECT: get_unchecked can win when bounds are proven once, used many times
fn sum_range(slice: &[u8], start: usize, end: usize) -> u8 {
    assert!(end <= slice.len() && start <= end);
    let mut sum = 0u8;
    for i in start..end {
        // SAFETY: assert above guarantees i < end <= len
        sum = sum.wrapping_add(unsafe { *slice.get_unchecked(i) });
    }
    sum
}
```

### Document Safety Invariants

**Every `unsafe` block needs a `// SAFETY:` comment.**

```rust
/// Creates a string from UTF-8 bytes without validation.
///
/// # Safety
///
/// The caller must ensure that `bytes` contains valid UTF-8.
/// Passing invalid UTF-8 is undefined behavior.
pub unsafe fn from_utf8_unchecked(bytes: Vec<u8>) -> String {
    // 2024 edition: unsafe_op_in_unsafe_fn warns by default.
    // Wrap the unsafe call in an inner unsafe block with its own SAFETY comment.
    // SAFETY: caller guarantees bytes are valid UTF-8 (propagated to the inner call).
    unsafe { String::from_utf8_unchecked(bytes) }
}

impl MyVec<T> {
    pub fn push(&mut self, value: T) {
        if self.len == self.capacity {
            self.grow();
        }
        // SAFETY: We just ensured len < capacity, so this write is in bounds.
        // The pointer is properly aligned because it came from a Vec allocation.
        unsafe {
            std::ptr::write(self.ptr.add(self.len), value);
        }
        self.len += 1;
    }
}
```

### Use `debug_assert!` for Invariants

**Check invariants in debug builds.**

```rust
pub unsafe fn get_unchecked(slice: &[u8], index: usize) -> u8 {
    debug_assert!(index < slice.len(), "index out of bounds");
    // SAFETY: caller guarantees index is in bounds
    unsafe { *slice.get_unchecked(index) }
}

impl<T> MyVec<T> {
    unsafe fn set_len(&mut self, new_len: usize) {
        debug_assert!(new_len <= self.capacity);
        debug_assert!(
            std::mem::size_of::<T>() == 0 || new_len <= isize::MAX as usize,
            "capacity overflow"
        );
        // This method assigns to a field — no unsafe op is actually performed.
        // The `unsafe fn` marker exists because the caller must uphold the invariant
        // that the first `new_len` elements are initialized. Document that in SAFETY:
        // on callers, not inside.
        self.len = new_len;
    }
}
```

### Contain Unsafe in Small Modules

**Isolate unsafe code for easier auditing.**

```rust
// src/raw.rs - All unsafe internals
//! Raw pointer operations. Do not use directly.
//!
//! This module contains the unsafe implementation details.
//! Use the safe wrappers in the parent module instead.

pub(super) unsafe fn raw_copy(src: *const u8, dst: *mut u8, len: usize) {
    // SAFETY: Caller ensures pointers are valid and non-overlapping
    std::ptr::copy_nonoverlapping(src, dst, len);
}

// src/lib.rs - Safe public API
mod raw;

pub fn copy_slice(src: &[u8], dst: &mut [u8]) {
    assert!(src.len() <= dst.len());
    // SAFETY: Slices guarantee valid, properly aligned pointers.
    // We checked that dst is large enough.
    unsafe {
        raw::raw_copy(src.as_ptr(), dst.as_mut_ptr(), src.len());
    }
}
```

### Don't trap into UB pitfalls

**Know and avoid all forms of UB.**

```rust
// Common UB pitfalls:

// 1. Null or dangling pointers
let ptr: *const i32 = std::ptr::null();
unsafe { *ptr }  // UB!

// 2. Unaligned access
let bytes: [u8; 4] = [1, 2, 3, 4];
let ptr = bytes.as_ptr() as *const u32;
unsafe { *ptr }  // UB if not aligned!

// 3. Data races
static mut COUNTER: u32 = 0;
// Accessing from multiple threads without synchronization is UB

// 4. Invalid values
let b: bool = unsafe { std::mem::transmute(2u8) };  // UB! bool must be 0 or 1

// 5. Breaking aliasing rules
let mut x = 42;
let r1 = &x as *const i32;
let r2 = &mut x as *mut i32;
unsafe {
    *r2 = 10;
    println!("{}", *r1);  // UB! r1 was invalidated by r2
}
```

### Prefer Safe Alternatives

**Use safe abstractions when available.**

```rust
// ✓ CORRECT: Use MaybeUninit for uninitialized memory (stable API)
use std::mem::MaybeUninit;

let mut array: [MaybeUninit<i32>; 10] = [const { MaybeUninit::uninit() }; 10];
for (i, elem) in array.iter_mut().enumerate() {
    elem.write(i as i32);
}
// SAFETY: all 10 elements written above
let array: [i32; 10] = array.map(|e| unsafe { e.assume_init() });

// ✘ WRONG: Uninitialized memory via transmute
let array: [i32; 10] = unsafe { std::mem::uninitialized() };  // UB!

// ✓ CORRECT: Use Cell/RefCell for interior mutability
use std::cell::RefCell;
let data = RefCell::new(vec![1, 2, 3]);
data.borrow_mut().push(4);

// ✘ WRONG: Raw pointer casting for mutability
let data = vec![1, 2, 3];
let ptr = &data as *const _ as *mut Vec<i32>;
unsafe { (*ptr).push(4); }  // UB!
```

### 2024 Edition Changes

The 2024 edition tightens unsafe semantics in three places. `cargo fix --edition` handles most of the mechanical rewrite; the SAFETY comments are on you.

**1. Extern blocks must be marked `unsafe`.** The author of the block is asserting the signatures match foreign definitions — a classic UB trap that 2021 left implicit.

```rust
// ✘ Rust 2021
extern "C" {
    fn puts(s: *const c_char) -> c_int;
}

// ✓ Rust 2024
unsafe extern "C" {
    fn puts(s: *const c_char) -> c_int;
}
```

**2. Unsafe attributes require the `unsafe(…)` wrapper.**

```rust
// ✓ Rust 2024
#[unsafe(no_mangle)]
pub extern "C" fn my_export() {}

#[unsafe(export_name = "custom_name")]
pub extern "C" fn renamed() {}

#[unsafe(link_name = "libfoo_bar")]
unsafe extern "C" {
    fn bar();
}
```

**3. `unsafe_op_in_unsafe_fn` is warn-by-default.** Unsafe operations inside an `unsafe fn` must be wrapped in an explicit inner `unsafe {}` block, with its own `// SAFETY:` comment.

```rust
// ✘ Invisible unsafe surface area
unsafe fn dangerous(p: *const u8) -> u8 {
    *p
}

// ✓ Explicit inner block — exactly where the unsafe op happens
unsafe fn dangerous(p: *const u8) -> u8 {
    // SAFETY: caller guarantees p is valid and properly aligned
    unsafe { *p }
}
```

**Why this matters:** inside a pre-2024 `unsafe fn`, every line was implicitly unsafe. You could dereference a raw pointer on line 37 of a 200-line function and nothing signaled "here be dragons." The 2024 change forces the unsafe surface to be visible — and auditable — even inside functions whose signature is already unsafe.

See [edition.md](edition.md) for the full 2024 migration.

### Unsafe Traits

**Document safety requirements for implementors.**

```rust
/// A type that can be safely zeroed.
///
/// # Safety
///
/// Implementing this trait guarantees that a value of all zero bytes
/// is a valid instance of the type. This is true for primitive integers,
/// but NOT for types like `bool`, `char`, references, or enums.
pub unsafe trait Zeroable {
    fn zeroed() -> Self;
}

// Safe to implement for integers
unsafe impl Zeroable for u32 {
    fn zeroed() -> Self { 0 }
}

// NOT safe: bool must be 0 or 1, not arbitrary bytes
// unsafe impl Zeroable for bool { ... }  // WRONG!
```

## Audit Checklist

When reviewing unsafe code:

1. **Is the unsafe actually necessary?** Can it be done safely?
2. **Is the unsafe block minimal?** Only the required operations?
3. **Is the edition 2024 or later?** `unsafe extern` / `#[unsafe(no_mangle)]` / inner-block style should all be in effect.
4. **Is there an explicit inner `unsafe {}` inside every `unsafe fn`** that actually performs unsafe operations?
5. **Are all safety invariants documented?** `// SAFETY:` comments on every unsafe block?
6. **Are preconditions checked?** `debug_assert!` for invariants?
7. **Is the safe wrapper sound?** Can safe code cause UB?
8. **Are edge cases handled?** Zero-size types, overflow, alignment?

## Summary

- **NEVER** use large unsafe blocks (minimize scope)
- **NEVER** use unsafe without documenting safety invariants
- **DO** know the UB pitfalls: null/dangling pointers, unaligned access, data races, invalid values, aliasing violations
- **DO** provide safe abstractions over unsafe internals
- **DO** add `// SAFETY:` comments to every unsafe block
- **DO** wrap unsafe ops inside `unsafe fn` bodies in explicit inner `unsafe {}` blocks (2024 edition warns by default)
- **DO** mark all `extern` blocks as `unsafe extern`
- **DO** use `#[unsafe(no_mangle)]` / `#[unsafe(link_name)]` / `#[unsafe(export_name)]`
- **DO** use `debug_assert!` to check invariants
- **DO** contain unsafe in small, auditable modules
- **DO** prefer safe alternatives (`MaybeUninit`, `Cell`, etc.)
- **DO** prefer safe `#[target_feature]` (1.86+) over `unsafe fn` for CPU-feature dispatch

---

## Related

- [edition.md](edition.md) - 2024 edition unsafe changes in detail
- [modernization.md](modernization.md) - Safe `#[target_feature]` (1.86+)
- [ownership.md](ownership.md) - Safe ownership patterns
- [modules.md](modules.md) - Containing unsafe in modules
- [errors.md](errors.md) - Documenting `# Safety` sections

## References

- [The Rustonomicon](https://doc.rust-lang.org/nomicon/)
- [Rust Reference: Undefined Behavior](https://doc.rust-lang.org/reference/behavior-considered-undefined.html)
- [Unsafe Code Guidelines](https://rust-lang.github.io/unsafe-code-guidelines/)
- [RFC 2585 — Unsafe block in unsafe fn](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html)
- [Unsafe attributes (2024 edition)](https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-attributes.html)
- [`unsafe extern` blocks (2024 edition)](https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-extern.html)
