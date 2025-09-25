//! Live preview management for real-time border animation updates
//! Handles threading and Hyprland IPC communication for preview functionality

const std = @import("std");
const config = @import("config");
const utils = @import("utils");

pub const PreviewManager = struct {
    allocator: std.mem.Allocator,
    current_config: config.AnimationConfig,
    animation_thread: ?std.Thread = null,
    should_stop: std.atomic.Value(bool),
    socket_path: []const u8,

    pub fn init(allocator: std.mem.Allocator) !PreviewManager {
        const socket_path = try utils.hyprland.getSocketPath(allocator);

        return PreviewManager{
            .allocator = allocator,
            .current_config = config.AnimationConfig.default(),
            .should_stop = std.atomic.Value(bool).init(false),
            .socket_path = socket_path,
        };
    }

    pub fn updateConfig(self: *PreviewManager, new_config: config.AnimationConfig) !void {
        self.current_config = new_config;

        // If preview is running, the animation thread will pick up the new config
        // on its next iteration due to shared memory access
    }

    pub fn start(self: *PreviewManager) !void {
        if (self.animation_thread != null) return; // Already running

        self.should_stop.store(false, .release);
        self.animation_thread = try std.Thread.spawn(.{}, previewThread, .{self});
    }

    pub fn stop(self: *PreviewManager) void {
        if (self.animation_thread == null) return;

        self.should_stop.store(true, .release);
        self.animation_thread.?.join();
        self.animation_thread = null;
    }

    pub fn deinit(self: *PreviewManager) void {
        self.stop();
        self.allocator.free(self.socket_path);
    }

    fn previewThread(self: *PreviewManager) !void {
        var hue: f64 = 0.0;

        while (!self.should_stop.load(.acquire)) {
            // Get current config (thread-safe read)
            const current_config = self.current_config;

            // Calculate frame timing
            const frame_time_ns = std.time.ns_per_s / current_config.fps;

            // Update animation based on type
            switch (current_config.animation_type) {
                .rainbow => {
                    try utils.hyprland.updateRainbowBorder(self.allocator, self.socket_path, hue);
                    hue = @mod(hue + current_config.speed, 1.0);
                },
                .pulse => {
                    // TODO: Implement pulse animation
                },
                .gradient => {
                    // TODO: Implement gradient animation
                },
                .solid => {
                    // TODO: Implement solid color animation
                },
            }

            std.Thread.sleep(frame_time_ns);
        }
    }
};
