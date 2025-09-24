//! Configuration persistence layer
//! Handles saving and loading configuration to/from JSON files

const std = @import("std");
const types = @import("types.zig");

pub const PersistenceError = error{
    ConfigNotFound,
    InvalidFormat,
    WriteError,
    ReadError,
};

pub fn getConfigDir(allocator: std.mem.Allocator) ![]u8 {
    const maybe_xdg = std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME") catch null;
    if (maybe_xdg) |xdg_val| {
        return xdg_val;
    } else {
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        return try std.fmt.allocPrint(allocator, "{s}/.config", .{home});
    }
}

pub fn getConfigPath(allocator: std.mem.Allocator) ![]u8 {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    return try std.fmt.allocPrint(allocator, "{s}/hypringmyborder/config.json", .{config_dir});
}

pub fn ensureConfigDir(allocator: std.mem.Allocator) !void {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const hypr_config_dir = try std.fmt.allocPrint(allocator, "{s}/hypringmyborder", .{config_dir});
    defer allocator.free(hypr_config_dir);

    std.fs.makeDirAbsolute(hypr_config_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn saveConfig(allocator: std.mem.Allocator, config: *const types.AnimationConfig) !void {
    try ensureConfigDir(allocator);

    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    // Create JSON representation
    var json_obj = std.json.ObjectMap.init(allocator);
    defer json_obj.deinit();

    try json_obj.put("version", std.json.Value{ .string = "1.0" });
    try json_obj.put("animation_type", std.json.Value{ .string = config.animation_type.toString() });
    try json_obj.put("fps", std.json.Value{ .integer = @intCast(config.fps) });
    try json_obj.put("speed", std.json.Value{ .float = config.speed });
    try json_obj.put("direction", std.json.Value{ .string = config.direction.toString() });

    // Convert colors to JSON array
    var colors_array = std.json.Array.init(allocator);
    defer colors_array.deinit();

    for (config.colors.items) |color| {
        const hex_color = try color.toHex(allocator);
        defer allocator.free(hex_color);
        try colors_array.append(std.json.Value{ .string = hex_color });
    }

    try json_obj.put("colors", std.json.Value{ .array = colors_array });

    const json_value = std.json.Value{ .object = json_obj };

    // Write to file
    const file = std.fs.createFileAbsolute(config_path, .{ .truncate = true }) catch {
        return PersistenceError.WriteError;
    };
    defer file.close();

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try std.json.Stringify.value(json_value, .{}, &out.writer);
    try file.writeAll(out.written());
}

pub fn loadConfig(allocator: std.mem.Allocator) !types.AnimationConfig {
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return PersistenceError.ConfigNotFound,
        else => return PersistenceError.ReadError,
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);

    _ = try file.readAll(contents);

    // Parse JSON
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{}) catch {
        return PersistenceError.InvalidFormat;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    // Extract configuration values
    const animation_type_str = root.get("animation_type").?.string;
    const animation_type = types.AnimationType.fromString(animation_type_str) orelse return PersistenceError.InvalidFormat;

    const fps = @as(u32, @intCast(root.get("fps").?.integer));
    const speed = root.get("speed").?.float;

    const direction_str = root.get("direction").?.string;
    const direction = types.AnimationDirection.fromString(direction_str) orelse return PersistenceError.InvalidFormat;

    // Parse colors
    var colors: std.ArrayList(types.ColorFormat) = .{};
    const colors_array = root.get("colors").?.array;

    for (colors_array.items) |color_value| {
        const color_str = color_value.string;
        const color = types.ColorFormat{ .hex = try allocator.dupe(u8, color_str) };
        try colors.append(allocator, color);
    }

    return types.AnimationConfig{
        .animation_type = animation_type,
        .fps = fps,
        .speed = speed,
        .colors = colors,
        .direction = direction,
    };
}
