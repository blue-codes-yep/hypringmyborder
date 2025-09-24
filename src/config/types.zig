//! Configuration data structures and types
//! Defines core data types for animation configuration and validation

const std = @import("std");

pub const AnimationType = enum {
    rainbow,
    pulse,
    gradient,
    solid,

    pub fn toString(self: AnimationType) []const u8 {
        return switch (self) {
            .rainbow => "rainbow",
            .pulse => "pulse",
            .gradient => "gradient",
            .solid => "solid",
        };
    }

    pub fn fromString(str: []const u8) ?AnimationType {
        if (std.mem.eql(u8, str, "rainbow")) return .rainbow;
        if (std.mem.eql(u8, str, "pulse")) return .pulse;
        if (std.mem.eql(u8, str, "gradient")) return .gradient;
        if (std.mem.eql(u8, str, "solid")) return .solid;
        return null;
    }
};

pub const ColorFormat = union(enum) {
    hex: []const u8,
    rgb: [3]u8,
    hsv: [3]f64,

    pub fn toHex(self: ColorFormat, allocator: std.mem.Allocator) ![]u8 {
        switch (self) {
            .hex => |hex| return try allocator.dupe(u8, hex),
            .rgb => |rgb| return try std.fmt.allocPrint(allocator, "#{X:0>2}{X:0>2}{X:0>2}", .{ rgb[0], rgb[1], rgb[2] }),
            .hsv => |hsv| {
                const rgb = hsvToRgb(hsv[0], hsv[1], hsv[2]);
                return try std.fmt.allocPrint(allocator, "#{X:0>2}{X:0>2}{X:0>2}", .{ rgb[0], rgb[1], rgb[2] });
            },
        }
    }

    fn hsvToRgb(h: f64, s: f64, v: f64) [3]u8 {
        const i = @as(u8, @intFromFloat(@floor(h * 6.0))) % 6;
        const f = h * 6.0 - @floor(h * 6.0);
        const p = v * (1.0 - s);
        const q = v * (1.0 - f * s);
        const t = v * (1.0 - (1.0 - f) * s);

        var r: f64 = 0;
        var g: f64 = 0;
        var b: f64 = 0;

        switch (i) {
            0 => {
                r = v;
                g = t;
                b = p;
            },
            1 => {
                r = q;
                g = v;
                b = p;
            },
            2 => {
                r = p;
                g = v;
                b = t;
            },
            3 => {
                r = p;
                g = q;
                b = v;
            },
            4 => {
                r = t;
                g = p;
                b = v;
            },
            else => {
                r = v;
                g = p;
                b = q;
            },
        }

        return .{
            @as(u8, @intFromFloat(r * 255.0)),
            @as(u8, @intFromFloat(g * 255.0)),
            @as(u8, @intFromFloat(b * 255.0)),
        };
    }
};

pub const AnimationDirection = enum {
    clockwise,
    counter_clockwise,

    pub fn toString(self: AnimationDirection) []const u8 {
        return switch (self) {
            .clockwise => "clockwise",
            .counter_clockwise => "counter_clockwise",
        };
    }

    pub fn fromString(str: []const u8) ?AnimationDirection {
        if (std.mem.eql(u8, str, "clockwise")) return .clockwise;
        if (std.mem.eql(u8, str, "counter_clockwise")) return .counter_clockwise;
        return null;
    }
};

pub const AnimationConfig = struct {
    animation_type: AnimationType,
    fps: u32,
    speed: f64,
    colors: std.ArrayList(ColorFormat),
    direction: AnimationDirection,

    pub fn default() AnimationConfig {
        return AnimationConfig{
            .animation_type = .rainbow,
            .fps = 30,
            .speed = 0.01,
            .colors = .{},
            .direction = .clockwise,
        };
    }

    pub fn validate(self: *const AnimationConfig) !void {
        if (self.fps < 1 or self.fps > 120) {
            return error.FpsOutOfRange;
        }

        if (self.speed < 0.001 or self.speed > 1.0) {
            return error.SpeedOutOfRange;
        }

        // Validate colors based on animation type
        switch (self.animation_type) {
            .pulse => {
                if (self.colors.items.len < 1) {
                    return error.InsufficientColors;
                }
            },
            .gradient => {
                if (self.colors.items.len < 2) {
                    return error.InsufficientColors;
                }
            },
            .solid => {
                if (self.colors.items.len < 1) {
                    return error.InsufficientColors;
                }
            },
            .rainbow => {
                // Rainbow doesn't require specific colors
            },
        }

        // Validate each color format
        for (self.colors.items) |color| {
            switch (color) {
                .hex => |hex| {
                    if (hex.len != 7 or hex[0] != '#') {
                        return error.InvalidColorFormat;
                    }
                    for (hex[1..]) |c| {
                        if (!std.ascii.isHex(c)) {
                            return error.InvalidColorFormat;
                        }
                    }
                },
                .rgb => |rgb| {
                    // RGB values are inherently valid as u8 (0-255)
                    _ = rgb;
                },
                .hsv => |hsv| {
                    if (hsv[0] < 0.0 or hsv[0] > 1.0 or hsv[1] < 0.0 or hsv[1] > 1.0 or hsv[2] < 0.0 or hsv[2] > 1.0) {
                        return error.InvalidColorFormat;
                    }
                },
            }
        }
    }

    pub fn deinit(self: *AnimationConfig, allocator: std.mem.Allocator) void {
        self.colors.deinit(allocator);
    }
};

pub const Preset = struct {
    name: []const u8,
    config: AnimationConfig,
    created_at: i64,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, config: AnimationConfig) !Preset {
        const owned_name = try allocator.dupe(u8, name);

        return Preset{
            .name = owned_name,
            .config = config,
            .created_at = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Preset, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.config.deinit(allocator);
    }
};
