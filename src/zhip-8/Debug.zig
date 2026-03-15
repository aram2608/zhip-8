const std = @import("std");
const CPU = @import("CPU.zig");
const sdl3 = @import("sdl3");
const Debug = @This();

fps_cap: sdl3.extras.FramerateCapper(f32),
window: sdl3.video.Window,
renderer: sdl3.render.Renderer,
emu: CPU,

const keypads = [_]sdl3.rect.Rect(f32){
    .{ .x = 10, .y = 320, .w = 50, .h = 50 },
};

pub fn init() !Debug {
    const window, const renderer = try sdl3.render.Renderer.initWithWindow(
        "zhip-8",
        1200,
        800,
        .{},
    );
    return .{
        .fps_cap = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = 60 } },
        .window = window,
        .renderer = renderer,
        .emu = CPU.init(),
    };
}

pub fn deinit(self: *Debug) void {
    self.window.deinit();
    self.renderer.deinit();
}

pub fn loadRom(self: *Debug, path: []const u8) !void {
    try self.emu.loadRom(path);
}

pub fn mainLoop(self: *Debug) !void {
    var quit = false;
    while (!quit) {
        const dt = self.fps_cap.delay();
        _ = dt;

        for (0..10) |i| {
            _ = i;
            self.emu.emulate();
        }

        if (self.emu.dt > 0) self.emu.dt -= 1;
        if (self.emu.st > 0) self.emu.st -= 1;

        try self.renderer.setDrawColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        try self.renderer.clear();

        try self.renderer.setDrawColor(.{ .r = 255, .g = 255, .b = 255, .a = 255 });
        for (0..32) |row| {
            for (0..64) |col| {
                if (self.emu.display[row * 64 + col] == 1) {
                    try self.renderer.renderFillRect(.{
                        .x = @floatFromInt(col * 10),
                        .y = @floatFromInt(row * 10),
                        .h = 10,
                        .w = 10,
                    });
                }
            }
        }

        try self.renderer.setDrawColor(.{ .r = 0, .g = 0, .b = 255, .a = 255 });
        try self.renderer.renderRects(&keypads);

        try self.renderer.present();

        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit => quit = true,
                .terminating => quit = true,
                .key_down => |key| {
                    if (key.scancode.? == .escape) {
                        quit = true;
                        break;
                    }
                    if (scancodeToChip8(key.scancode.?)) |chip_key| {
                        self.emu.keys[chip_key] = 1;
                    }
                },
                .key_up => |key| {
                    if (scancodeToChip8(key.scancode.?)) |chip_key| {
                        self.emu.keys[chip_key] = 0;
                    }
                },
                else => {},
            }
        }
    }
}

fn scancodeToChip8(scancode: sdl3.Scancode) ?u8 {
    return switch (scancode) {
        .kp_1 => 0x1,
        .kp_2 => 0x2,
        .kp_3 => 0x3,
        .kp_4 => 0xC,
        .q => 0x4,
        .w => 0x5,
        .e => 0x6,
        .r => 0xD,
        .a => 0x7,
        .s => 0x8,
        .d => 0x9,
        .f => 0xE,
        .z => 0xA,
        .x => 0x0,
        .c => 0xB,
        .v => 0xF,
        else => null,
    };
}
