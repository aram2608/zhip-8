const std = @import("std");
const sdl3 = @import("sdl3");
const Emulator = @import("zhip-8").Emulator;
const chizel = @import("chizel");

const Opts = struct {
    file_path: []const u8 = "",

    pub fn validate_file_path(value: []const u8) !void {
        if (value.len == 0) return error.RomFileRequired;
    }

    pub const shorts = .{ .file_path = 'f' };
    pub const help = .{ .file_path = "Path to ROM file" };
    pub const config = .{ .env_prefix = "ZHIP8_" };
};

const fps = 60;
const width = 640;
const height = 320;

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

pub fn main() !void {
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();
    const arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var parser = chizel.Chip(Opts).init(&args, arena);
    defer parser.deinit();

    const result = try parser.parse();

    if (result.had_help) {
        const out = try result.printHelp(std.heap.page_allocator);
        defer std.heap.page_allocator.free(out);
        std.debug.print("{s}\n", .{out});
        return;
    }

    defer sdl3.shutdown();

    const init_flags = sdl3.InitFlags{ .video = true };
    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);

    const window, const renderer = try sdl3.render.Renderer.initWithWindow(
        "zhip-8",
        width,
        height,
        .{},
    );
    defer window.deinit();
    defer renderer.deinit();

    var fps_cap = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = fps } };

    var emu = Emulator.init();

    try emu.loadRom(result.opts.file_path);

    var quit = false;
    while (!quit) {
        const dt = fps_cap.delay();
        _ = dt;

        for (0..10) |i| {
            _ = i;
            emu.emulate();
        }

        if (emu.dt > 0) emu.dt -= 1;
        if (emu.st > 0) emu.st -= 1;

        try renderer.setDrawColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        try renderer.clear();

        try renderer.setDrawColor(.{ .r = 255, .g = 255, .b = 255, .a = 255 });
        for (0..32) |row| {
            for (0..64) |col| {
                if (emu.display[row * 64 + col] == 1) {
                    try renderer.renderFillRect(.{
                        .x = @floatFromInt(col * 10),
                        .y = @floatFromInt(row * 10),
                        .h = 10,
                        .w = 10,
                    });
                }
            }
        }

        try renderer.present();

        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit => quit = true,
                .terminating => quit = true,
                .key_down => |key| {
                    if (scancodeToChip8(key.scancode.?)) |chip_key| {
                        emu.keys[chip_key] = 1;
                    }
                },
                .key_up => |key| {
                    if (scancodeToChip8(key.scancode.?)) |chip_key| {
                        emu.keys[chip_key] = 0;
                    }
                },
                else => {},
            }
        }
    }
}
