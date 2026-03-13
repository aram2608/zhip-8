const std = @import("std");
const sdl3 = @import("sdl3");

const fps = 60;
const width = 640;
const height = 320;

pub fn main() !void {
    defer sdl3.shutdown();

    const init_flags = sdl3.InitFlags{ .video = true };
    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);

    const window = try sdl3.video.Window.init("zhip-8", width, height, .{});
    defer window.deinit();

    var fps_cap = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = fps } };

    var quit = false;
    while (!quit) {
        const dt = fps_cap.delay();
        _ = dt;

        const surface = try window.getSurface();
        try surface.fillRect(null, surface.mapRgb(0, 0, 0));
        try window.updateSurface();

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
