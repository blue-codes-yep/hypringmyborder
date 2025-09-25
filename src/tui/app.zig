//! Main TUI Application
//! Manages the overall Terminal User Interface state and screen management

const std = @import("std");
const renderer = @import("renderer.zig");
const events = @import("events.zig");
const components = @import("components/mod.zig");

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

    // Main screen components
    main_panels: [4]components.Panel,
    status_text: components.Text,
    help_text: components.Text,

    pub fn init(allocator: std.mem.Allocator) !TUIApp {
        const r = try renderer.Renderer.init(allocator);
        const event_handler = try events.SimpleEventHandler.init();

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

        const status_text = components.Text.initWithStyle("[Tab] Switch Panel  [Enter] Select  [Esc] Exit  [F1] Help", 2, terminal_size.height - 2, renderer.TextStyle{ .fg_color = renderer.Color.CYAN });

        const help_text = components.Text.initWithStyle("HyprIngMyBorder Configuration - Press F1 for help", 2, 1, renderer.TextStyle{ .fg_color = renderer.Color.YELLOW, .bold = true });

        return TUIApp{
            .allocator = allocator,
            .renderer = r,
            .event_handler = event_handler,
            .current_screen = Screen.main,
            .should_exit = false,
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
        for (&self.main_panels) |*panel| {
            try panel.render(&self.renderer);

            // Add some placeholder content to show the panels are working
            const content_area = panel.getContentArea();
            if (content_area.width > 0 and content_area.height > 0) {
                const placeholder_text = components.Text.init("Content here...", content_area.x + 1, content_area.y + 1);
                try placeholder_text.render(&self.renderer);
            }
        }

        // Render status bar
        try self.status_text.render(&self.renderer);
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
            "",
            "Panels:",
            "  Animation Settings - Configure border animations",
            "  Live Preview      - See changes in real-time",
            "  Presets          - Manage saved configurations",
            "  System Status    - View system information",
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
        self.renderer.deinit();
        self.event_handler.deinit();
    }
};
