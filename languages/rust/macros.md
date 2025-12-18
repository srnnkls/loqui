---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Macros

Guidelines for declarative and procedural macros.

## Core Guidelines

### Prefer Functions Over Macros

**Use macros only when functions can't do the job.**

```rust
// ✓ CORRECT: Function when possible
pub fn max<T: Ord>(a: T, b: T) -> T {
    if a > b { a } else { b }
}

// ✓ CORRECT: Macro when you need:
// - Variable arguments
// - Code generation
// - Compile-time string manipulation
// - Accessing caller's scope

macro_rules! vec_of_strings {
    ($($x:expr),* $(,)?) => {
        vec![$($x.to_string()),*]
    };
}

// ✘ WRONG: Macro for simple operations
macro_rules! add {
    ($a:expr, $b:expr) => { $a + $b };  // Just use a function
}
```

Valid reasons for macros:
- Variadic arguments (`println!`, `vec!`)
- DSLs and code generation
- Compile-time computation
- Conditional compilation beyond `#[cfg]`

### Input Syntax Mirrors Output

**Macro syntax should look like the code it generates.**

```rust
// ✓ CORRECT: struct keyword signals struct generation
bitflags! {
    struct Permissions: u32 {
        const READ = 0b001;
        const WRITE = 0b010;
    }
}

// ✘ WRONG: Ad-hoc syntax
bitflags! {
    flags Permissions: u32 {
        READ = 0b001,
        WRITE = 0b010,
    }
}

// ✓ CORRECT: Semicolons like regular constants
const_group! {
    const A: u32 = 1;
    const B: u32 = 2;
}

// ✘ WRONG: Commas (constants use semicolons)
const_group! {
    const A: u32 = 1,
    const B: u32 = 2,
}
```

### Use `$crate` for Hygiene

**Reference crate items with `$crate` to avoid name conflicts.**

```rust
// ✓ CORRECT: $crate ensures correct resolution
#[macro_export]
macro_rules! my_vec {
    ($($x:expr),* $(,)?) => {
        {
            let mut v = $crate::__private::Vec::new();
            $(v.push($x);)*
            v
        }
    };
}

// Re-export Vec for macro hygiene
#[doc(hidden)]
pub mod __private {
    pub use std::vec::Vec;
}

// ✘ WRONG: Assumes Vec is in scope
macro_rules! bad_vec {
    ($($x:expr),* $(,)?) => {
        {
            let mut v = Vec::new();  // Breaks if user shadows Vec
            $(v.push($x);)*
            v
        }
    };
}
```

### Support Attributes

**Allow attributes on generated items.**

```rust
// ✓ CORRECT: Supports #[derive], #[cfg], etc.
macro_rules! make_struct {
    (
        $(#[$attr:meta])*
        $vis:vis struct $name:ident {
            $(
                $(#[$field_attr:meta])*
                $field_vis:vis $field:ident : $ty:ty
            ),* $(,)?
        }
    ) => {
        $(#[$attr])*
        $vis struct $name {
            $(
                $(#[$field_attr])*
                $field_vis $field: $ty,
            )*
        }
    };
}

// Usage with attributes
make_struct! {
    #[derive(Debug, Clone)]
    pub struct Config {
        #[serde(default)]
        pub name: String,
        pub value: i32,
    }
}
```

### Support Visibility Specifiers

**Follow Rust's visibility syntax.**

```rust
// ✓ CORRECT: Visibility is configurable
macro_rules! make_wrapper {
    ($vis:vis $name:ident($inner:ty)) => {
        $vis struct $name($inner);
    };
}

make_wrapper!(pub UserId(u64));      // Public
make_wrapper!(pub(crate) Internal(u64));  // Crate-visible
make_wrapper!(Private(u64));         // Private (default)
```

### Work in All Item Positions

**Test macros in module scope and function scope.**

```rust
// ✓ CORRECT: Works everywhere
macro_rules! define_id {
    ($name:ident) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        pub struct $name(u64);
    };
}

// Module scope
define_id!(UserId);

fn example() {
    // Function scope
    define_id!(LocalId);
    let id = LocalId(42);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_in_function() {
        define_id!(TestId);  // Should work here too
    }
}
```

### Provide Good Error Messages

**Use `compile_error!` for clear diagnostics.**

```rust
macro_rules! require_string {
    (String) => { /* ok */ };
    ($other:ty) => {
        compile_error!(concat!(
            "expected `String`, found `",
            stringify!($other),
            "`"
        ));
    };
}

// For complex validation
macro_rules! validated_struct {
    (struct $name:ident { }) => {
        compile_error!("struct must have at least one field");
    };
    (struct $name:ident { $($fields:tt)+ }) => {
        struct $name { $($fields)+ }
    };
}
```

### Procedural Macros: Minimize Dependencies

**Keep proc-macro crates lean.**

```toml
# proc-macro crate Cargo.toml
[lib]
proc-macro = true

[dependencies]
# Minimal dependencies
syn = { version = "2", features = ["derive"] }  # Only needed features
quote = "1"
proc-macro2 = "1"

# Avoid pulling in the whole ecosystem
```

### Test Macro Expansion

**Use `cargo expand` and `trybuild` for testing.**

```rust
// tests/expand.rs - using trybuild for compile-fail tests
#[test]
fn ui() {
    let t = trybuild::TestCases::new();
    t.pass("tests/cases/pass/*.rs");
    t.compile_fail("tests/cases/fail/*.rs");
}

// Manual expansion check with cargo-expand:
// $ cargo expand --test my_test
```

## Summary

- **NEVER** use macros when functions suffice
- **NEVER** expose internal items without `$crate`
- **DO** make macro syntax mirror the generated code
- **DO** use `$crate` for hygiene
- **DO** support attributes on generated items
- **DO** support visibility specifiers
- **DO** test in both module and function scope
- **DO** provide clear error messages with `compile_error!`
- **DO** minimize proc-macro dependencies
- **DON'T** create macros with surprising or ad-hoc syntax

---

## Related

- [modules.md](modules.md) - Macro visibility and exports
- [quality.md](quality.md) - Macro documentation

## References

- [Rust API Guidelines: Macros](https://rust-lang.github.io/api-guidelines/macros.html)
- [The Little Book of Rust Macros](https://veykril.github.io/tlborm/)
- [Procedural Macros Workshop](https://github.com/dtolnay/proc-macro-workshop)
