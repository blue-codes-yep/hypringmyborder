//! Preset management functionality
//! Handles CRUD operations for named configuration presets

const std = @import("std");
const types = @import("types.zig");
const persistence = @import("persistence.zig");

pub const PresetError = error{
    PresetNotFound,
    PresetAlreadyExists,
    InvalidPresetName,
};

pub fn getPresetsPath(allocator: std.mem.Allocator) ![]u8 {
    const config_dir = try persistence.getConfigDir(allocator);
    defer allocator.free(config_dir);

    return try std.fmt.allocPrint(allocator, "{s}/hypringmyborder/presets.json", .{config_dir});
}

pub fn loadPresets(allocator: std.mem.Allocator) !std.StringHashMap(types.Preset) {
    const presets_path = try getPresetsPath(allocator);
    defer allocator.free(presets_path);

    var presets = std.StringHashMap(types.Preset).init(allocator);

    const file = std.fs.openFileAbsolute(presets_path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => {
            // No presets file exists yet, return empty map
            return presets;
        },
        else => return err,
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);

    _ = try file.readAll(contents);

    // Parse JSON
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{}) catch {
        // Invalid JSON, return empty map
        return presets;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    var iterator = root.iterator();
    while (iterator.next()) |entry| {
        const preset_name = entry.key_ptr.*;
        const preset_obj = entry.value_ptr.*.object;

        // Parse preset configuration
        const animation_type_str = preset_obj.get("animation_type").?.string;
        const animation_type = types.AnimationType.fromString(animation_type_str) orelse continue;

        const fps = @as(u32, @intCast(preset_obj.get("fps").?.integer));
        const speed = preset_obj.get("speed").?.float;

        const direction_str = preset_obj.get("direction").?.string;
        const direction = types.AnimationDirection.fromString(direction_str) orelse continue;

        const created_at = preset_obj.get("created_at").?.integer;

        // Parse colors
        var colors: std.ArrayList(types.ColorFormat) = .{};
        const colors_array = preset_obj.get("colors").?.array;

        for (colors_array.items) |color_value| {
            const color_str = color_value.string;
            const color = types.ColorFormat{ .hex = try allocator.dupe(u8, color_str) };
            try colors.append(allocator, color);
        }

        const config = types.AnimationConfig{
            .animation_type = animation_type,
            .fps = fps,
            .speed = speed,
            .colors = colors,
            .direction = direction,
        };

        const preset = types.Preset{
            .name = try allocator.dupe(u8, preset_name),
            .config = config,
            .created_at = created_at,
        };

        try presets.put(preset.name, preset);
    }

    return presets;
}

pub fn savePresets(allocator: std.mem.Allocator, presets: *const std.StringHashMap(types.Preset)) !void {
    try persistence.ensureConfigDir(allocator);

    const presets_path = try getPresetsPath(allocator);
    defer allocator.free(presets_path);

    // Create JSON representation
    var json_obj = std.json.ObjectMap.init(allocator);
    defer json_obj.deinit();

    var iterator = presets.iterator();
    while (iterator.next()) |entry| {
        const preset = entry.value_ptr.*;

        var preset_obj = std.json.ObjectMap.init(allocator);
        defer preset_obj.deinit();

        try preset_obj.put("animation_type", std.json.Value{ .string = preset.config.animation_type.toString() });
        try preset_obj.put("fps", std.json.Value{ .integer = @intCast(preset.config.fps) });
        try preset_obj.put("speed", std.json.Value{ .float = preset.config.speed });
        try preset_obj.put("direction", std.json.Value{ .string = preset.config.direction.toString() });
        try preset_obj.put("created_at", std.json.Value{ .integer = preset.created_at });

        // Convert colors to JSON array
        var colors_array = std.json.Array.init(allocator);
        defer colors_array.deinit();

        for (preset.config.colors.items) |color| {
            const hex_color = try color.toHex(allocator);
            defer allocator.free(hex_color);
            try colors_array.append(std.json.Value{ .string = hex_color });
        }

        try preset_obj.put("colors", std.json.Value{ .array = colors_array });

        try json_obj.put(preset.name, std.json.Value{ .object = preset_obj });
    }

    const json_value = std.json.Value{ .object = json_obj };

    // Write to file
    const file = std.fs.createFileAbsolute(presets_path, .{ .truncate = true }) catch {
        return error.WriteError;
    };
    defer file.close();

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try std.json.Stringify.value(json_value, .{}, &out.writer);
    try file.writeAll(out.written());
}

pub fn savePreset(allocator: std.mem.Allocator, name: []const u8, config: *const types.AnimationConfig) !void {
    if (name.len == 0) return PresetError.InvalidPresetName;

    var presets = try loadPresets(allocator);
    defer {
        var iterator = presets.iterator();
        while (iterator.next()) |entry| {
            var preset = entry.value_ptr.*;
            preset.deinit(allocator);
        }
        presets.deinit();
    }

    const preset = try types.Preset.init(allocator, name, config.*);
    try presets.put(preset.name, preset);

    try savePresets(allocator, &presets);
}

pub fn loadPreset(allocator: std.mem.Allocator, name: []const u8) !types.AnimationConfig {
    var presets = try loadPresets(allocator);
    defer {
        var iterator = presets.iterator();
        while (iterator.next()) |entry| {
            var preset = entry.value_ptr.*;
            preset.deinit(allocator);
        }
        presets.deinit();
    }

    const preset = presets.get(name) orelse return PresetError.PresetNotFound;

    // Return a copy of the configuration
    var colors: std.ArrayList(types.ColorFormat) = .{};
    for (preset.config.colors.items) |color| {
        try colors.append(allocator, color);
    }

    return types.AnimationConfig{
        .animation_type = preset.config.animation_type,
        .fps = preset.config.fps,
        .speed = preset.config.speed,
        .colors = colors,
        .direction = preset.config.direction,
    };
}

pub fn deletePreset(allocator: std.mem.Allocator, name: []const u8) !void {
    var presets = try loadPresets(allocator);
    defer {
        var iterator = presets.iterator();
        while (iterator.next()) |entry| {
            var preset = entry.value_ptr.*;
            preset.deinit(allocator);
        }
        presets.deinit();
    }

    if (!presets.remove(name)) {
        return PresetError.PresetNotFound;
    }

    try savePresets(allocator, &presets);
}
