const std = @import("std");
const sdl3 = @import("sdl3");
const Emulator = @import("zhip-8").Emulator;

const fps = 60;
const width = 640;
const height = 320;

pub fn main() !void {
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

    var quit = false;
    while (!quit) {
        const dt = fps_cap.delay();
        _ = dt;

        emu.emulate();

        try renderer.setDrawColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        try renderer.clear();

        try renderer.setDrawColorFloat(.{ .r = 255, .g = 255, .b = 255, .a = 255 });
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

        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit => quit = true,
                .terminating => quit = true,
                .key_down => |key| {
                    std.debug.print("Scancode: {d}\n", .{key.scancode.?});
                },
                else => {},
            }
        }
    }
}
