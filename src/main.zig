const std = @import("std");
const sdl3 = @import("sdl3");
// TODO: Make a debug console
// we can create a Cmd with chizel to fire the ROM
// in standard run mode or debug mode with some nice features
const Debug = @import("zhip-8").Debug;
const Emulator = @import("zhip-8").Emulator;
const chizel = @import("chizel");

const Cmds = union(enum) {
    debug: struct {
        file_path: []const u8 = "",

        pub fn validate_file_path(value: []const u8) !void {
            if (value.len == 0) return error.RomFileRequired;
        }

        pub const shorts = .{ .file_path = 'f' };
        pub const help = .{ .file_path = "Path to ROM file" };
    },
    emulate: struct {
        file_path: []const u8 = "",

        pub fn validate_file_path(value: []const u8) !void {
            if (value.len == 0) return error.RomFileRequired;
        }

        pub const shorts = .{ .file_path = 'f' };
        pub const help = .{ .file_path = "Path to ROM file" };
    },
    pub const help = .{
        .emulate = "Emulate in a 640x320 pixel window",
        .debug = "Load a rich debug window for the emulator",
    };
    pub const config = .{ .env_prefix = "ZHIP8_" };
};

pub fn main() !void {
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();
    const arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var parser = chizel.Chizel(Cmds).init(&args, arena);
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

    try sdl3.ttf.init();
    defer sdl3.ttf.quit();

    const opts = result.opts;
    switch (opts) {
        .debug => |d| {
            var debug = try Debug.init();
            defer debug.deinit();
            try debug.loadRom(d.file_path);
            try debug.mainLoop();
        },
        .emulate => |e| {
            var emu = try Emulator.init();
            defer emu.deinit();
            try emu.loadRom(e.file_path);
            try emu.mainLoop();
        },
    }
}
