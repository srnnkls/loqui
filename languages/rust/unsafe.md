---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Unsafe

A safe API must uphold its safety invariants for every input that safe Rust can supply. Keep unsafe operations small, document the proof, and prefer an existing safe abstraction when it meets the requirement.

## Establish a Sound Boundary

A comment saying “the caller ensures the pointer is valid” cannot make a safe function accepting arbitrary raw pointers sound. Accept a slice when that expresses the operation:

```rust
fn clear(bytes: &mut [u8]) {
    bytes.fill(0);
}

let mut bytes = [1, 2, 3];
clear(&mut bytes);
assert_eq!(bytes, [0, 0, 0]);
```

If interoperability requires raw inputs, expose the caller obligations through an `unsafe fn` and a complete contract:

```rust
#![deny(unsafe_op_in_unsafe_fn)]

/// Clears a caller-owned buffer.
///
/// # Safety
///
/// `ptr` must be non-null and aligned, even when `len` is zero. It must
/// identify `len` initialized bytes within one allocation, valid for reads
/// and writes for this call. No other pointer may access those bytes during
/// the call. `len` must not exceed `isize::MAX`, and the addressed range
/// must not wrap around the address space.
pub unsafe fn clear_raw(ptr: *mut u8, len: usize) {
    // SAFETY: The caller establishes the validity, size, and exclusive-access
    // requirements of from_raw_parts_mut for the duration of this call.
    let bytes = unsafe { std::slice::from_raw_parts_mut(ptr, len) };
    bytes.fill(0);
}

let mut bytes = [1, 2, 3];
// SAFETY: This array provides initialized, exclusive storage for three bytes.
unsafe { clear_raw(bytes.as_mut_ptr(), bytes.len()) };
assert_eq!(bytes, [0, 0, 0]);
```

For generic `T`, initialization and alignment concern `T`, and the total byte size is `len * size_of::<T>()`. Non-null and alignment requirements also apply to zero-sized types. An address-range check alone cannot establish allocation validity or exclusivity. Use the exact contract of [`from_raw_parts_mut`](https://doc.rust-lang.org/std/slice/fn.from_raw_parts_mut.html).

## Tie Views to Their Storage

Prefer a normal slice for a borrowed view. When an internal representation needs a raw pointer, encode its relationship to the source rather than manufacturing an unconstrained lifetime:

```rust
use std::marker::PhantomData;

struct SliceView<'a, T> {
    ptr: *const T,
    len: usize,
    source: PhantomData<&'a [T]>,
}

impl<'a, T> SliceView<'a, T> {
    fn new(slice: &'a [T]) -> Self {
        Self { ptr: slice.as_ptr(), len: slice.len(), source: PhantomData }
    }

    fn as_slice(&self) -> &[T] {
        // SAFETY: new obtains this range from a valid slice. The private
        // fields preserve that range, and 'a keeps its shared borrow valid.
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }
}

let storage = [10, 20];
let view = SliceView::new(&storage);
assert_eq!(view.as_slice(), &storage);
```

`PhantomData` records a type relationship; it does not validate arbitrary raw inputs. All constructors, mutation paths, and unsafe implementations must preserve the representation's invariant. Review auto traits and variance if the abstraction grows; do not add `Send` or `Sync` implementations merely to silence an error.

## Explain Every Unsafe Operation

An unsafe function declares obligations for callers; an unsafe block discharges obligations for operations inside it. Edition 2024 enables `unsafe_op_in_unsafe_fn` as a warning by default. Use explicit blocks and consider denying the lint in the project:

```rust
#![deny(unsafe_op_in_unsafe_fn)]

/// Reads one byte without bounds checking.
///
/// # Safety
/// `index` must be less than `bytes.len()`.
pub unsafe fn read_unchecked(bytes: &[u8], index: usize) -> u8 {
    debug_assert!(index < bytes.len());
    // SAFETY: The caller guarantees the index is in bounds in all builds.
    unsafe { *bytes.get_unchecked(index) }
}
```

The debug assertion helps detect a broken contract; it does not establish a safe API's precondition in release builds. A safe wrapper must check its inputs with an unconditional check or derive their validity from an existing invariant. Safety comments should explain the allocation, initialization, lifetime, aliasing, or synchronization facts the operation relies on.

## Use Safe Operations First

Safe code can often express the same work without an unsafe proof:

```rust
fn get(bytes: &[u8], index: usize) -> Option<u8> {
    bytes.get(index).copied()
}

fn sum_range(bytes: &[u8], start: usize, end: usize) -> u8 {
    bytes[start..end].iter().fold(0, |sum, byte| sum.wrapping_add(*byte))
}

fn copy_prefix(source: &[u8], destination: &mut [u8]) {
    destination[..source.len()].copy_from_slice(source);
}
```

These functions have safe failure behavior for out-of-range access. Introduce unchecked indexing only with evidence that it improves the relevant workload and a proof that covers every index. Keep synchronization, aliasing, and pointer arithmetic inside a small module whose safe interface preserves the invariant.

## Initialization and Valid Representations

Uninitialized storage is not an initialized value. `MaybeUninit<T>` supports staged initialization; `assume_init` requires a valid `T` on every path that reaches it:

```rust
use std::mem::MaybeUninit;

let mut slots: [MaybeUninit<u32>; 4] = [const { MaybeUninit::uninit() }; 4];
for (index, slot) in slots.iter_mut().enumerate() {
    slot.write(index as u32);
}
// SAFETY: Every element was initialized by the completed loop above.
let values = slots.map(|slot| unsafe { slot.assume_init() });
assert_eq!(values, [0, 1, 2, 3]);
```

For types with destructors, account for initialized elements if construction fails or unwinds; `MaybeUninit` does not drop their contents automatically. Prefer `std::array::from_fn` or a `Vec` when those safe APIs suffice.

Distinguish an all-zero representation from allowing every bit pattern:

| Type                     | Is the all-zero representation valid?     | Are all bit patterns valid?    |
| ------------------------ | ----------------------------------------- | ------------------------------ |
| Primitive integers       | Yes                                       | Yes                            |
| `bool`                   | Yes: `false`                              | No: only 0 and 1               |
| `char`                   | Yes: `'\0'`                               | No: only Unicode scalar values |
| References, `NonZeroU32` | No                                        | No                             |
| Enums                    | Depends on the type's validity and layout | Depends on the type            |

An unsafe trait promising zero-initializability must document precisely that guarantee; it must not conflate it with arbitrary-byte validity. Prefer an established abstraction with a suitable contract to inventing one for a single initialization site. See [`mem::zeroed`](https://doc.rust-lang.org/std/mem/fn.zeroed.html) and the [Reference's invalid-value rules](https://doc.rust-lang.org/reference/behavior-considered-undefined.html).

## Foreign Interfaces and Unsafe Attributes

Edition 2024 requires `unsafe extern` blocks. The author must verify the ABI and declarations against the foreign definitions. `link_name` is an ordinary attribute on a foreign item:

```rust,no_run
use std::ffi::{c_char, c_int};

unsafe extern "C" {
    #[link_name = "puts"]
    fn c_puts(text: *const c_char) -> c_int;
}

// SAFETY: c"hello" supplies a live, NUL-terminated C string. This declaration
// assumes the target provides the C puts function with the signature above.
unsafe { c_puts(c"hello".as_ptr()) };
```

The attributes requiring `#[unsafe(...)]` are `no_mangle`, `export_name`, and `link_section`. Their obligations concern the linker and target environment, not just Rust types. For example, an exported name must not collide with another symbol:

```rust,no_run
// SAFETY: The embedding application's symbol namespace reserves this name
// for this function, whose signature matches its documented C interface.
#[unsafe(export_name = "example_rust_api_version")]
pub extern "C" fn api_version() -> u32 {
    1
}
```

Changing the syntax does not verify the ABI, symbol uniqueness, or section placement. See [unsafe attributes](https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-attributes.html) and [extern blocks](https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-extern.html).

A newtype is not automatically FFI-compatible with its inner type; use a suitable `repr(transparent)` or `repr(C)` contract. CPU-feature-specific functions also retain target-feature calling requirements: a safe declaration with `#[target_feature]` is not blanket permission to call it on unsupported hardware. See the [Reference on target features](https://doc.rust-lang.org/reference/attributes/codegen.html#the-target_feature-attribute).

## Review and Validation

Check valid ranges, alignment, initialized values, live allocations, aliasing, synchronization, and panic paths. Exercise empty buffers, zero-sized types, and boundary arithmetic using valid inputs. Do not execute examples known to cause undefined behavior as ordinary tests.

Run relevant tests with Miri when supported, and use sanitizers or FFI integration tests for the boundaries they cover. A passing run checks exercised executions; it is not a proof of soundness. The [Rustonomicon](https://doc.rust-lang.org/nomicon/) provides the broader model.

## Related

- [Ownership](ownership.md): borrowed views and valid replacement states
- [Edition 2024](edition.md): migration steps
- [Testing](test.md): native validation and doctests
- [Source examples](resources.md): redb's guarded storage APIs
