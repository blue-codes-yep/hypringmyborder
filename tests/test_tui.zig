const std = @import("std");
const tui = @import("tui");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Starting TUI Application Test\n", .{});
    std.debug.print("============================\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Tab - Switch panels\n", .{});
    std.debug.print("  F1  - Help screen\n", .{});
    std.debug.print("  Esc - Exit\n", .{});
    std.debug.print("  q   - Quick exit\n\n", .{});
    std.debug.print("Press Enter to start...", .{});

    // Wait for user to press Enter
    const stdin_file = std.fs.File{ .handle = 0 };
    var buffer: [1]u8 = undefined;
    _ = try stdin_file.read(buffer[0..]);

    // Initialize and run the TUI application
    var tui_app = try tui.TUIApp.init(allocator);
    defer tui_app.deinit();

    try tui_app.run();

    std.debug.print("TUI Application exited successfully!\n", .{});
}
