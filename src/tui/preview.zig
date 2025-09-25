//! Live preview management for real-time border animation updates
//! Handles threading and Hyprland IPC communication for preview functionality

const std = @import("std");
const config = @import("config");
const utils = @import("utils");
const animations = @import("animations");

/// Preview status enumeration for UI feedback
pub const PreviewStatus = enum {
    stopped,
    starting,
    running,
    err,

    pub fn toString(self: PreviewStatus) []const u8 {
        return switch (self) {
            .stopped => "Stopped",
            .starting => "Starting...",
            .running => "Running",
            .err => "Error",
        };
    }
};

/// Preview statistics for monitoring
pub const PreviewStats = struct {
    frames_rendered: u64 = 0,
    last_frame_time: i64 = 0,
    actual_fps: f32 = 0.0,
    connection_status: bool = false,

    pub fn updateFrameStats(self: *PreviewStats, target_fps: u32) void {
        _ = target_fps; // Unused for now, but may be used for FPS calculations later
        const now = std.time.milliTimestamp();
        if (self.last_frame_time > 0) {
            const frame_delta = now - self.last_frame_time;
            if (frame_delta > 0) {
                self.actual_fps = 1000.0 / @as(f32, @floatFromInt(frame_delta));
            }
        }
        self.last_frame_time = now;
        self.frames_rendered += 1;
    }
};

pub const PreviewManager = struct {
    allocator: std.mem.Allocator,
    current_config: config.AnimationConfig,
    animation_thread: ?std.Thread = null,
    should_stop: std.atomic.Value(bool),
    config_changed: std.atomic.Value(bool),
    socket_path: []const u8,

    // Status and statistics (thread-safe access)
    status: std.atomic.Value(u8),
    stats: PreviewStats,
    stats_mutex: std.Thread.Mutex,

    // Animation provider
    animation_provider: ?animations.AnimationProvider = null,

    pub fn init(allocator: std.mem.Allocator) !PreviewManager {
        const socket_path = try utils.hyprland.getSocketPath(allocator);

        return PreviewManager{
            .allocator = allocator,
            .current_config = config.AnimationConfig.default(),
            .should_stop = std.atomic.Value(bool).init(false),
            .config_changed = std.atomic.Value(bool).init(false),
            .socket_path = socket_path,
            .status = std.atomic.Value(u8).init(@intFromEnum(PreviewStatus.stopped)),
            .stats = PreviewStats{},
            .stats_mutex = std.Thread.Mutex{},
        };
    }

    /// Thread-safe configuration update
    pub fn updateConfig(self: *PreviewManager, new_config: config.AnimationConfig) !void {
        // Validate the new configuration
        try new_config.validate();

        // Update configuration atomically
        self.current_config = new_config;
        self.config_changed.store(true, .release);
    }

    /// Start the preview with proper error handling
    pub fn start(self: *PreviewManager) !void {
        if (self.animation_thread != null) return; // Already running

        // Test Hyprland connection before starting
        if (!utils.hyprland.testConnection(self.socket_path)) {
            self.status.store(@intFromEnum(PreviewStatus.err), .release);
            return error.HyprlandConnectionFailed;
        }

        self.status.store(@intFromEnum(PreviewStatus.starting), .release);
        self.should_stop.store(false, .release);
        self.config_changed.store(true, .release); // Force initial config load

        // Reset statistics
        {
            self.stats_mutex.lock();
            defer self.stats_mutex.unlock();
            self.stats = PreviewStats{};
        }

        self.animation_thread = try std.Thread.spawn(.{}, previewThread, .{self});
    }

    /// Stop the preview gracefully
    pub fn stop(self: *PreviewManager) void {
        if (self.animation_thread == null) return;

        self.should_stop.store(true, .release);
        self.animation_thread.?.join();
        self.animation_thread = null;

        // Clean up animation provider
        if (self.animation_provider) |*provider| {
            provider.cleanup();
            self.animation_provider = null;
        }

        self.status.store(@intFromEnum(PreviewStatus.stopped), .release);
    }

    /// Get current preview status (thread-safe)
    pub fn getStatus(self: *const PreviewManager) PreviewStatus {
        const status_int = self.status.load(.acquire);
        return @enumFromInt(status_int);
    }

    /// Get current preview statistics (thread-safe)
    pub fn getStats(self: *PreviewManager) PreviewStats {
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();
        return self.stats;
    }

    /// Check if preview is currently running
    pub fn isRunning(self: *const PreviewManager) bool {
        return self.getStatus() == .running;
    }

    pub fn deinit(self: *PreviewManager) void {
        self.stop();
        self.allocator.free(self.socket_path);
    }

    /// Main preview thread function with proper error handling and animation provider integration
    fn previewThread(self: *PreviewManager) !void {
        var timer = try std.time.Timer.start();
        var last_config_type: ?config.AnimationType = null;

        // Set status to running once thread starts successfully
        self.status.store(@intFromEnum(PreviewStatus.running), .release);

        while (!self.should_stop.load(.acquire)) {
            // Check for configuration changes
            if (self.config_changed.swap(false, .acq_rel)) {
                const current_config = self.current_config;

                // Recreate animation provider if type changed
                if (last_config_type == null or last_config_type.? != current_config.animation_type) {
                    // Clean up old provider
                    if (self.animation_provider) |*provider| {
                        provider.cleanup();
                    }

                    // Create new provider
                    self.animation_provider = animations.createAnimationProvider(self.allocator, current_config.animation_type) catch |err| {
                        std.log.err("Failed to create animation provider: {}", .{err});
                        self.status.store(@intFromEnum(PreviewStatus.err), .release);
                        return;
                    };

                    last_config_type = current_config.animation_type;
                }

                // Configure the animation provider
                if (self.animation_provider) |*provider| {
                    provider.configure(current_config) catch |err| {
                        std.log.err("Failed to configure animation provider: {}", .{err});
                        self.status.store(@intFromEnum(PreviewStatus.err), .release);
                        return;
                    };
                }
            }

            // Update animation if provider is available
            if (self.animation_provider) |*provider| {
                const elapsed_time = @as(f64, @floatFromInt(timer.read())) / std.time.ns_per_s;

                provider.update(self.allocator, self.socket_path, elapsed_time) catch |err| {
                    std.log.err("Animation update failed: {}", .{err});

                    // Test connection and update status
                    if (!utils.hyprland.testConnection(self.socket_path)) {
                        self.status.store(@intFromEnum(PreviewStatus.err), .release);
                        {
                            self.stats_mutex.lock();
                            defer self.stats_mutex.unlock();
                            self.stats.connection_status = false;
                        }
                    }

                    // Continue trying - don't exit on single frame failure
                    std.Thread.sleep(100 * std.time.ns_per_ms); // Brief pause on error
                    continue;
                };

                // Update statistics
                {
                    self.stats_mutex.lock();
                    defer self.stats_mutex.unlock();
                    self.stats.updateFrameStats(self.current_config.fps);
                    self.stats.connection_status = true;
                }
            }

            // Calculate frame timing
            const current_config = self.current_config;
            const frame_time_ns = std.time.ns_per_s / current_config.fps;
            std.Thread.sleep(frame_time_ns);
        }
    }
};
