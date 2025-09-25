const std = @import("std");

/// Build script for HyprIngMyBorder.
/// Defines reusable modules, the main executable, unit tests, and an interactive TUI test runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core library
    const hypr_mod = b.addModule("hypringmyborder", .{
        .root_source_file = b.path("src/hypringmyborder.zig"),
        .target = target,
    });

    // Utilities module
    const utils_mod = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/mod.zig"),
        .target = target,
    });

    // Config module (depends on utils)
    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("src/config/mod.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "utils", .module = utils_mod },
        },
    });

    // Animation providers (depends on config + utils)
    const animations_mod = b.addModule("animations", .{
        .root_source_file = b.path("src/animations/mod.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "utils", .module = utils_mod },
        },
    });

    // TUI module (standalone)
    const tui_mod = b.addModule("tui", .{
        .root_source_file = b.path("src/tui/mod.zig"),
        .target = target,
    });

    // --- Main Executable ---
    const exe = b.addExecutable(.{
        .name = "hypringmyborder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hypringmyborder", .module = hypr_mod },
                .{ .name = "config", .module = config_mod },
                .{ .name = "animations", .module = animations_mod },
                .{ .name = "utils", .module = utils_mod },
                .{ .name = "tui", .module = tui_mod },
            },
            .link_libc = true,
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the main executable");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // --- Unit tests (runs test "..." blocks) ---
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hypringmyborder", .module = hypr_mod },
                .{ .name = "config", .module = config_mod },
                .{ .name = "animations", .module = animations_mod },
                .{ .name = "utils", .module = utils_mod },
                .{ .name = "tui", .module = tui_mod },
            },
        }),
    });

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&unit_tests.step);

    // --- Interactive TUI Runner (executes tests/test_tui.zig) ---
    const test_tui_exe = b.addExecutable(.{
        .name = "test_tui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_tui.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tui", .module = tui_mod },
                .{ .name = "utils", .module = utils_mod },
                .{ .name = "config", .module = config_mod },
                .{ .name = "animations", .module = animations_mod },
                .{ .name = "hypringmyborder", .module = hypr_mod },
            },
            .link_libc = true,
        }),
    });

    const run_tui_test = b.step("run-tui-test", "Run the interactive TUI test");
    const run_tui_cmd = b.addRunArtifact(test_tui_exe);
    run_tui_test.dependOn(&run_tui_cmd.step);
}
