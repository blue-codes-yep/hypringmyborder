const std = @import("std");

/// This build script defines both a reusable library module and an executable
/// front‑end for the HyprIngMyBorder project.  The library exposes
/// functionality for animating Hyprland window borders, while the CLI
/// provides a comprehensive command‑line interface with modular architecture.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The core library module lives in src/hypringmyborder.zig.  Consumers of
    // this package can `@import("hypringmyborder")` to access its public
    // declarations.
    const hypr_mod = b.addModule("hypringmyborder", .{
        .root_source_file = b.path("src/hypringmyborder.zig"),
        .target = target,
    });

    // Utilities module (no dependencies)
    const utils_mod = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/mod.zig"),
        .target = target,
    });

    // Configuration module (depends on utils)
    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("src/config/mod.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "utils", .module = utils_mod },
        },
    });

    // Animation providers module (depends on config and utils)
    const animations_mod = b.addModule("animations", .{
        .root_source_file = b.path("src/animations/mod.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "utils", .module = utils_mod },
        },
    });

    // CLI module (depends on config, utils, and animations)
    const cli_mod = b.addModule("cli", .{
        .root_source_file = b.path("src/cli/mod.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "utils", .module = utils_mod },
            .{ .name = "animations", .module = animations_mod },
        },
    });

    // Define the CLI executable with all module dependencies
    const exe = b.addExecutable(.{
        .name = "hypringmyborder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hypringmyborder", .module = hypr_mod },
                .{ .name = "cli", .module = cli_mod },
                .{ .name = "config", .module = config_mod },
                .{ .name = "animations", .module = animations_mod },
                .{ .name = "utils", .module = utils_mod },
            },
        }),
    });

    // Install the executable into `zig-out/bin` when running `zig build`.
    b.installArtifact(exe);

    // Provide a `run` step to conveniently execute the program with `zig build run`.
    const run_step = b.step("run", "Run the CLI tool");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    // Allow users to pass additional arguments to the CLI via `zig build run -- ...`.
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
