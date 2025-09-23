//! Command‑line interface for HyprIngMyBorder.
//!
//! This front‑end provides an interactive menu for the user.  Instead of
//! requiring command‑line flags, the program prompts the user to pick
//! between a few sensible presets (15 FPS, 30 FPS or 60 FPS) or to
//! install the program as a Hyprland autostart entry.  Only after the
//! user selects one of the run options will the tool connect to the
//! Hyprland IPC and begin animating borders.

const std = @import("std");
const hypr = @import("hypringmyborder");

/// Display the interactive menu.  Writes to stderr using std.debug.print
/// so that it works even if stdout is being piped elsewhere.
fn printMenu() void {
    std.debug.print(
        "\nHyprIngMyBorder CLI\n" ++ "Select an option:\n" ++ "  1) Run with 15 FPS\n" ++ "  2) Run with 30 FPS\n" ++ "  3) Run with 60 FPS\n" ++ "  4) Install autostart\n" ++ "  5) Exit\n",
        .{},
    );
}

/// Add an `exec-once` directive for this program to the user's Hyprland
/// configuration.  The function appends a line pointing at the current
/// executable to `~/.config/hypr/hyprland.conf` (falling back to
/// `$XDG_CONFIG_HOME` if defined).  If the line already exists it does
/// nothing.  Errors are reported to the user via std.debug.print.
fn installAutostart(allocator: std.mem.Allocator) !void {
    // Determine the absolute path to this executable.
    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);

    // Compute the configuration directory.  Prefer XDG_CONFIG_HOME when set.
    // The returned string is owned by this function and must be freed at the
    // end.  We use a single defer after assigning `config_dir` regardless of
    // which branch is taken.
    var config_dir: []const u8 = undefined;
    {
        const maybe_xdg = std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME") catch null;
        if (maybe_xdg) |xdg_val| {
            config_dir = xdg_val;
        } else {
            const home = try std.process.getEnvVarOwned(allocator, "HOME");
            defer allocator.free(home);
            config_dir = try std.fmt.allocPrint(allocator, "{s}/.config", .{home});
        }
    }
    defer allocator.free(config_dir);

    // Build the Hyprland configuration path.
    const conf_path = try std.fmt.allocPrint(allocator, "{s}/hypr/hyprland.conf", .{config_dir});
    defer allocator.free(conf_path);

    // Attempt to open the file for reading and writing.  If it does not
    // exist, create the necessary directory hierarchy and a new file.
    var file: std.fs.File = undefined;
    {
        const result = std.fs.openFileAbsolute(conf_path, .{ .mode = .read_write }) catch |err| err;
        if (result) |opened| {
            file = opened;
        } else |err| switch (err) {
            // If the file is missing, create the parent directory and the file.
            error.FileNotFound => {
                // Ensure the hypr directory exists.
                const hypr_dir = try std.fmt.allocPrint(allocator, "{s}/hypr", .{config_dir});
                defer allocator.free(hypr_dir);
                _ = std.fs.makeDirAbsolute(hypr_dir) catch |e| switch (e) {
                    error.PathAlreadyExists => {},
                    else => return e,
                };
                // Create the hyprland.conf file.
                file = try std.fs.createFileAbsolute(conf_path, .{ .truncate = false });
            },
            else => return err,
        }
    }
    defer file.close();

    // Read the existing contents (up to 1 MiB) to check for duplicate entries.
    // If the file grows beyond this size there may be false negatives, but
    // Hyprland configs are typically small.  In Zig 0.16 we avoid deprecated
    // `readToEndAlloc` APIs and instead determine the file size, allocate a
    // buffer, and read into it.  We cap the allocation at 1 MiB to avoid
    // consuming too much memory.
    const max_bytes: usize = 1024 * 1024;
    // Determine the current file length.  If this fails (e.g. streaming
    // input), assume zero length.
    const file_size: usize = blk: {
        const end_pos = file.getEndPos() catch break :blk 0;
        // Cast the file size to usize.  In Zig 0.16 the preferred way to
        // perform integer casts is with @as() rather than @intCast() with two
        // parameters.
        break :blk @min(max_bytes, @as(usize, end_pos));
    };
    var contents: []u8 = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);
    // Seek back to the beginning before reading.
    _ = file.seekTo(0) catch {};
    const bytes_read = try file.readAll(contents);
    const contents_slice = contents[0..bytes_read];
    // If the config already mentions the executable, do nothing.
    // Check if the existing configuration already contains the executable path.
    // `std.mem.indexOf` returns `null` if `needle` is not present.
    if (std.mem.indexOf(u8, contents_slice, exe_path) != null) {
        std.debug.print("Autostart entry already exists in {s}\n", .{conf_path});
        return;
    }
    // Append a newline and the exec-once directive.
    const line = try std.fmt.allocPrint(allocator, "\nexec-once = {s}\n", .{exe_path});
    defer allocator.free(line);
    try file.seekFromEnd(0);
    _ = try file.writeAll(line);
    std.debug.print("Added autostart entry to {s}\n", .{conf_path});
}

/// The interactive top‑level driver.  Presents a menu until the user
/// selects a run preset or exits.  When a run preset is chosen, this
/// function calls `hypr.runRainbow` with a corresponding update interval
/// and a default hue step.  Because `runRainbow` loops forever, the
/// program will not return to the menu unless interrupted.
fn interactive() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    while (true) {
        printMenu();
        std.debug.print("Choose an option: ", .{});
        // Use a buffered reader on stdin.  We allocate a small buffer and
        // then read a line up to the newline delimiter.  The first character
        // of the line is used as the menu selection.
        var input_buf: [64]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&input_buf);
        const stdin_ifc = &stdin_reader.interface;
        // Read until newline (exclusive).  End of stream returns error.EndOfStream.
        const line = stdin_ifc.takeDelimiterExclusive('\n') catch |e| switch (e) {
            error.EndOfStream => return,
            else => return e,
        };
        if (line.len == 0) {
            // Empty input; just prompt again.
            continue;
        }
        const ch = line[0];
        switch (ch) {
            '1' => {
                // 15 FPS -> interval 66.66... ms (approx).  We round to 67 ms.
                try hypr.runRainbow(allocator, 0.01, 67);
                return;
            },
            '2' => {
                // 30 FPS -> 33 ms interval.
                try hypr.runRainbow(allocator, 0.01, 33);
                return;
            },
            '3' => {
                // 60 FPS -> 16 ms interval.
                try hypr.runRainbow(allocator, 0.01, 16);
                return;
            },
            '4' => {
                // Install autostart entry.
                installAutostart(allocator) catch |e| {
                    std.debug.print("Failed to install autostart: {s}\n", .{@errorName(e)});
                };
            },
            '5' => {
                // Exit the program.
                return;
            },
            else => {
                std.debug.print("Invalid selection. Please try again.\n", .{});
            },
        }
    }
}

/// Entry point for the CLI application.  Delegates to the
/// interactive driver.
pub fn main() !void {
    try interactive();
}

