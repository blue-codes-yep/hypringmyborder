const std = @import("std");

/// This build script defines both a reusable library module and an executable
/// front‑end for the HyprIngMyBorder project.  The library exposes
/// functionality for animating Hyprland window borders, while the CLI
/// provides a simple command‑line interface to control the animation speed
/// and update frequency.
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

    // Define the CLI executable.  Its root module is src/main.zig which
    // imports `hypringmyborder` and parses command‑line arguments.
    const exe = b.addExecutable(.{
        .name = "hypringmyborder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ .{ .name = "hypringmyborder", .module = hypr_mod } },
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