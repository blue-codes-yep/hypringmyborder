//! Command‑line interface for HyprIngMyBorder.
//!
//! The CLI remembers a user‑selected FPS preset and runs the border
//! animation automatically.  When invoked without arguments, it will
//! attempt to load a saved preset from the user's configuration
//! directory (`{config_dir}/hypringmyborder/preset`).  If no preset is
//! found, it defaults to 15 FPS and records this choice for future
//! runs.  The CLI also supports an interactive configuration mode,
//! available via `--configure` (or `-c`), which presents a menu of
//! presets (15, 30, 60 FPS) and an option to install a Hyprland
//! autostart entry.  Selecting an FPS in the menu updates the saved
//! preset and immediately starts the animation.  The autostart
//! installer appends an `exec-once` directive pointing at the current
//! executable to `hyprland.conf` so the animation starts on login.

const std = @import("std");
const hypr = @import("hypringmyborder");

/// Determine the configuration directory according to the XDG Base Directory
/// specification.  Prefer `$XDG_CONFIG_HOME` if set, otherwise fall back
/// to `$HOME/.config`.  The returned slice is owned by the caller and
/// must be freed with the provided allocator.
fn getConfigDir(allocator: std.mem.Allocator) ![]u8 {
    const maybe_xdg = std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME") catch null;
    if (maybe_xdg) |xdg_val| {
        return xdg_val;
    } else {
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        return try std.fmt.allocPrint(allocator, "{s}/.config", .{home});
    }
}

/// Load the saved FPS preset if it exists.  The preset is stored in
/// `{config_dir}/hypringmyborder/preset` as plain text (e.g. "15\n").  If
/// the file does not exist or cannot be parsed, returns `null`.
fn loadPreset(allocator: std.mem.Allocator) ?u32 {
    const config_dir = getConfigDir(allocator) catch return null;
    defer allocator.free(config_dir);

    // Construct the path to the preset file.
    const preset_path = std.fmt.allocPrint(allocator, "{s}/hypringmyborder/preset", .{config_dir}) catch return null;
    defer allocator.free(preset_path);

    // Try to open the file; if it doesn’t exist, return null.
    var file = std.fs.openFileAbsolute(preset_path, .{ .mode = .read_only }) catch return null;
    defer file.close();

    // Read the preset into a small buffer.
    var buf: [32]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch return null;
    const slice = buf[0..bytes_read];

    // Trim whitespace and attempt to parse as a u32.
    const trimmed = std.mem.trim(u8, slice, " \n\r\t");
    if (trimmed.len == 0) return null;

    // DO NOT capture the error as a variable – simply return null on failure.
    const fps = std.fmt.parseInt(u32, trimmed, 10) catch {
        // Invalid contents; ignore and treat as no preset.
        return null;
    };

    return fps;
}

/// Save the given FPS preset to the preset file.  Creates the
/// `{config_dir}/hypringmyborder` directory if necessary.  Overwrites any
/// existing preset.  Writes the FPS as a decimal string followed by
/// newline.
fn savePreset(allocator: std.mem.Allocator, fps: u32) !void {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);
    const preset_dir = try std.fmt.allocPrint(allocator, "{s}/hypringmyborder", .{config_dir});
    defer allocator.free(preset_dir);
    const preset_path = try std.fmt.allocPrint(allocator, "{s}/preset", .{preset_dir});
    defer allocator.free(preset_path);

    // Ensure the directory exists.
    _ = std.fs.makeDirAbsolute(preset_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    // Open the file for writing (create or truncate).
    var file = try std.fs.createFileAbsolute(preset_path, .{ .truncate = true });
    defer file.close();
    // Write the FPS value and newline.
    var tmp_buf: [32]u8 = undefined;
    const written = try std.fmt.bufPrint(&tmp_buf, "{d}\n", .{fps});
    _ = try file.writeAll(written);
}

/// Run the rainbow animation with the given FPS.  Maps preset FPS values to
/// corresponding update intervals (ms) and invokes `hypr.runRainbow`.
fn runWithFps(allocator: std.mem.Allocator, fps: u32) !void {
    const interval_ms: u64 = switch (fps) {
        15 => 67,
        30 => 33,
        60 => 16,
        else => 67,
    };
    try hypr.runRainbow(allocator, 0.01, interval_ms);
}

/// Display the interactive menu.  Writes to stderr using std.debug.print
/// so that it works even if stdout is being piped elsewhere.
fn printMenu() void {
    std.debug.print(
        "\nHypringMyBorder CLI\n" ++ "Select an option:\n" ++ "  1) Run with 15 FPS\n" ++ "  2) Run with 30 FPS\n" ++ "  3) Run with 60 FPS\n" ++ "  4) Install autostart\n" ++ "  5) Exit\n",
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
/// The interactive menu driver.
fn interactive() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    while (true) {
        printMenu();
        std.debug.print("Choose an option: ", .{});

        var input_buf: [64]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&input_buf);
        const stdin_ifc = &stdin_reader.interface;

        const line = stdin_ifc.takeDelimiterExclusive('\n') catch |e| switch (e) {
            error.EndOfStream => return,
            else => return e,
        };
        if (line.len == 0) continue;

        const ch = line[0];
        switch (ch) {
            '1' => {
                savePreset(allocator, 15) catch |e| {
                    std.debug.print("Failed to save preset: {s}\n", .{@errorName(e)});
                };
                try runWithFps(allocator, 15);
                return;
            },
            '2' => {
                savePreset(allocator, 30) catch |e| {
                    std.debug.print("Failed to save preset: {s}\n", .{@errorName(e)});
                };
                try runWithFps(allocator, 30);
                return;
            },
            '3' => {
                savePreset(allocator, 60) catch |e| {
                    std.debug.print("Failed to save preset: {s}\n", .{@errorName(e)});
                };
                try runWithFps(allocator, 60);
                return;
            },
            '4' => {
                installAutostart(allocator) catch |e| {
                    std.debug.print("Failed to install autostart: {s}\n", .{@errorName(e)});
                };
            }, // <-- comma separates this case from the next
            '5' => {
                return;
            },
            else => {
                std.debug.print("Invalid selection. Please try again.\n", .{});
            },
        }
    }
}

/// Entry point for the CLI application.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        const arg1 = args[1];
        if (std.mem.eql(u8, arg1, "--configure") or std.mem.eql(u8, arg1, "-c")) {
            try interactive();
            return;
        }
    }

    // loadPreset returns ?u32, so no `try`.
    const maybe_fps = loadPreset(allocator);

    var fps: u32 = undefined;
    if (maybe_fps) |val| {
        // Use the saved preset
        fps = val;
    } else {
        // No preset: default to 15 and save it
        savePreset(allocator, 15) catch |e| {
            std.debug.print("Warning: failed to save default preset: {s}\n", .{@errorName(e)});
        };
        fps = 15;
    }

    try runWithFps(allocator, fps);
}
