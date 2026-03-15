const std = @import("std");
const CPU = @import("CPU.zig");
const sdl3 = @import("sdl3");
const Debug = @This();

fps_cap: sdl3.extras.FramerateCapper(f32),
window: sdl3.video.Window,
renderer: sdl3.render.Renderer,
emu: CPU,

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

const key_order = [16]usize{
    0x1, 0x2, 0x3, 0xC, // 1 2 3 4
    0x4, 0x5, 0x6, 0xD, // q w e r
    0x7, 0x8, 0x9, 0xE, // a s d f
    0xA, 0x0, 0xB, 0xF, // z x c v
};

pub fn drawKeys(self: *const Debug) !void {
    const magic_x: f32 = 20;
    const magic_y: f32 = 320;
    const size: f32 = 60;
    const pad: f32 = 4;

    for (key_order, 0..) |key, i| {
        const col: f32 = @floatFromInt(i % 4);
        const row: f32 = @floatFromInt(i / 4);

        if (self.emu.keys[key] == 1) {
            try self.renderer.setDrawColor(
                .{ .r = 255, .b = 0, .g = 0, .a = 255 },
            );
        } else {
            try self.renderer.setDrawColor(
                .{ .r = 0, .b = 255, .g = 0, .a = 255 },
            );
        }

        try self.renderer.renderFillRect(.{
            .x = magic_x + col * (size + pad),
            .y = magic_y + row * (size + pad),
            .w = size,
            .h = size,
        });
    }
}

pub fn mainLoop(self: *Debug) !void {
    var quit = false;
    var step = false;
    while (!quit) {
        const dt = self.fps_cap.delay();
        _ = dt;

        if (step) {
            for (0..10) |i| {
                _ = i;
                self.emu.emulate();
            }
        }
        step = false;

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
        try self.drawKeys();

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
                    if (key.scancode.? == .n) {
                        step = true;
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
        .one => 0x1,
        .two => 0x2,
        .three => 0x3,
        .four => 0xC,
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
