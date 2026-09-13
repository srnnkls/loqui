---
paths: "**/*.rs, **/Cargo.toml"
---

# Rust Macros

Prefer functions, generics, and const evaluation when they express the operation clearly. Use macros for capabilities such as variadic input, item generation, derives, or syntax that cannot be expressed conveniently by a function.

## Familiar Input and Predictable Expansion

Make macro input resemble the Rust it generates. Support trailing commas and relevant visibility and attributes where callers need them. Evaluate input expressions the documented number of times; duplicating a token can duplicate an effect.

```rust
macro_rules! strings {
    ($($value:expr),* $(,)?) => {
        ::std::vec![$(($value).to_string()),*]
    };
}

let mut calls = 0;
let values = strings![{ calls += 1; calls }, "hello",];
assert_eq!(calls, 1);
assert_eq!(values, ["1", "hello"]);
```

Parenthesize expression fragments before attaching operations to preserve grouping. A small macro should not hide ownership transfer, control flow, or allocation that callers need to understand.

## Hygiene and Public Helpers

In an exported declarative macro, use `$crate` for paths into the defining crate and qualified paths for other dependencies where appropriate. `$crate` is robust to renaming the defining dependency; it does not bypass visibility. Helpers used by an external expansion must be accessible at that call site.

For example, an exported macro can refer to `$crate::__private::Vec` when the library deliberately provides a public hidden support module. `#[doc(hidden)]` hides documentation only; that helper still participates in the public expansion contract. Test the macro from a separate crate and with a renamed dependency.

[Serde's derive implementation](../../resources/languages/rust/serde/serde_derive/src) is a useful example of generated paths and public support requirements. Copy the principle, not an internal layout that happens to work in one crate. See the [Reference on macro hygiene](https://doc.rust-lang.org/reference/macros-by-example.html#hygiene).

## Preserve Attributes and Visibility

```rust
macro_rules! make_struct {
    (
        $(#[$attribute:meta])*
        $visibility:vis struct $name:ident {
            $(
                $(#[$field_attribute:meta])*
                $field_visibility:vis $field:ident: $ty:ty
            ),* $(,)?
        }
    ) => {
        $(#[$attribute])*
        $visibility struct $name {
            $(
                $(#[$field_attribute])*
                $field_visibility $field: $ty,
            )*
        }
    };
}

make_struct! {
    #[derive(Debug, Clone)]
    pub struct Config {
        /// Display name.
        pub name: String,
        pub(crate) enabled: bool,
    }
}

let config = Config { name: "example".into(), enabled: true };
assert!(config.enabled);
```

Forward only attributes whose placement is supported. A helper attribute such as `#[serde(default)]` needs its corresponding derive or attribute macro; forwarding it onto an otherwise plain struct does not make it valid.

Test the positions the macro promises to support: module scope, block scope, expressions, or other intended contexts. A macro need not work in every syntactic position, but its interface should make the intended use clear.

## Diagnostics

Use `compile_error!` for invalid macro syntax that the macro itself recognizes:

```rust,compile_fail
macro_rules! nonempty_struct {
    (struct $name:ident {}) => {
        compile_error!("struct must have at least one field");
    };
    (struct $name:ident { $($fields:tt)+ }) => {
        struct $name { $($fields)+ }
    };
}

nonempty_struct!(struct Empty {});
```

Token matching is syntactic, not semantic type analysis: matching the token `String` does not establish that an arbitrary alias resolves to the standard string type. Leave type-level constraints to generated Rust bounds where possible.

For procedural macros, attach errors to relevant input spans, for example through `syn::Error::new_spanned` and `to_compile_error`. Returning a deliberate diagnostic is more useful than panicking during expansion.

## Editions and Conditional Compilation

A macro's definition edition determines the meaning of fragment specifiers. In edition 2024, `expr` also matches top-level const blocks and underscore expressions. Use `expr_2021` to preserve earlier matching rules when required; there is no `expr_2024` fragment. Review arm precedence when migrating. See the [edition example](edition.md#macro-fragments-and-match-ergonomics).

`gen` is reserved in edition 2024. Use another identifier or `r#gen`; this reservation does not make generators stable.

On Rust 1.95+, `cfg_select!` selects the first matching configuration arm:

```rust
cfg_select! {
    unix => { fn platform() -> &'static str { "unix" } }
    windows => { fn platform() -> &'static str { "windows" } }
    _ => { fn platform() -> &'static str { "other" } }
}
assert!(!platform().is_empty());
```

Use ordinary `#[cfg]` for independent conditions. Remove a `cfg-if` dependency only after checking that the standard macro covers its uses and the project's supported compilers. See the [standard macro](https://doc.rust-lang.org/std/macro.cfg_select.html).

## Procedural Macro Crates

Put procedural macro entry points in a `proc-macro` crate. Select dependencies and features for the syntax actually parsed:

```toml
[lib]
proc-macro = true

[dependencies]
syn = { version = "2", default-features = false, features = ["derive", "parsing", "printing", "proc-macro"] }
quote = "1"
proc-macro2 = "1"
```

This is an example configuration for Syn 2, not a requirement to use that major version. Adding bodies or broader syntax may require additional features. Leaving default features enabled while adding a feature list does not disable the defaults. Follow the chosen version's [feature documentation](https://docs.rs/syn/2/syn/#optional-features).

Keep token parsing and generation separate enough to test independently. [Serde's derive sources](../../resources/languages/rust/serde/serde_derive/src) show why generic bounds, lifetimes, attributes, and crate paths need focused handling.

## Verify Generated Behavior

Use `cargo expand` to inspect expansions where helpful, and compile downstream examples to check hygiene, visibility, and type bounds. Use compile-pass and compile-fail cases for public macro contracts. A tool such as `trybuild` can snapshot diagnostics when their quality is important; review changes rather than accepting new snapshots automatically.

Do not compare expansion text as a substitute for checking behavior: Rust's hygiene is not fully represented by printed tokens. Run relevant runtime tests for expression evaluation count, moves, generated conversions, and other observable effects.

## Related

- [Edition 2024](edition.md): fragments and reserved identifiers
- [Modules](modules.md): public support surfaces and dependencies
- [Testing](test.md): downstream and compile-failure tests
- [API Guidelines: macros](../../resources/languages/rust/api-guidelines/src/macros.md)
- [Source catalog](resources.md): Serde implementation examples
