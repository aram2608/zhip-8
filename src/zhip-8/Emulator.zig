const std = @import("std");
const Emulator = @This();

// Memory: 4 kilobytes, about 4096 bytes
// Display: 64 x 32, about 640 and 320
// Program counter: points at current instruction
// Index register: I, points somewhere in the memory
// Stack for 16-bit addresses
// Delay timer: 8-bit timer, basically fps 60 hz, so 60 times/sec
// Sound timer: 8-bit timer for sounds
// 16 8-bit (1 byte) registers for variables, 0 through F in hexadecimal

font: [16 * 5]u8 = .{
    0xF0, 0x90, 0x90, 0x90, 0xF0, //0
    0x20, 0x60, 0x20, 0x20, 0x70, //1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, //2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, //3
    0x90, 0x90, 0xF0, 0x10, 0x10, //4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, //5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, //6
    0xF0, 0x10, 0x20, 0x40, 0x40, //7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, //8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, //9
    0xF0, 0x90, 0xF0, 0x90, 0x90, //A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, //B
    0xF0, 0x80, 0x80, 0x80, 0xF0, //C
    0xE0, 0x90, 0x90, 0x90, 0xE0, //D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, //E
    0xF0, 0x80, 0xF0, 0x80, 0x80, //F
},
// Available RAM for emulator
memory: [4096]u8,
// Variable register V0 to VF
V: [16]u8,
// Delay timer
dt: u8,
// Sound timer
st: u8,

// Program counter
pc: u16 = 0x200,
// Subroutine stack
stack: [16]u16,
// Stack pointer
sp: u16,
// Register index
I: u16,
display: [64 * 32]u1,

pub fn init() Emulator {
    return .{
        .pc = 0x200,
        .sp = 0,
        .dt = 0,
        .st = 0,
        .I = 0,
        .V = std.mem.zeroes([16]u8),
        .memory = std.mem.zeroes([4096]u8),
        .stack = std.mem.zeroes([16]u16),
        .display = std.mem.zeroes([64 * 32]u1),
    };
}

/// Opcodes are 2 bytes so we extract the op then advance.
fn getOpcode(self: *Emulator) u16 {
    const op: u16 = @as(u16, self.memory[self.pc]) << 8 | self.memory[self.pc + 1];
    self.pc += 2;
    return op;
}

pub fn emulate(self: *Emulator) void {
    const op = self.getOpcode();

    const nibble = (op & 0xF000) >> 12; // Instruction type
    const x = (op & 0x0F00) >> 8; // Register index Vx
    const y = (op & 0x00F0) >> 4; // Register index Vy
    const n = op & 0x000F; // 4 bit nibble [rightside]
    const kk = op & 0x00FF; // byte [low byte]
    const nnn = op & 0x0FFF; // 12-bit addresses [data]

    switch (nibble) {
        0x0 => {
            switch (kk) {
                // 00E0 - clear screen
                0xE0 => @memset(&self.display, 0),
                // 00EE - return from subroutine
                0xEE => {
                    self.sp -= 1;
                    self.pc = self.stack[self.sp];
                },
                else => std.debug.print("Unknown op: {d}\n", .{kk}),
            }
        },
        // 1NNN - jump to address NNN
        0x1 => {
            self.pc = nnn;
        },
        // 2NNN - call subroutine at NNN
        0x2 => {
            self.stack[self.sp] = self.pc;
            self.sp += 1;
            self.pc = nnn;
        },
        // 3XNN - skip next instruction if VX == NN
        0x3 => {
            if (self.V[@intCast(x)] == @as(u8, @intCast(kk))) self.pc += 2;
        },
        // 4XNN - skip next instruction if VX != NN
        0x4 => {
            if (self.V[@intCast(x)] != @as(u8, @intCast(kk))) self.pc += 2;
        },
        // 5XY0 - skip next instruction if VX == VY
        0x5 => {
            if (self.V[@intCast(x)] == self.V[@intCast(y)]) self.pc += 2;
        },
        // 6XNN - VX = NN
        0x6 => {
            self.V[@intCast(x)] = @intCast(kk);
        },
        // 7XNN - VX += NN
        0x7 => {
            self.V[@intCast(x)] += @intCast(kk);
        },
        // 8XYN - arithmetic and bitwise ops
        0x8 => {
            switch (n) {
                // 8XY0 - VX = VY
                0x0 => {
                    self.V[@intCast(x)] = self.V[@intCast(y)];
                },
                // 8XY1 - VX = VX OR VY
                0x1 => {
                    self.V[@intCast(x)] = self.V[@intCast(x)] | self.V[@intCast(y)];
                },
                // 8XY2 - VX = VX AND VY
                0x2 => {
                    self.V[@intCast(x)] = self.V[@intCast(x)] & self.V[@intCast(y)];
                },
                // 8XY3 - VX = VX XOR VY
                0x3 => {
                    self.V[@intCast(x)] = self.V[@intCast(x)] ^ self.V[@intCast(y)];
                },
                // 8XY4 - VX += VY, VF = 1 if overflow
                0x4 => {
                    const result: u16 = @as(u16, self.V[@intCast(x)]) + self.V[@intCast(y)];
                    self.V[0xF] = if (result > 0xFF) 1 else 0;
                    self.V[@intCast(x)] = @truncate(result);
                },
                // 8XY5 - VX -= VY, VF = 1 if no borrow
                0x5 => {
                    self.V[0xF] = if (self.V[@intCast(x)] >= self.V[@intCast(y)]) 1 else 0;
                    self.V[@intCast(x)] -%= self.V[@intCast(y)];
                },
                // 8XY6 - VX >>= 1, VF = shifted out bit
                0x6 => {
                    self.V[0xF] = self.V[@intCast(x)] & 0x1;
                    self.V[@intCast(x)] >>= 1;
                },
                // 8XY7 - VX = VY - VX, VF = 1 if no borrow
                0x7 => {
                    self.V[0xF] = if (self.V[@intCast(y)] >= self.V[@intCast(x)]) 1 else 0;
                    self.V[@intCast(x)] = self.V[@intCast(y)] -% self.V[@intCast(x)];
                },
                // 8XYE - VX <<= 1 (multiply by 2), VF = shifted out bit
                0xE => {
                    self.V[0xF] = if ((self.V[@intCast(x)] & 0x80) != 0) 1 else 0;
                    self.V[@intCast(x)] <<= 1;
                },
                else => std.debug.print("Unknown op: {d}\n", .{n}),
            }
        },
        // 9XNN - skip next instruction if Vx != Vy
        0x9 => {
            if (self.V[@intCast(x)] != self.V[@intCast(y)]) self.pc += 2;
        },
        // AXNN - set I to supplied address
        0xA => {
            self.I = nnn;
        },
        // CXNN - set Vx to an anded random number
        0xC => {
            self.V[@intCast(x)] = std.crypto.random.int(u8) & @as(u8, @intCast(kk));
        },
        // DXYN - draw N-byte sprite at (VX, VY), VF = 1 if pixels collide
        0xD => {
            const vx = self.V[@intCast(x)];
            const vy = self.V[@intCast(y)];

            for (0..n) |row| {
                const byte = self.memory[self.I + row];
                for (0..8) |col| {
                    if (byte & @as(u8, 0x80) >> @intCast(col) != 0) {
                        const px = (vx + col) % 64;
                        const py = (vy + row) % 32;
                        const idx = py * 64 + px;
                        // If collision turn on
                        if (self.display[idx] == 1) self.V[0xF] = 1;
                        self.display[idx] ^= self.display[idx];
                    }
                }
            }
        },
        0xE => {
            switch (kk) {
                // EX9E - skip next instruction if key in VX is pressed
                0x9E => {
                    std.debug.print("Key pressed\n", .{});
                },
                // EXA1 - skip next instruction if key in VX is not pressed
                0xA1 => {
                    std.debug.print("Key not pressed\n", .{});
                },
                else => std.debug.print("Unknown op: {d}\n", .{kk}),
            }
        },
        // FXNN - misc ops (timers, memory, input)
        0xF => {},
        else => std.debug.print("Unknown op: {d}\n", .{nibble}),
    }
}

test {
    const emu = init();
    _ = emu;
}
