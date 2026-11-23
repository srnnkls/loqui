//! Build steps shared by loqui Zig projects.
//!
//! From `build.zig`:
//!
//!     const loqui = @import(".loqui/zig/check.zig");
//!     loqui.addChecks(b, root_module);
//!
//! `zig build fmt` fails on unformatted sources; `zig build check` analyzes
//! the module's tests without emitting a binary. Analysis is lazy, so a
//! module reaches every declaration only through
//! `test { std.testing.refAllDecls(@This()); }` in its root file.

const std = @import("std");

pub fn addChecks(b: *std.Build, root_module: *std.Build.Module) void {
    const fmt = b.addFmt(.{
        .paths = &.{ "build.zig", "src" },
        .check = true,
    });
    b.step("fmt", "Fail on unformatted Zig sources").dependOn(&fmt.step);

    const tests = b.addTest(.{ .root_module = root_module });
    b.step("check", "Analyze the module's tests without emitting a binary").dependOn(&tests.step);
}
