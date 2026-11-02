//! Execution engine for decoded Whitespace v0.3 programs.
//!
//! Semantics follow the Haskell reference implementation, including its
//! non-obvious corners: values are the second-from-top operand for `store`,
//! `slide` tolerates depths smaller than its argument, `div`/`mod` round
//! towards negative infinity, and malformed code is only reported once the
//! instruction pointer reaches it.

const std = @import("std");
const parse = @import("parse.zig");
const sys = @import("sys.zig");

pub const Error = error{Runtime};

const Input = struct {
    buf: [4096]u8 = undefined,
    len: usize = 0,
    pos: usize = 0,

    fn readByte(self: *Input) ?u8 {
        if (self.pos == self.len) {
            self.len = sys.read(sys.stdin, &self.buf);
            self.pos = 0;
            if (self.len == 0) return null;
        }
        const byte = self.buf[self.pos];
        self.pos += 1;
        return byte;
    }

    /// One line of input without its terminator, or null at end of file.
    fn readLine(
        self: *Input,
        alloc: std.mem.Allocator,
        out: *std.ArrayList(u8),
    ) std.mem.Allocator.Error!?[]const u8 {
        out.clearRetainingCapacity();
        var any = false;
        while (true) {
            const byte = self.readByte() orelse break;
            any = true;
            if (byte == '\n') break;
            try out.append(alloc, byte);
        }
        if (!any) return null;
        return out.items;
    }
};

/// Reads one number from a line of input: optional surrounding ASCII
/// whitespace, an optional sign, then decimal digits.
fn inputNumber(text: []const u8) ?i64 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n\x0b\x0c");
    if (trimmed.len == 0) return null;

    var i: usize = 0;
    var negative = false;
    if (trimmed[0] == '-') {
        negative = true;
        i = 1;
    }
    if (i == trimmed.len) return null;

    var value: i64 = 0;
    while (i < trimmed.len) : (i += 1) {
        const digit = trimmed[i];
        if (digit < '0' or digit > '9') return null;
        value = value *% 10;
        value +%= @intCast(digit - '0');
    }
    return if (negative) -%value else value;
}

pub const Vm = struct {
    alloc: std.mem.Allocator,
    prog: []const parse.Instr,
    labels: []const parse.Label,
    parse_err: ?parse.ParseError,

    stack: std.ArrayList(i64) = .empty,
    heap: std.ArrayList(i64) = .empty,
    calls: std.ArrayList(u32) = .empty,
    line: std.ArrayList(u8) = .empty,
    input: Input = .{},

    pub fn init(
        alloc: std.mem.Allocator,
        prog: []const parse.Instr,
        labels: []const parse.Label,
        parse_err: ?parse.ParseError,
    ) Vm {
        return .{ .alloc = alloc, .prog = prog, .labels = labels, .parse_err = parse_err };
    }

    pub fn deinit(self: *Vm) void {
        self.stack.deinit(self.alloc);
        self.heap.deinit(self.alloc);
        self.calls.deinit(self.alloc);
        self.line.deinit(self.alloc);
    }

    fn fail(self: *Vm, comptime format: []const u8, args: anytype) Error {
        _ = self;
        var buf: [320]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, "wspace: " ++ format ++ "\n", args) catch
            "wspace: error\n";
        sys.write(sys.stderr, message);
        return error.Runtime;
    }

    fn push(self: *Vm, value: i64) Error!void {
        self.stack.append(self.alloc, value) catch
            return self.fail("out of memory", .{});
    }

    fn pop(self: *Vm, comptime what: []const u8) Error!i64 {
        const len = self.stack.items.len;
        if (len == 0) return self.fail("stack underflow ({s})", .{what});
        const value = self.stack.items[len - 1];
        self.stack.items.len = len - 1;
        return value;
    }

    fn peek(self: *Vm, comptime what: []const u8) Error!i64 {
        if (self.stack.items.len == 0) return self.fail("stack underflow ({s})", .{what});
        return self.stack.items[self.stack.items.len - 1];
    }

    fn labelPos(self: *Vm, id: u32) Error!usize {
        const label = self.labels[id];
        const pos = label.pos orelse
            return self.fail("undefined label ({s})", .{label.name});
        return pos;
    }

    fn heapStore(self: *Vm, address: i64, value: i64) Error!void {
        if (address < 0) return self.fail("negative heap address ({d})", .{address});
        const index: usize = @intCast(address);
        if (index >= self.heap.items.len) {
            const old_len = self.heap.items.len;
            self.heap.resize(self.alloc, index + 1) catch
                return self.fail("out of memory", .{});
            // The reference implementation pads the heap with zeros.
            @memset(self.heap.items[old_len..], 0);
        }
        self.heap.items[index] = value;
    }

    fn heapLoad(self: *Vm, address: i64) Error!i64 {
        if (address < 0 or @as(u64, @intCast(address)) >= self.heap.items.len)
            return self.fail("heap address out of range ({d})", .{address});
        return self.heap.items[@intCast(address)];
    }

    pub fn run(self: *Vm) Error!void {
        var pc: usize = 0;
        while (true) {
            if (pc >= self.prog.len) {
                if (self.parse_err) |err| return self.fail("{s} at byte {d}", .{
                    err.kind.message(),
                    err.offset,
                });
                return self.fail("instruction pointer out of range ({d})", .{pc});
            }

            const instr = self.prog[pc];
            pc += 1;

            switch (instr) {
                .push => |value| try self.push(value),

                .dup => {
                    const value = try self.peek("dup");
                    try self.push(value);
                },

                .copy => |depth| {
                    if (depth < 0 or @as(u64, @intCast(depth)) >= self.stack.items.len)
                        return self.fail("stack index out of range (copy {d})", .{depth});
                    const index = self.stack.items.len - 1 - @as(usize, @intCast(depth));
                    try self.push(self.stack.items[index]);
                },

                .slide => |depth| {
                    const len = self.stack.items.len;
                    if (len == 0) return self.fail("stack underflow (slide)", .{});
                    // `drop` is total in Haskell, so a slide deeper than the
                    // stack just empties it; a negative depth removes nothing.
                    var keep = len;
                    if (depth >= 0) {
                        const removed: usize = @intCast(depth);
                        keep = if (removed >= len) 1 else len - removed;
                    }
                    if (keep != len) {
                        self.stack.items[keep - 1] = self.stack.items[len - 1];
                        self.stack.items.len = keep;
                    }
                },

                .swap => {
                    const len = self.stack.items.len;
                    if (len < 2) return self.fail("stack underflow (swap)", .{});
                    const top = self.stack.items[len - 1];
                    self.stack.items[len - 1] = self.stack.items[len - 2];
                    self.stack.items[len - 2] = top;
                },

                .discard => {
                    _ = try self.pop("discard");
                },

                .add => {
                    const y = try self.pop("add");
                    const x = try self.pop("add");
                    try self.push(x +% y);
                },

                .sub => {
                    const y = try self.pop("subtract");
                    const x = try self.pop("subtract");
                    try self.push(x -% y);
                },

                .mul => {
                    const y = try self.pop("multiply");
                    const x = try self.pop("multiply");
                    try self.push(x *% y);
                },

                .div => {
                    const y = try self.pop("divide");
                    const x = try self.pop("divide");
                    if (y == 0) return self.fail("division by zero", .{});
                    // Haskell's `div` rounds towards negative infinity.
                    if (x == std.math.minInt(i64) and y == -1)
                        try self.push(std.math.minInt(i64))
                    else
                        try self.push(@divFloor(x, y));
                },

                .mod => {
                    const y = try self.pop("modulo");
                    const x = try self.pop("modulo");
                    if (y == 0) return self.fail("division by zero", .{});
                    // Haskell's `mod` takes the sign of the divisor.
                    if (x == std.math.minInt(i64) and y == -1)
                        try self.push(0)
                    else
                        try self.push(@mod(x, y));
                },

                .store => {
                    const value = try self.pop("store");
                    const address = try self.pop("store");
                    try self.heapStore(address, value);
                },

                .retrieve => {
                    const address = try self.pop("retrieve");
                    try self.push(try self.heapLoad(address));
                },

                .label => {},

                .call => |id| {
                    const target = try self.labelPos(id);
                    self.calls.append(self.alloc, @intCast(pc)) catch
                        return self.fail("out of memory", .{});
                    pc = target;
                },

                .jump => |id| pc = try self.labelPos(id),

                .jump_zero => |id| {
                    const value = try self.pop("if zero");
                    if (value == 0) pc = try self.labelPos(id);
                },

                .jump_negative => |id| {
                    const value = try self.pop("if negative");
                    if (value < 0) pc = try self.labelPos(id);
                },

                .ret => {
                    const len = self.calls.items.len;
                    if (len == 0) return self.fail("call stack underflow (return)", .{});
                    const target = self.calls.items[len - 1];
                    self.calls.items.len = len - 1;
                    pc = target;
                },

                .out_char => {
                    const value = try self.pop("output character");
                    if (value < 0 or value > 0x10FFFF)
                        return self.fail("invalid character code ({d})", .{value});
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(@intCast(value), &buf) catch
                        return self.fail("invalid character code ({d})", .{value});
                    sys.write(sys.stdout, buf[0..len]);
                },

                .out_num => {
                    const value = try self.pop("output number");
                    var buf: [24]u8 = undefined;
                    const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
                    sys.write(sys.stdout, text);
                },

                .read_char => {
                    const byte = self.input.readByte() orelse
                        return self.fail("end of file on input", .{});
                    try self.push(byte);
                },

                .read_num => {
                    const line = self.input.readLine(self.alloc, &self.line) catch
                        return self.fail("out of memory", .{});
                    const text = line orelse return self.fail("end of file on input", .{});
                    const value = inputNumber(text) orelse
                        return self.fail("invalid number on input ({s})", .{text});
                    try self.push(value);
                },

                .end => return,
            }
        }
    }
};
