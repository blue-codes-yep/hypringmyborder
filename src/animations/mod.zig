//! Animation module exports
//! Provides different animation providers and the animation interface

pub const rainbow = @import("rainbow.zig");
pub const pulse = @import("pulse.zig");
pub const gradient = @import("gradient.zig");
pub const solid = @import("solid.zig");

const std = @import("std");
const config = @import("config");

/// Animation provider interface for different animation types
pub const AnimationProvider = struct {
    const Self = @This();

    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    updateFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) anyerror!void,
    configureFn: *const fn (ptr: *anyopaque, animation_config: config.AnimationConfig) anyerror!void,
    cleanupFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,

    pub fn update(self: *Self, allocator: std.mem.Allocator, socket_path: []const u8, time: f64) !void {
        try self.updateFn(self.ptr, allocator, socket_path, time);
    }

    pub fn configure(self: *Self, animation_config: config.AnimationConfig) !void {
        try self.configureFn(self.ptr, animation_config);
    }

    pub fn cleanup(self: *Self) void {
        self.cleanupFn(self.ptr, self.allocator);
    }
};

pub fn createAnimationProvider(allocator: std.mem.Allocator, animation_type: config.AnimationType) !AnimationProvider {
    switch (animation_type) {
        .rainbow => return rainbow.create(allocator),
        .pulse => return pulse.create(allocator),
        .gradient => return gradient.create(allocator),
        .solid => return solid.create(allocator),
    }
}
