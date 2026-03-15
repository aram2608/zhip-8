//! Memory: 4 kilobytes, about 4096 bytes
//! Display: 64 x 32, about 640 and 320
//! Program counter: points at current instruction
//! Index register: I, points somewhere in the memory
//! Stack for 16-bit addresses
//! Delay timer: 8-bit timer, basically fps 60 hz, so 60 times/sec
//! Sound timer: 8-bit timer for sounds
//! 16 8-bit (1 byte) registers for variables, 0 through F in hexadecimal
//!
//! Instructions follow the EXYN syntax.
//! E is the first nibble and represents the type of instruction.
//! X is the second nibble and looks up vars in the var registers (VX).
//! Y is the third nibble and looks up vars in the var registers (VY).
//! N is the fourth nibble. A 4-bit number.
//! NN is the second byte. An 8-bit number.
//! NNN is the second, third, and fourth nibbles. A 12-bit memory address.

const std = @import("std");
const CPU = @This();

// Available RAM for emulator
memory: [4096]u8,
// Variable register V0 to VF
V: [16]u8,
// Delay timer
dt: u8,
// Sound timer
st: u8,

// Program counter
// Needs to start after the font memory
pc: u16 = 0x200,
// Subroutine stack
stack: [16]u16,
// Stack pointer
sp: u16,
// Register index
I: u16,
display: [64 * 32]u1,
// Keyyboard inputs
keys: [16]u1,

pub fn init() CPU {
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
        .keys = std.mem.zeroes([16]u1),
    };
}

/// Opcodes are 2 bytes so we extract the op then advance.
fn getOpcode(self: *CPU) u16 {
    const op: u16 = @as(u16, self.memory[self.pc]) << 8 | self.memory[self.pc + 1];
    self.pc += 2;
    return op;
}

pub fn loadRom(self: *CPU, path: []const u8) !void {
    @memcpy(self.memory[0..font.len], &font);
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    // ROMs are loaded at the program counter
    _ = try file.read(self.memory[0x200..]);
}

pub fn emulate(self: *CPU) void {
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
            self.V[@intCast(x)] +%= @intCast(kk);
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
        // BNNN - jump to NNN + V0
        0xB => {
            self.pc = nnn + self.V[0];
        },
        // CXNN - set Vx to an anded random number
        0xC => {
            self.V[@intCast(x)] = std.crypto.random.int(u8) & @as(u8, @intCast(kk));
        },
        // DXYN - draw N-byte sprite at (VX, VY), VF = 1 if pixels collide
        0xD => {
            const vx = self.V[@intCast(x)];
            const vy = self.V[@intCast(y)];
            self.V[0xF] = 0;

            for (0..n) |row| {
                const byte = self.memory[self.I + row];
                for (0..8) |col| {
                    if ((byte & (@as(u8, 0x80) >> @intCast(col))) != 0) {
                        const px = (vx + col) % 64;
                        const py = vy + row;
                        if (py >= 32) break;
                        const idx = py * 64 + px;
                        if (self.display[idx] == 1) self.V[0xF] = 1;
                        self.display[idx] ^= 1;
                    }
                }
            }
        },
        0xE => {
            switch (kk) {
                // EX9E - skip next instruction if key in VX is pressed
                0x9E => {
                    if (self.keys[@intCast(self.V[x])] == 1) self.pc += 2;
                },
                // EXA1 - skip next instruction if key in VX is not pressed
                0xA1 => {
                    if (self.keys[@intCast(self.V[x])] == 0) self.pc += 2;
                },
                else => std.debug.print("Unknown op: {d}\n", .{kk}),
            }
        },
        // FXNN - misc ops (timers, memory, input)
        0xF => {
            switch (kk) {
                // FX07 - VX = delay timer
                0x07 => {
                    self.V[@intCast(x)] = self.dt;
                },
                // FX0A - wait for key press, store key in VX
                0x0A => {
                    var found = false;
                    for (self.keys, 0..) |k, i| {
                        if (k == 1) {
                            self.V[@intCast(x)] = @intCast(i);
                            found = true;
                            break;
                        }
                    }
                    // If not found redo instruction
                    if (!found) self.pc -= 2;
                },
                // FX15 - set delay timer = VX
                0x15 => {
                    self.dt = self.V[@intCast(x)];
                },
                // FX18 - set sound timer = VX
                0x18 => {
                    self.st = self.V[@intCast(x)];
                },
                // FX1E - I += VX
                0x1E => {
                    self.I += self.V[@intCast(x)];
                },
                // FX29 - set I to font sprite for digit VX
                0x29 => {
                    self.I = self.V[@intCast(x)] * 5;
                },
                // FX33 - BCD representation of VX in memory[I..I+2]
                0x33 => {
                    const val = self.V[@intCast(x)];
                    self.memory[self.I] = val / 100;
                    self.memory[self.I + 1] = (val / 10) % 10;
                    self.memory[self.I + 2] = val % 10;
                },
                // FX55 - store V0..VX in memory starting at I
                0x55 => {
                    for (0..@intCast(x + 1)) |i| {
                        self.memory[self.I + i] = self.V[i];
                    }
                },
                // FX65 - load V0..VX from memory starting at I
                0x65 => {
                    for (0..@intCast(x + 1)) |i| {
                        self.V[i] = self.memory[self.I + i];
                    }
                },
                else => std.debug.print("Unknown op: F{X:0>2}\n", .{kk}),
            }
        },
        else => std.debug.print("Unknown op: {d}\n", .{nibble}),
    }
}

const font: [16 * 5]u8 = .{
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
};

test {
    const emu = init();
    _ = emu;
}
