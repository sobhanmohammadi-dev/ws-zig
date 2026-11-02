//! Unit tests for the decoder.
//!
//! Whitespace is written here in a readable form: `s` is a space, `t` a tab and
//! `n` a newline, so `ssn` is the three source bytes space, space, newline.

const std = @import("std");
const parse = @import("parse.zig");

fn src(comptime text: []const u8) []const u8 {
    comptime var out: []const u8 = "";
    inline for (text) |c| {
        out = out ++ switch (c) {
            's' => " ",
            't' => "\t",
            'n' => "\n",
            else => @compileError("only s, t and n are allowed in test source"),
        };
    }
    return out;
}

/// A number literal: sign token, binary digits most significant first, newline.
fn number(comptime value: i64) []const u8 {
    comptime var out: []const u8 = if (value < 0) "t" else "s";
    const magnitude: u64 = if (value < 0) @intCast(-value) else @intCast(value);
    if (magnitude == 0) return out ++ "n";

    var shift: u6 = 63;
    while ((magnitude >> shift) == 0) shift -= 1;
    while (true) {
        out = out ++ if ((magnitude >> shift) & 1 == 1) "t" else "s";
        if (shift == 0) break;
        shift -= 1;
    }
    return out ++ "n";
}

fn push(comptime value: i64) []const u8 {
    return "ss" ++ number(value);
}

test "push decodes magnitudes and signs" {
    const cases = [_]i64{ 0, 1, 2, 72, 255, 1000, -1, -72, -1000 };
    inline for (cases) |value| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const program = try parse.parse(arena.allocator(), src(push(value)));
        try std.testing.expectEqual(@as(usize, 1), program.instrs.len);
        try std.testing.expectEqual(value, program.instrs[0].push);
        try std.testing.expectEqual(@as(?parse.ParseError, null), program.err);
    }
}

test "equals token is decoded after a sign-less number" {
    // push 0 followed by dup (space, newline, space) to prove the number's
    // terminating newline is consumed exactly once.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse.parse(arena.allocator(), src(push(0) ++ "sns"));
    try std.testing.expectEqual(@as(usize, 2), program.instrs.len);
    try std.testing.expectEqual(@as(i64, 0), program.instrs[0].push);
    try std.testing.expectEqual(parse.Instr.dup, program.instrs[1]);
}

test "stack, arithmetic, heap, control and io opcodes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse.parse(arena.allocator(), src(
        "sns" ++ // dup
            "snt" ++ // swap
            "snn" ++ // discard
            "sts" ++ number(2) ++ // copy 2
            "stn" ++ number(3) ++ // slide 3
            "tsss" ++ // add
            "tsst" ++ // sub
            "tssn" ++ // mul
            "tsts" ++ // div
            "tstt" ++ // mod
            "tts" ++ // store
            "ttt" ++ // retrieve
            "tnss" ++ // output character
            "tnst" ++ // output number
            "tnts" ++ // read character
            "tntt" ++ // read number
            "ntn" ++ // return
            "nnn", // end
    ));
    try std.testing.expectEqual(@as(?parse.ParseError, null), program.err);
    try std.testing.expectEqual(@as(usize, 18), program.instrs.len);
    try std.testing.expectEqual(parse.Instr.dup, program.instrs[0]);
    try std.testing.expectEqual(parse.Instr.swap, program.instrs[1]);
    try std.testing.expectEqual(parse.Instr.discard, program.instrs[2]);
    try std.testing.expectEqual(@as(i64, 2), program.instrs[3].copy);
    try std.testing.expectEqual(@as(i64, 3), program.instrs[4].slide);
    try std.testing.expectEqual(parse.Instr.add, program.instrs[5]);
    try std.testing.expectEqual(parse.Instr.sub, program.instrs[6]);
    try std.testing.expectEqual(parse.Instr.mul, program.instrs[7]);
    try std.testing.expectEqual(parse.Instr.div, program.instrs[8]);
    try std.testing.expectEqual(parse.Instr.mod, program.instrs[9]);
    try std.testing.expectEqual(parse.Instr.store, program.instrs[10]);
    try std.testing.expectEqual(parse.Instr.retrieve, program.instrs[11]);
    try std.testing.expectEqual(parse.Instr.out_char, program.instrs[12]);
    try std.testing.expectEqual(parse.Instr.out_num, program.instrs[13]);
    try std.testing.expectEqual(parse.Instr.read_char, program.instrs[14]);
    try std.testing.expectEqual(parse.Instr.read_num, program.instrs[15]);
    try std.testing.expectEqual(parse.Instr.ret, program.instrs[16]);
    try std.testing.expectEqual(parse.Instr.end, program.instrs[17]);
}

test "labels are interned and the first definition wins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse.parse(arena.allocator(), src(
        "nss" ++ "st" ++ "n" ++ // label <tab,space>
            "nnn" ++ // end
            "nss" ++ "st" ++ "n" ++ // label <tab,space> again
            "ntn", // return
    ));
    try std.testing.expectEqual(@as(?parse.ParseError, null), program.err);
    try std.testing.expectEqual(@as(usize, 1), program.labels.len);
    try std.testing.expectEqual(@as(u32, 0), program.instrs[0].label);
    try std.testing.expectEqual(@as(u32, 0), program.instrs[2].label);
    try std.testing.expectEqual(@as(?u32, 0), program.labels[0].pos);
    try std.testing.expectEqualSlices(u8, " \t", program.labels[0].name);
}

test "malformed instructions stop decoding and are reported later" {
    const cases = [_]struct { source: []const u8, kind: parse.ParseErrorKind }{
        .{ .source = "stt", .kind = .unrecognised },
        .{ .source = "ss", .kind = .truncated_number },
        .{ .source = "ssn", .kind = .missing_sign_bit },
        .{ .source = "nss", .kind = .truncated_label },
        .{ .source = "nss" ++ "s", .kind = .truncated_label },
    };
    inline for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const program = try parse.parse(arena.allocator(), src(case.source));
        try std.testing.expectEqual(@as(usize, 0), program.instrs.len);
        try std.testing.expectEqual(case.kind, program.err.?.kind);
    }
}

test "a malformed tail after end does not discard the program" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse.parse(arena.allocator(), src("nnn" ++ "stt"));
    try std.testing.expectEqual(@as(usize, 1), program.instrs.len);
    try std.testing.expectEqual(parse.Instr.end, program.instrs[0]);
    try std.testing.expectEqual(parse.ParseErrorKind.unrecognised, program.err.?.kind);
}

test "empty program decodes to nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse.parse(arena.allocator(), "");
    try std.testing.expectEqual(@as(usize, 0), program.instrs.len);
    try std.testing.expectEqual(@as(?parse.ParseError, null), program.err);
}
