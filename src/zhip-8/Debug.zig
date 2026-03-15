const std = @import("std");
const CPU = @import("CPU.zig");
const sdl3 = @import("sdl3");
const Debug = @This();

const State = enum { step, run, pause };

fps_cap: sdl3.extras.FramerateCapper(f32),
window: sdl3.video.Window,
renderer: sdl3.render.Renderer,
font: sdl3.ttf.Font,
text_engine: sdl3.ttf.RendererTextEngine,
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
        .font = try sdl3.ttf.Font.init("font/JetBrainsMono-Bold.ttf", 20.0),
        .text_engine = try sdl3.ttf.RendererTextEngine.init(renderer),
        .renderer = renderer,
        .emu = CPU.init(),
    };
}

pub fn deinit(self: *Debug) void {
    self.window.deinit();
    self.renderer.deinit();
    self.font.deinit();
    self.text_engine.deinit();
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

const key_tag = [16]u8{
    '1', '2', '3', '4',
    'q', 'w', 'e', 'r',
    'a', 's', 'd', 'f',
    'z', 'x', 'c', 'v',
};

fn drawKeys(self: *const Debug) !void {
    var buf: [4]u8 = undefined;
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

        const x: f32 = magic_x + col * (size + pad);
        const y: f32 = magic_y + row * (size + pad);

        try self.renderer.renderFillRect(.{
            .x = x,
            .y = y,
            .w = size,
            .h = size,
        });

        const label: []const u8 = try std.fmt.bufPrint(
            &buf,
            "{c}",
            .{key_tag[i]},
        );
        const text = try sdl3.ttf.Text.init(.{ .value = self.text_engine.value }, self.font, label);
        try sdl3.ttf.drawRendererText(text, x, y);
    }
}

const commands = [_]struct { label: []const u8, key: []const u8 }{
    .{ .label = "Step", .key = "N" },
    .{ .label = "Run", .key = "Space" },
    .{ .label = "Pause", .key = "P" },
    .{ .label = "Reset", .key = "K" },
};

fn drawCommands(self: *Debug) !void {
    const panel_x: f32 = 660;
    const panel_y: f32 = 20;
    const panel_w: f32 = 220;
    const line_h: f32 = 30;
    const pad: f32 = 10;
    const panel_h: f32 = pad * 2 + commands.len * line_h;

    try self.renderer.setDrawColor(.{ .r = 30, .g = 30, .b = 30, .a = 255 });
    try self.renderer.renderFillRect(
        .{ .x = panel_x, .y = panel_y, .w = panel_w, .h = panel_h },
    );

    var buf: [32]u8 = undefined;
    for (commands, 0..) |cmd, i| {
        const label = try std.fmt.bufPrint(
            &buf,
            "{s}: {s}",
            .{ cmd.label, cmd.key },
        );
        const text = try sdl3.ttf.Text.init(
            .{ .value = self.text_engine.value },
            self.font,
            label,
        );
        const y: f32 = panel_y + pad + @as(f32, @floatFromInt(i)) * line_h;
        try sdl3.ttf.drawRendererText(text, panel_x + pad, y);
    }
}

fn reset(self: *Debug) void {
    self.emu.pc = 0x200;
    self.emu.I = 0;
    self.emu.sp = 0;
    @memset(&self.emu.V, 0);
    @memset(&self.emu.display, 0);
    @memset(&self.emu.keys, 0);
    @memset(&self.emu.stack, 0);
    self.emu.dt = 0;
    self.emu.st = 0;
}

pub fn mainLoop(self: *Debug) !void {
    var quit = false;
    var state: State = .pause;
    while (!quit) {
        const dt = self.fps_cap.delay();
        _ = dt;

        switch (state) {
            .step => {
                for (0..10) |i| {
                    _ = i;
                    self.emu.emulate();
                }
                state = .pause;
            },
            .run => {
                for (0..10) |i| {
                    _ = i;
                    self.emu.emulate();
                }
            },
            .pause => {},
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
        try self.drawKeys();

        try self.drawCommands();

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
                        state = .step;
                    }
                    if (key.scancode.? == .space) {
                        state = .run;
                    }
                    if (key.scancode.? == .p) {
                        state = .pause;
                        break;
                    }
                    if (key.scancode.? == .k) {
                        self.reset();
                        state = .pause;
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
