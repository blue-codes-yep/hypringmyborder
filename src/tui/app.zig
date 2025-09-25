//! Main TUI Application
//! Manages the overall Terminal User Interface state and screen management

const std = @import("std");
const renderer = @import("renderer.zig");
const events = @import("events.zig");
const components = @import("components/mod.zig");
const preview = @import("preview.zig");
const config = @import("config");

pub const Screen = enum {
    main,
    help,
};

pub const TUIApp = struct {
    allocator: std.mem.Allocator,
    renderer: renderer.Renderer,
    event_handler: events.SimpleEventHandler,
    current_screen: Screen,
    should_exit: bool,

    // Preview management
    preview_manager: preview.PreviewManager,
    current_config: config.AnimationConfig,

    // Main screen components
    main_panels: [4]components.Panel,
    status_text: components.Text,
    help_text: components.Text,

    pub fn init(allocator: std.mem.Allocator) !TUIApp {
        const r = try renderer.Renderer.init(allocator);
        const event_handler = try events.SimpleEventHandler.init();

        // Initialize preview manager
        const preview_manager = try preview.PreviewManager.init(allocator);

        // Initialize default configuration
        var default_config = config.AnimationConfig.default();
        default_config.colors = .{};

        // Initialize main screen panels
        const terminal_size = r.getTerminalSize();
        const panel_width = (terminal_size.width - 6) / 2; // Leave margins and space between panels
        const panel_height = (terminal_size.height - 8) / 2; // Leave space for header and footer

        var main_panels = [4]components.Panel{
            components.Panel.init("Animation Settings", 2, 3, panel_width, panel_height),
            components.Panel.init("Live Preview", 4 + panel_width, 3, panel_width, panel_height),
            components.Panel.init("Presets", 2, 5 + panel_height, panel_width, panel_height),
            components.Panel.init("System Status", 4 + panel_width, 5 + panel_height, panel_width, panel_height),
        };

        // Set first panel as focused
        main_panels[0].setFocus(true);

        const status_text = components.Text.initWithStyle("[Tab] Switch Panel  [Enter] Select  [Esc] Exit  [F1] Help  [F2] Start/Stop Preview", 2, terminal_size.height - 2, renderer.TextStyle{ .fg_color = renderer.Color.CYAN });

        const help_text = components.Text.initWithStyle("HyprIngMyBorder Configuration - Press F1 for help", 2, 1, renderer.TextStyle{ .fg_color = renderer.Color.YELLOW, .bold = true });

        return TUIApp{
            .allocator = allocator,
            .renderer = r,
            .event_handler = event_handler,
            .current_screen = Screen.main,
            .should_exit = false,
            .preview_manager = preview_manager,
            .current_config = default_config,
            .main_panels = main_panels,
            .status_text = status_text,
            .help_text = help_text,
        };
    }

    pub fn run(self: *TUIApp) !void {
        try self.renderer.clear();
        try self.renderer.hideCursor();

        while (!self.should_exit) {
            try self.render();
            try self.handleInput();
        }

        try self.renderer.showCursor();
        try self.renderer.clear();
    }

    fn render(self: *TUIApp) !void {
        try self.renderer.clear();

        switch (self.current_screen) {
            .main => try self.renderMainScreen(),
            .help => try self.renderHelpScreen(),
        }
    }

    fn renderMainScreen(self: *TUIApp) !void {
        // Render header
        try self.help_text.render(&self.renderer);

        // Render main panels
        for (&self.main_panels, 0..) |*panel, i| {
            try panel.render(&self.renderer);

            const content_area = panel.getContentArea();
            if (content_area.width > 0 and content_area.height > 0) {
                switch (i) {
                    0 => try self.renderAnimationSettingsPanel(content_area),
                    1 => try self.renderLivePreviewPanel(content_area),
                    2 => try self.renderPresetsPanel(content_area),
                    3 => try self.renderSystemStatusPanel(content_area),
                    else => {},
                }
            }
        }

        // Render status bar
        try self.status_text.render(&self.renderer);
    }

    fn renderAnimationSettingsPanel(self: *TUIApp, area: @import("components/panel.zig").ContentArea) !void {
        var y = area.y + 1;

        // Animation type
        const type_text = try std.fmt.allocPrint(self.allocator, "Type: {s}", .{self.current_config.animation_type.toString()});
        defer self.allocator.free(type_text);
        const type_display = components.Text.init(type_text, area.x + 1, y);
        try type_display.render(&self.renderer);
        y += 1;

        // FPS
        const fps_text = try std.fmt.allocPrint(self.allocator, "FPS:  {d}", .{self.current_config.fps});
        defer self.allocator.free(fps_text);
        const fps_display = components.Text.init(fps_text, area.x + 1, y);
        try fps_display.render(&self.renderer);
        y += 1;

        // Speed
        const speed_text = try std.fmt.allocPrint(self.allocator, "Speed: {d:.3}", .{self.current_config.speed});
        defer self.allocator.free(speed_text);
        const speed_display = components.Text.init(speed_text, area.x + 1, y);
        try speed_display.render(&self.renderer);
        y += 1;

        // Direction
        const dir_text = try std.fmt.allocPrint(self.allocator, "Dir:  {s}", .{self.current_config.direction.toString()});
        defer self.allocator.free(dir_text);
        const dir_display = components.Text.init(dir_text, area.x + 1, y);
        try dir_display.render(&self.renderer);
    }

    fn renderLivePreviewPanel(self: *TUIApp, area: @import("components/panel.zig").ContentArea) !void {
        var y = area.y + 1;

        // Preview status with visual indicator
        const status = self.preview_manager.getStatus();
        const status_color = switch (status) {
            .stopped => renderer.Color.WHITE,
            .starting => renderer.Color.YELLOW,
            .running => renderer.Color.GREEN,
            .err => renderer.Color.RED,
        };

        const status_indicator = switch (status) {
            .stopped => "●",
            .starting => "◐",
            .running => "●",
            .err => "✗",
        };

        const status_text = try std.fmt.allocPrint(self.allocator, "{s} Status: {s}", .{ status_indicator, status.toString() });
        defer self.allocator.free(status_text);
        const status_display = components.Text.initWithStyle(status_text, area.x + 1, y, renderer.TextStyle{ .fg_color = status_color, .bold = true });
        try status_display.render(&self.renderer);
        y += 2;

        // Preview statistics if running
        if (status == .running) {
            const stats = self.preview_manager.getStats();

            // Animation info
            const anim_text = try std.fmt.allocPrint(self.allocator, "Animation: {s}", .{self.current_config.animation_type.toString()});
            defer self.allocator.free(anim_text);
            const anim_display = components.Text.init(anim_text, area.x + 1, y);
            try anim_display.render(&self.renderer);
            y += 1;

            // Frame statistics
            const frames_text = try std.fmt.allocPrint(self.allocator, "Frames: {d}", .{stats.frames_rendered});
            defer self.allocator.free(frames_text);
            const frames_display = components.Text.init(frames_text, area.x + 1, y);
            try frames_display.render(&self.renderer);
            y += 1;

            // FPS comparison
            const target_fps = self.current_config.fps;
            const fps_color = if (@abs(stats.actual_fps - @as(f32, @floatFromInt(target_fps))) < 5.0)
                renderer.Color.GREEN
            else
                renderer.Color.YELLOW;
            const fps_text = try std.fmt.allocPrint(self.allocator, "FPS: {d:.1}/{d}", .{ stats.actual_fps, target_fps });
            defer self.allocator.free(fps_text);
            const fps_display = components.Text.initWithStyle(fps_text, area.x + 1, y, renderer.TextStyle{ .fg_color = fps_color });
            try fps_display.render(&self.renderer);
            y += 1;

            // Connection status with indicator
            const conn_indicator = if (stats.connection_status) "●" else "●";
            const conn_status = if (stats.connection_status) "Connected" else "Disconnected";
            const conn_color = if (stats.connection_status) renderer.Color.GREEN else renderer.Color.RED;
            const conn_text = try std.fmt.allocPrint(self.allocator, "{s} IPC: {s}", .{ conn_indicator, conn_status });
            defer self.allocator.free(conn_text);
            const conn_display = components.Text.initWithStyle(conn_text, area.x + 1, y, renderer.TextStyle{ .fg_color = conn_color });
            try conn_display.render(&self.renderer);
            y += 1;

            // Performance indicator
            const perf_text = if (stats.actual_fps > @as(f32, @floatFromInt(target_fps)) * 0.9)
                "Performance: Good"
            else
                "Performance: Slow";
            const perf_color = if (stats.actual_fps > @as(f32, @floatFromInt(target_fps)) * 0.9)
                renderer.Color.GREEN
            else
                renderer.Color.YELLOW;
            const perf_display = components.Text.initWithStyle(perf_text, area.x + 1, y, renderer.TextStyle{ .fg_color = perf_color });
            try perf_display.render(&self.renderer);
        } else if (status == .err) {
            const error_text = "Connection failed";
            const error_display = components.Text.initWithStyle(error_text, area.x + 1, y, renderer.TextStyle{ .fg_color = renderer.Color.RED });
            try error_display.render(&self.renderer);
            y += 1;

            const help_text = "Check Hyprland status";
            const help_display = components.Text.initWithStyle(help_text, area.x + 1, y, renderer.TextStyle{ .fg_color = renderer.Color.YELLOW });
            try help_display.render(&self.renderer);
        } else {
            const help_text = "Press F2 to start preview";
            const help_display = components.Text.initWithStyle(help_text, area.x + 1, y, renderer.TextStyle{ .fg_color = renderer.Color.CYAN });
            try help_display.render(&self.renderer);
            y += 1;

            const info_text = "Live border animation";
            const info_display = components.Text.init(info_text, area.x + 1, y);
            try info_display.render(&self.renderer);
        }
    }

    fn renderPresetsPanel(self: *TUIApp, area: @import("components/panel.zig").ContentArea) !void {
        const placeholder_text = components.Text.init("Preset management", area.x + 1, area.y + 1);
        try placeholder_text.render(&self.renderer);

        const help_text = components.Text.init("(Coming soon)", area.x + 1, area.y + 2);
        try help_text.render(&self.renderer);
    }

    fn renderSystemStatusPanel(self: *TUIApp, area: @import("components/panel.zig").ContentArea) !void {
        var y = area.y + 1;

        // Test Hyprland connection
        const connection_ok = self.preview_manager.stats.connection_status or
            @import("utils").hyprland.testConnection(self.preview_manager.socket_path);

        const hypr_status = if (connection_ok) "Connected" else "Disconnected";
        const hypr_color = if (connection_ok) renderer.Color.GREEN else renderer.Color.RED;
        const hypr_text = try std.fmt.allocPrint(self.allocator, "Hyprland: {s}", .{hypr_status});
        defer self.allocator.free(hypr_text);
        const hypr_display = components.Text.initWithStyle(hypr_text, area.x + 1, y, renderer.TextStyle{ .fg_color = hypr_color });
        try hypr_display.render(&self.renderer);
        y += 1;

        // Socket path info
        const socket_text = "Socket: Available";
        const socket_display = components.Text.initWithStyle(socket_text, area.x + 1, y, renderer.TextStyle{ .fg_color = renderer.Color.GREEN });
        try socket_display.render(&self.renderer);
        y += 1;

        // Environment status
        const env_text = "Environment: OK";
        const env_display = components.Text.initWithStyle(env_text, area.x + 1, y, renderer.TextStyle{ .fg_color = renderer.Color.GREEN });
        try env_display.render(&self.renderer);
    }

    fn renderHelpScreen(self: *TUIApp) !void {
        const terminal_size = self.renderer.getTerminalSize();

        // Help panel
        const help_panel = components.Panel.init("Help", 5, 3, terminal_size.width - 10, terminal_size.height - 8);
        try help_panel.render(&self.renderer);

        // Help content
        const help_content = [_][]const u8{
            "HyprIngMyBorder Configuration Help",
            "",
            "Navigation:",
            "  Tab       - Switch between panels",
            "  Enter     - Select/activate item",
            "  Esc       - Exit application",
            "  F1        - Toggle this help screen",
            "  F2        - Start/Stop live preview",
            "",
            "Panels:",
            "  Animation Settings - Configure border animations",
            "  Live Preview      - See changes in real-time",
            "  Presets          - Manage saved configurations",
            "  System Status    - View system information",
            "",
            "Live Preview:",
            "  Shows real-time border animation status",
            "  Displays connection status to Hyprland",
            "  Shows actual FPS and frame statistics",
            "",
            "Press any key to return to main screen...",
        };

        const content_area = help_panel.getContentArea();
        for (help_content, 0..) |line, i| {
            if (i >= content_area.height) break;

            const text = components.Text.init(line, content_area.x + 2, content_area.y + @as(u16, @intCast(i)));
            try text.render(&self.renderer);
        }
    }

    fn handleInput(self: *TUIApp) !void {
        const event = try self.event_handler.waitForKeypress();

        switch (event) {
            .key => |key_event| {
                switch (self.current_screen) {
                    .main => try self.handleMainScreenInput(key_event),
                    .help => try self.handleHelpScreenInput(key_event),
                }
            },
        }
    }

    fn handleMainScreenInput(self: *TUIApp, key_event: events.KeyEvent) !void {
        switch (key_event.key) {
            .escape => {
                self.should_exit = true;
            },
            .f1 => {
                self.current_screen = Screen.help;
            },
            .f2 => {
                // Add debug logging to see if F2 is detected
                std.log.info("F2 key detected, toggling preview", .{});
                self.togglePreview() catch |err| {
                    // Don't exit on preview errors, just log them
                    std.log.err("Preview toggle failed: {}", .{err});
                };
            },
            .tab => {
                try self.switchFocus();
            },
            .enter => {
                // TODO: Handle panel-specific actions
            },
            .char => {
                if (key_event.char) |c| {
                    switch (c) {
                        'q', 'Q' => self.should_exit = true,
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    fn togglePreview(self: *TUIApp) !void {
        if (self.preview_manager.isRunning()) {
            self.preview_manager.stop();
        } else {
            // Update preview manager with current config before starting
            try self.preview_manager.updateConfig(self.current_config);
            try self.preview_manager.start();
        }
    }

    fn handleHelpScreenInput(self: *TUIApp, key_event: events.KeyEvent) !void {
        // Any key returns to main screen
        _ = key_event;
        self.current_screen = Screen.main;
    }

    fn switchFocus(self: *TUIApp) !void {
        // Find currently focused panel
        var current_focus: ?usize = null;
        for (&self.main_panels, 0..) |*panel, i| {
            if (panel.focused) {
                panel.setFocus(false);
                current_focus = i;
                break;
            }
        }

        // Move to next panel
        const next_focus = if (current_focus) |focus|
            (focus + 1) % self.main_panels.len
        else
            0;

        self.main_panels[next_focus].setFocus(true);
    }

    pub fn deinit(self: *TUIApp) void {
        // Stop preview before cleanup
        self.preview_manager.stop();
        self.preview_manager.deinit();

        // Clean up configuration
        self.current_config.deinit(self.allocator);

        self.renderer.deinit();
        self.event_handler.deinit();
    }
};
