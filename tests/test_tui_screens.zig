//! Tests for TUI screens
//! Tests for animation settings and preset management panels

const std = @import("std");
const testing = std.testing;
const tui = @import("tui");
const config = @import("config");

test "AnimationSettingsPanel basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var panel = try tui.screens.AnimationSettingsPanel.init(allocator, 0, 0, 60, 30);
    defer panel.deinit();

    // Test initial state
    const initial_config = panel.getAnimationConfig();
    try testing.expect(initial_config.fps > 0);
    try testing.expect(initial_config.speed > 0.0);

    // Test setting configuration
    var new_config = config.AnimationConfig.default();
    new_config.animation_type = config.AnimationType.pulse;
    new_config.fps = 30;
    new_config.speed = 0.5;

    try panel.setAnimationConfig(new_config);
    const updated_config = panel.getAnimationConfig();
    try testing.expect(updated_config.animation_type == config.AnimationType.pulse);
    try testing.expect(updated_config.fps == 30);
    try testing.expect(updated_config.speed == 0.5);

    // Test visibility
    panel.setVisible(false);
    try testing.expect(!panel.visible);

    panel.setVisible(true);
    try testing.expect(panel.visible);
}

test "PresetManagementPanel basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var panel = try tui.screens.PresetManagementPanel.init(allocator, 0, 0, 50, 25);
    defer panel.deinit();

    // Test initial state
    try testing.expect(panel.visible);
    try testing.expect(panel.getSelectedPresetName() == null);

    // Test visibility
    panel.setVisible(false);
    try testing.expect(!panel.visible);

    panel.setVisible(true);
    try testing.expect(panel.visible);

    // Test current preset setting
    try panel.setCurrentPreset("test_preset");
    // Note: This would normally update the display, but we can't easily test that without a full preset system
}

test "TUI screens integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test that both screens can be created and work together
    var animation_panel = try tui.screens.AnimationSettingsPanel.init(allocator, 0, 0, 60, 30);
    defer animation_panel.deinit();

    var preset_panel = try tui.screens.PresetManagementPanel.init(allocator, 65, 0, 50, 25);
    defer preset_panel.deinit();

    // Test positioning
    animation_panel.setPosition(10, 5);
    preset_panel.setPosition(75, 5);

    // Both should be visible and functional
    try testing.expect(animation_panel.visible);
    try testing.expect(preset_panel.visible);

    // Test that they can be updated independently
    animation_panel.update(1000); // 1 second
    // Preset panel doesn't have an update method, which is fine

    // Test configuration sharing (conceptually)
    const config_from_animation = animation_panel.getAnimationConfig();
    try testing.expect(config_from_animation.fps > 0);
}
