---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Unsafe

Guidelines for writing and reviewing unsafe code.

## Core Principles

### Unsafe is a Boundary, Not a Mode

**Keep unsafe blocks minimal. Provide safe abstractions.**

```rust
// ✓ CORRECT: Minimal unsafe, safe wrapper
pub fn get_unchecked(slice: &[u8], index: usize) -> u8 {
    // SAFETY: Caller guarantees index < slice.len()
    // We document this requirement and trust the caller
    unsafe { *slice.get_unchecked(index) }
}

// ✘ WRONG: Large unsafe block
unsafe fn do_everything(ptr: *mut u8, len: usize) {
    // 100 lines of code, hard to audit
    // Which operations actually need unsafe?
}

// ✓ CORRECT: Isolate unsafe operations
fn do_everything_safe(ptr: *mut u8, len: usize) {
    let slice = unsafe {
        // SAFETY: ptr is valid for len bytes (documented precondition)
        std::slice::from_raw_parts_mut(ptr, len)
    };

    // Rest is safe Rust
    process_slice(slice);
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
    // SAFETY: Caller guarantees bytes are valid UTF-8
    String::from_utf8_unchecked(bytes)
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
    // SAFETY: Caller guarantees index is in bounds
    *slice.get_unchecked(index)
}

impl<T> MyVec<T> {
    unsafe fn set_len(&mut self, new_len: usize) {
        debug_assert!(new_len <= self.capacity);
        debug_assert!(
            std::mem::size_of::<T>() == 0 || new_len <= isize::MAX as usize,
            "capacity overflow"
        );
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
// ✓ CORRECT: Use MaybeUninit for uninitialized memory
use std::mem::MaybeUninit;

let mut array: [MaybeUninit<i32>; 10] = MaybeUninit::uninit_array();
for (i, elem) in array.iter_mut().enumerate() {
    elem.write(i as i32);
}
// SAFETY: All elements have been initialized
let array = unsafe { MaybeUninit::array_assume_init(array) };

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
3. **Are all safety invariants documented?** `// SAFETY:` comments?
4. **Are preconditions checked?** `debug_assert!` for invariants?
5. **Is the safe wrapper sound?** Can safe code cause UB?
6. **Are edge cases handled?** Zero-size types, overflow, alignment?

## Summary

- **NEVER** use large unsafe blocks (minimize scope)
- **NEVER** use unsafe without documenting safety invariants
- **DO** know the UB pitfalls: null/dangling pointers, unaligned access, data races, invalid values, aliasing violations
- **DO** provide safe abstractions over unsafe internals
- **DO** add `// SAFETY:` comments to every unsafe block
- **DO** use `debug_assert!` to check invariants
- **DO** contain unsafe in small, auditable modules
- **DO** prefer safe alternatives (`MaybeUninit`, `Cell`, etc.)

---

## Related

- [ownership.md](ownership.md) - Safe ownership patterns
- [modules.md](modules.md) - Containing unsafe in modules
- [errors.md](errors.md) - Documenting `# Safety` sections

## References

- [The Rustonomicon](https://doc.rust-lang.org/nomicon/)
- [Rust Reference: Undefined Behavior](https://doc.rust-lang.org/reference/behavior-considered-undefined.html)
- [Unsafe Code Guidelines](https://rust-lang.github.io/unsafe-code-guidelines/)
