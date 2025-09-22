const std = @import("std");

// --- HSV → RGB helper ---
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

fn fmtColor(allocator: std.mem.Allocator, rgb: [3]u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "0xff{X:0>2}{X:0>2}{X:0>2}", .{
        rgb[0], rgb[1], rgb[2],
    });
}

fn getSocketPath(allocator: std.mem.Allocator) ![]u8 {
    const runtime = try std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR");
    defer allocator.free(runtime);

    const his = try std.process.getEnvVarOwned(allocator, "HYPRLAND_INSTANCE_SIGNATURE");
    defer allocator.free(his);

    return std.fmt.allocPrint(allocator, "{s}/hypr/{s}/.socket.sock", .{ runtime, his });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const socket_path = try getSocketPath(allocator);
    defer allocator.free(socket_path);

    var hue: f64 = 0.0;
    const step: f64 = 0.01; // speed of hue shift
    const interval_ms: u64 = 100; // ~10fps (set to 16 for ~60fps)

    while (true) {
        // rainbow colors (2 stops, opposite ends)
        const rgb1 = hsvToRgb(hue, 1.0, 1.0);
        const rgb2 = hsvToRgb(@mod(hue + 0.5, 1.0), 1.0, 1.0);

        const c1 = try fmtColor(allocator, rgb1);
        defer allocator.free(c1);
        const c2 = try fmtColor(allocator, rgb2);
        defer allocator.free(c2);

        const cmd = try std.fmt.allocPrint(
            allocator,
            "keyword general:col.active_border {s} {s} 270deg\n",
            .{ c1, c2 },
        );
        defer allocator.free(cmd);

        var sock = try std.net.connectUnixSocket(socket_path);
        defer sock.close();
        _ = try sock.writeAll(cmd);

        hue = @mod(hue + step, 1.0);
        std.Thread.sleep(std.time.ns_per_ms * interval_ms);
    }
}
