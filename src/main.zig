//! Enhanced command-line interface for HyprIngMyBorder.
//!
//! This is the main entry point for the enhanced CLI that provides a comprehensive
//! interactive configuration system with live preview, multiple animation types,
//! preset management, and Hyprland environment validation.
//!
//! Usage:
//!   hypringmyborder           - Run with last saved configuration
//!   hypringmyborder --cli     - Open interactive configuration menu
//!   hypringmyborder --help    - Show help information

const std = @import("std");
const hypr = @import("hypringmyborder");
const cli = @import("cli");
const config = @import("config");
const utils = @import("utils");

/// Print help information
fn printHelp() void {
    std.debug.print(
        \\HyprIngMyBorder - Enhanced Hyprland Border Animation
        \\
        \\Usage:
        \\  hypringmyborder           Run with last saved configuration
        \\  hypringmyborder --cli     Open interactive configuration menu
        \\  hypringmyborder --help    Show this help information
        \\
        \\The interactive menu (--cli) provides:
        \\  - Multiple animation types (rainbow, pulse, gradient, solid)
        \\  - Live preview of changes
        \\  - Preset management
        \\  - Fine-grained configuration options
        \\  - Hyprland environment validation
        \\
    , .{});
}

/// Run animation with saved configuration
fn runWithSavedConfig(allocator: std.mem.Allocator) !void {
    // Validate Hyprland environment first
    utils.environment.validateEnvironment(allocator) catch |err| {
        std.debug.print("Environment Error: {s}\n", .{@errorName(err)});
        std.debug.print("Use --cli to access system diagnostics and troubleshooting.\n", .{});
        return;
    };

    // Try to load saved configuration
    var animation_config = config.persistence.loadConfig(allocator) catch |err| switch (err) {
        config.persistence.PersistenceError.ConfigNotFound => blk: {
            std.debug.print("No saved configuration found. Using default settings.\n", .{});
            std.debug.print("Use --cli to configure your border animation.\n", .{});

            // Create and save default configuration
            var default_config = config.AnimationConfig.default();

            config.persistence.saveConfig(allocator, &default_config) catch |save_err| {
                std.debug.print("Warning: Could not save default configuration: {s}\n", .{@errorName(save_err)});
            };

            break :blk default_config;
        },
        else => blk: {
            std.debug.print("Error loading configuration: {s}\n", .{@errorName(err)});
            std.debug.print("Using default settings. Use --cli to reconfigure.\n", .{});
            break :blk config.AnimationConfig.default();
        },
    };
    defer animation_config.deinit(allocator);

    // Validate the loaded configuration
    animation_config.validate() catch |err| {
        std.debug.print("Invalid configuration: {s}\n", .{@errorName(err)});
        std.debug.print("Use --cli to fix the configuration.\n", .{});
        return;
    };

    // Get socket path
    const socket_path = utils.hyprland.getSocketPath(allocator) catch |err| {
        std.debug.print("Error getting Hyprland socket path: {s}\n", .{@errorName(err)});
        return;
    };
    defer allocator.free(socket_path);

    // Test connection
    if (!utils.hyprland.testConnection(socket_path)) {
        std.debug.print("Cannot connect to Hyprland. Make sure Hyprland is running.\n", .{});
        return;
    }

    std.debug.print("Starting border animation with {s} type at {d} FPS...\n", .{ animation_config.animation_type.toString(), animation_config.fps });
    std.debug.print("Press Ctrl+C to stop.\n", .{});

    // Create and run animation
    var animation_provider = @import("animations").createAnimationProvider(allocator, animation_config.animation_type) catch |err| {
        std.debug.print("Error creating animation provider: {s}\n", .{@errorName(err)});
        return;
    };
    defer animation_provider.cleanup();

    try animation_provider.configure(animation_config);

    // Animation loop
    var timer = try std.time.Timer.start();
    const frame_time_ns = std.time.ns_per_s / animation_config.fps;

    while (true) {
        const elapsed = @as(f64, @floatFromInt(timer.lap())) / std.time.ns_per_s;

        animation_provider.update(allocator, socket_path, elapsed) catch |err| {
            std.debug.print("Animation error: {s}\n", .{@errorName(err)});
            std.debug.print("Retrying in 1 second...\n", .{});
            std.Thread.sleep(std.time.ns_per_s);
            continue;
        };

        std.Thread.sleep(frame_time_ns);
    }
}

/// Run interactive CLI configuration
fn runInteractiveCLI(allocator: std.mem.Allocator) !void {
    // Check environment and show status
    const env_status = utils.environment.checkEnvironment(allocator) catch |err| {
        std.debug.print("Error checking environment: {s}\n", .{@errorName(err)});
        return;
    };
    defer {
        var mut_status = env_status;
        mut_status.deinit(allocator);
    }

    // Show environment status if there are issues
    if (!env_status.hyprland_running or !env_status.socket_accessible) {
        utils.environment.printEnvironmentStatus(&env_status);

        if (!env_status.hyprland_running) {
            std.debug.print("Hyprland is not running. Some features will be unavailable.\n", .{});
            std.debug.print("You can still configure settings, but live preview won't work.\n\n", .{});
        }
    }

    // Initialize menu system
    var menu_system = cli.menu.MenuSystem.init(allocator);
    defer menu_system.deinit();

    // Initialize preview manager if Hyprland is available
    var preview_manager: ?cli.preview.PreviewManager = null;
    if (env_status.hyprland_running and env_status.socket_accessible) {
        preview_manager = cli.preview.PreviewManager.init(allocator) catch |err| blk: {
            std.debug.print("Warning: Could not initialize preview manager: {s}\n", .{@errorName(err)});
            break :blk null;
        };

        if (preview_manager) |*pm| {
            menu_system.setPreviewManager(pm);
        }
    }
    defer if (preview_manager) |*pm| pm.deinit();

    // TODO: Set up main menu structure and run menu loop
    // This will be implemented in subsequent tasks

    std.debug.print("Interactive CLI configuration is not yet fully implemented.\n", .{});
    std.debug.print("This will be completed in the next implementation tasks.\n", .{});
    std.debug.print("For now, you can run without arguments to use the default animation.\n", .{});
}

/// Entry point for the CLI application
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse command line arguments
    if (args.len > 1) {
        const arg1 = args[1];
        if (std.mem.eql(u8, arg1, "--cli")) {
            try runInteractiveCLI(allocator);
            return;
        } else if (std.mem.eql(u8, arg1, "--help") or std.mem.eql(u8, arg1, "-h")) {
            printHelp();
            return;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg1});
            std.debug.print("Use --help for usage information.\n", .{});
            return;
        }
    }

    // Run with saved configuration
    try runWithSavedConfig(allocator);
}
