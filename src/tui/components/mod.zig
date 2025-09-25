//! TUI Components module
//! Provides reusable UI components for the Terminal User Interface

pub const Panel = @import("panel.zig").Panel;
pub const Text = @import("text.zig").Text;

// Re-export common types
pub const Component = union(enum) {
    panel: Panel,
    text: Text,
};
