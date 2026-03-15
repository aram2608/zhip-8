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

// Global config struct to store frequently used colors
const C = struct {
    const bg = sdl3.pixels.Color{ .r = 13, .g = 14, .b = 20, .a = 255 };
    const panel = sdl3.pixels.Color{ .r = 22, .g = 23, .b = 32, .a = 255 };
    const border = sdl3.pixels.Color{ .r = 55, .g = 56, .b = 78, .a = 255 };
    const header = sdl3.pixels.Color{ .r = 33, .g = 34, .b = 50, .a = 255 };
    const key_off = sdl3.pixels.Color{ .r = 30, .g = 32, .b = 46, .a = 255 };
    const key_on = sdl3.pixels.Color{ .r = 55, .g = 130, .b = 255, .a = 255 };
    const pix_on = sdl3.pixels.Color{ .r = 72, .g = 220, .b = 120, .a = 255 };
    const pix_bg = sdl3.pixels.Color{ .r = 10, .g = 20, .b = 15, .a = 255 };
};

// Global constants for formatting widgets
const HEADER_H: f32 = 26;
const PIXEL_SZ: f32 = 10;

const DISP_X: f32 = 8;
const DISP_Y: f32 = 8;
const DISP_W: f32 = 64 * PIXEL_SZ + 8; // 648
const DISP_H: f32 = HEADER_H + 4 + 32 * PIXEL_SZ + 4; // 354
const DISP_IX: f32 = DISP_X + 4; // inner pixel origin x
const DISP_IY: f32 = DISP_Y + HEADER_H + 4; // inner pixel origin y

const KEY_SZ: f32 = 54;
const KEY_GAP: f32 = 5;
const KEY_PAD: f32 = 10;
const KEYS_X: f32 = DISP_X;
const KEYS_Y: f32 = DISP_Y + DISP_H + 8; // 370
const KEYS_W: f32 = KEY_PAD * 2 + 4 * KEY_SZ + 3 * KEY_GAP; // 251
const KEYS_H: f32 = HEADER_H + KEY_PAD + 4 * KEY_SZ + 3 * KEY_GAP + KEY_PAD; // 277

const CTRL_X: f32 = DISP_X + DISP_W + 8; // 664
const CTRL_Y: f32 = DISP_Y;
const CTRL_W: f32 = 280;
const CTRL_LINE: f32 = 28;
const CTRL_PAD: f32 = 10;
const CTRL_H: f32 = HEADER_H + CTRL_PAD + 4 * CTRL_LINE + CTRL_PAD; // 158

pub fn init() !Debug {
    const window, const renderer = try sdl3.render.Renderer.initWithWindow(
        "zhip-8",
        1200,
        760,
        .{},
    );
    return .{
        .fps_cap = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = 60 } },
        .window = window,
        .font = try sdl3.ttf.Font.init("font/JetBrainsMono-Bold.ttf", 16.0),
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

fn drawPanel(self: *const Debug, x: f32, y: f32, w: f32, h: f32, title: []const u8) !void {
    // Outer border (1px frame)
    try self.renderer.setDrawColor(C.border);
    try self.renderer.renderFillRect(.{ .x = x, .y = y, .w = w, .h = h });
    // Header strip
    try self.renderer.setDrawColor(C.header);
    try self.renderer.renderFillRect(.{ .x = x + 1, .y = y + 1, .w = w - 2, .h = HEADER_H - 1 });
    // Header / body separator line
    try self.renderer.setDrawColor(C.border);
    try self.renderer.renderFillRect(.{ .x = x + 1, .y = y + HEADER_H, .w = w - 2, .h = 1 });
    // Body fill
    try self.renderer.setDrawColor(C.panel);
    try self.renderer.renderFillRect(.{ .x = x + 1, .y = y + HEADER_H + 1, .w = w - 2, .h = h - HEADER_H - 2 });
    // Title text
    const text = try sdl3.ttf.Text.init(.{ .value = self.text_engine.value }, self.font, title);
    try sdl3.ttf.drawRendererText(text, x + 8, y + 4);
}

const key_order = [16]usize{
    0x1, 0x2, 0x3, 0xC,
    0x4, 0x5, 0x6, 0xD,
    0x7, 0x8, 0x9, 0xE,
    0xA, 0x0, 0xB, 0xF,
};

const key_tag = [16]u8{
    '1', '2', '3', '4',
    'q', 'w', 'e', 'r',
    'a', 's', 'd', 'f',
    'z', 'x', 'c', 'v',
};

fn drawKeys(self: *const Debug) !void {
    try self.drawPanel(KEYS_X, KEYS_Y, KEYS_W, KEYS_H, "KEYPAD");

    var buf: [4]u8 = undefined;
    for (key_order, 0..) |key, i| {
        const col: f32 = @floatFromInt(i % 4);
        const row: f32 = @floatFromInt(i / 4);
        const kx = KEYS_X + KEY_PAD + col * (KEY_SZ + KEY_GAP);
        const ky = KEYS_Y + HEADER_H + 1 + KEY_PAD + row * (KEY_SZ + KEY_GAP);

        // Key border
        try self.renderer.setDrawColor(C.border);
        try self.renderer.renderFillRect(
            .{ .x = kx - 1, .y = ky - 1, .w = KEY_SZ + 2, .h = KEY_SZ + 2 },
        );

        // Key fill
        if (self.emu.keys[key] == 1) {
            try self.renderer.setDrawColor(C.key_on);
        } else {
            try self.renderer.setDrawColor(C.key_off);
        }
        try self.renderer.renderFillRect(.{ .x = kx, .y = ky, .w = KEY_SZ, .h = KEY_SZ });

        // Centered label
        const label = try std.fmt.bufPrint(&buf, "{c}", .{key_tag[i]});
        const text = try sdl3.ttf.Text.init(
            .{ .value = self.text_engine.value },
            self.font,
            label,
        );
        try sdl3.ttf.drawRendererText(text, kx + 22, ky + 17);
    }
}

const commands = [_]struct { label: []const u8, key: []const u8 }{
    .{ .label = "Step", .key = "N" },
    .{ .label = "Run", .key = "Space" },
    .{ .label = "Pause", .key = "P" },
    .{ .label = "Reset", .key = "K" },
};

fn drawCommands(self: *const Debug) !void {
    try self.drawPanel(CTRL_X, CTRL_Y, CTRL_W, CTRL_H, "CONTROLS");

    for (commands, 0..) |cmd, i| {
        const y = CTRL_Y + HEADER_H + 1 + CTRL_PAD + @as(f32, @floatFromInt(i)) * CTRL_LINE;

        const key_text = try sdl3.ttf.Text.init(.{ .value = self.text_engine.value }, self.font, cmd.key);
        try sdl3.ttf.drawRendererText(key_text, CTRL_X + CTRL_PAD, y);

        const lbl_text = try sdl3.ttf.Text.init(.{ .value = self.text_engine.value }, self.font, cmd.label);
        try sdl3.ttf.drawRendererText(lbl_text, CTRL_X + CTRL_PAD + 90, y);
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
                self.emu.emulate();
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

        // Background
        try self.renderer.setDrawColor(C.bg);
        try self.renderer.clear();

        // Display panel frame
        try self.drawPanel(DISP_X, DISP_Y, DISP_W, DISP_H, "CHIP-8");

        // Dark scanline background for the pixel grid
        try self.renderer.setDrawColor(C.pix_bg);
        try self.renderer.renderFillRect(.{
            .x = DISP_IX,
            .y = DISP_IY,
            .w = 64 * PIXEL_SZ,
            .h = 32 * PIXEL_SZ,
        });

        // Lit pixels (9x9 with 1px gap — LED matrix effect)
        try self.renderer.setDrawColor(C.pix_on);
        for (0..32) |row| {
            for (0..64) |col| {
                if (self.emu.display[row * 64 + col] == 1) {
                    try self.renderer.renderFillRect(.{
                        .x = DISP_IX + @as(f32, @floatFromInt(col)) * PIXEL_SZ,
                        .y = DISP_IY + @as(f32, @floatFromInt(row)) * PIXEL_SZ,
                        .w = PIXEL_SZ - 1,
                        .h = PIXEL_SZ - 1,
                    });
                }
            }
        }

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
                    if (key.scancode.? == .n) state = .step;
                    if (key.scancode.? == .space) state = .run;
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
