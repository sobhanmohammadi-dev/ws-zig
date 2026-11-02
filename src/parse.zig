//! Whitespace v0.3 source decoding.
//!
//! Tokens are read straight from the raw source bytes: every byte other than
//! space, tab and line feed is ignored, exactly like `tokenise` in the Haskell
//! reference implementation. Decoding stops at the first malformed instruction
//! and records the reason; the error is only reported if execution reaches it,
//! which preserves the reference implementation's lazy parse errors.

const std = @import("std");

/// The Whitespace v0.3 instruction set as implemented by wspace 0.3.
pub const Instr = union(enum) {
    push: i64,
    dup,
    copy: i64,
    slide: i64,
    swap,
    discard,
    add,
    sub,
    mul,
    div,
    mod,
    store,
    retrieve,
    label: u32,
    call: u32,
    jump: u32,
    jump_zero: u32,
    jump_negative: u32,
    ret,
    out_char,
    out_num,
    read_char,
    read_num,
    end,
};

pub const ParseErrorKind = enum {
    unrecognised,
    truncated_number,
    truncated_label,
    missing_sign_bit,

    pub fn message(kind: ParseErrorKind) []const u8 {
        return switch (kind) {
            .unrecognised => "unrecognised instruction",
            .truncated_number => "unexpected end of program in number literal",
            .truncated_label => "unexpected end of program in label",
            .missing_sign_bit => "number literal has no sign bit",
        };
    }
};

pub const ParseError = struct {
    kind: ParseErrorKind,
    /// Byte offset in the source of the instruction that could not be decoded.
    offset: usize,
};

pub const Label = struct {
    /// Label text in canonical form: `' '` for space, `'\t'` for tab.
    name: []const u8,
    /// Index of the first `label` instruction that defines this name.
    pos: ?u32 = null,
};

pub const Program = struct {
    instrs: []const Instr,
    labels: []const Label,
    /// Set when decoding stopped early.
    err: ?ParseError,
};

const space = ' ';
const tab = '\t';
const newline = '\n';

const Reader = struct {
    src: []const u8,
    pos: usize = 0,

    fn next(self: *Reader) ?u8 {
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            self.pos += 1;
            if (c == space or c == tab or c == newline) return c;
        }
        return null;
    }
};

const Step = union(enum) {
    ok: Instr,
    bad: ParseErrorKind,
    eof,
};

const Number = union(enum) {
    ok: i64,
    bad: ParseErrorKind,
};

const Text = union(enum) {
    ok: []const u8,
    bad: ParseErrorKind,
};

const Context = struct {
    alloc: std.mem.Allocator,
    labels: std.ArrayList(Label) = .empty,

    /// Returns the id of `name`, appending it if it is new. The reference
    /// implementation compares labels as strings, so interning here gives the
    /// same equality with a single lookup per reference.
    fn intern(self: *Context, name: []const u8) std.mem.Allocator.Error!u32 {
        for (self.labels.items, 0..) |label, i| {
            if (std.mem.eql(u8, label.name, name)) return @intCast(i);
        }
        try self.labels.append(self.alloc, .{ .name = try self.alloc.dupe(u8, name) });
        return @intCast(self.labels.items.len - 1);
    }
};

/// A number literal is a sign token (space for positive, tab for negative)
/// followed by binary digits, most significant first, terminated by a newline.
fn readNumber(r: *Reader) Number {
    const sign = r.next() orelse return .{ .bad = .truncated_number };
    if (sign == newline) return .{ .bad = .missing_sign_bit };

    var value: i64 = 0;
    while (true) {
        const token = r.next() orelse return .{ .bad = .truncated_number };
        if (token == newline) break;
        value = value *% 2;
        if (token == tab) value +%= 1;
    }
    return .{ .ok = if (sign == tab) -%value else value };
}

fn readLabel(r: *Reader, alloc: std.mem.Allocator) std.mem.Allocator.Error!Text {
    var buf: std.ArrayList(u8) = .empty;
    while (true) {
        const token = r.next() orelse return .{ .bad = .truncated_label };
        if (token == newline) return .{ .ok = try buf.toOwnedSlice(alloc) };
        try buf.append(alloc, token);
    }
}

fn decodeLabel(r: *Reader, ctx: *Context, comptime tag: std.meta.Tag(Instr)) !Step {
    const text = try readLabel(r, ctx.alloc);
    switch (text) {
        .ok => |name| return .{ .ok = @unionInit(Instr, @tagName(tag), try ctx.intern(name)) },
        .bad => |kind| return .{ .bad = kind },
    }
}

fn decodeOne(r: *Reader, ctx: *Context) std.mem.Allocator.Error!Step {
    const first = r.next() orelse return .eof;

    switch (first) {
        space => {
            const second = r.next() orelse return .{ .bad = .unrecognised };
            switch (second) {
                space => switch (readNumber(r)) {
                    .ok => |value| return .{ .ok = .{ .push = value } },
                    .bad => |kind| return .{ .bad = kind },
                },
                tab => {
                    const third = r.next() orelse return .{ .bad = .unrecognised };
                    switch (third) {
                        space => switch (readNumber(r)) {
                            .ok => |value| return .{ .ok = .{ .copy = value } },
                            .bad => |kind| return .{ .bad = kind },
                        },
                        newline => switch (readNumber(r)) {
                            .ok => |value| return .{ .ok = .{ .slide = value } },
                            .bad => |kind| return .{ .bad = kind },
                        },
                        else => return .{ .bad = .unrecognised },
                    }
                },
                newline => {
                    const third = r.next() orelse return .{ .bad = .unrecognised };
                    switch (third) {
                        space => return .{ .ok = .dup },
                        tab => return .{ .ok = .swap },
                        newline => return .{ .ok = .discard },
                        else => return .{ .bad = .unrecognised },
                    }
                },
                else => return .{ .bad = .unrecognised },
            }
        },
        tab => {
            const second = r.next() orelse return .{ .bad = .unrecognised };
            switch (second) {
                space => {
                    const third = r.next() orelse return .{ .bad = .unrecognised };
                    switch (third) {
                        space => {
                            const fourth = r.next() orelse return .{ .bad = .unrecognised };
                            switch (fourth) {
                                space => return .{ .ok = .add },
                                tab => return .{ .ok = .sub },
                                newline => return .{ .ok = .mul },
                                else => return .{ .bad = .unrecognised },
                            }
                        },
                        tab => {
                            const fourth = r.next() orelse return .{ .bad = .unrecognised };
                            switch (fourth) {
                                space => return .{ .ok = .div },
                                tab => return .{ .ok = .mod },
                                else => return .{ .bad = .unrecognised },
                            }
                        },
                        else => return .{ .bad = .unrecognised },
                    }
                },
                tab => {
                    const third = r.next() orelse return .{ .bad = .unrecognised };
                    switch (third) {
                        space => return .{ .ok = .store },
                        tab => return .{ .ok = .retrieve },
                        else => return .{ .bad = .unrecognised },
                    }
                },
                newline => {
                    const third = r.next() orelse return .{ .bad = .unrecognised };
                    switch (third) {
                        space => {
                            const fourth = r.next() orelse return .{ .bad = .unrecognised };
                            switch (fourth) {
                                space => return .{ .ok = .out_char },
                                tab => return .{ .ok = .out_num },
                                else => return .{ .bad = .unrecognised },
                            }
                        },
                        tab => {
                            const fourth = r.next() orelse return .{ .bad = .unrecognised };
                            switch (fourth) {
                                space => return .{ .ok = .read_char },
                                tab => return .{ .ok = .read_num },
                                else => return .{ .bad = .unrecognised },
                            }
                        },
                        else => return .{ .bad = .unrecognised },
                    }
                },
                else => return .{ .bad = .unrecognised },
            }
        },
        newline => {
            const second = r.next() orelse return .{ .bad = .unrecognised };
            switch (second) {
                space => {
                    const third = r.next() orelse return .{ .bad = .unrecognised };
                    switch (third) {
                        space => return decodeLabel(r, ctx, .label),
                        tab => return decodeLabel(r, ctx, .call),
                        newline => return decodeLabel(r, ctx, .jump),
                        else => return .{ .bad = .unrecognised },
                    }
                },
                tab => {
                    const third = r.next() orelse return .{ .bad = .unrecognised };
                    switch (third) {
                        space => return decodeLabel(r, ctx, .jump_zero),
                        tab => return decodeLabel(r, ctx, .jump_negative),
                        newline => return .{ .ok = .ret },
                        else => return .{ .bad = .unrecognised },
                    }
                },
                newline => {
                    const third = r.next() orelse return .{ .bad = .unrecognised };
                    if (third == newline) return .{ .ok = .end };
                    return .{ .bad = .unrecognised };
                },
                else => return .{ .bad = .unrecognised },
            }
        },
        else => unreachable,
    }
}

pub fn parse(alloc: std.mem.Allocator, src: []const u8) std.mem.Allocator.Error!Program {
    var instrs: std.ArrayList(Instr) = .empty;
    var ctx: Context = .{ .alloc = alloc };
    var reader: Reader = .{ .src = src };
    var err: ?ParseError = null;

    while (true) {
        const start = reader.pos;
        const step = try decodeOne(&reader, &ctx);
        switch (step) {
            .eof => break,
            .bad => |kind| {
                err = .{ .kind = kind, .offset = start };
                break;
            },
            .ok => |instr| {
                const index: u32 = @intCast(instrs.items.len);
                try instrs.append(alloc, instr);
                // The first `label` instruction defining a name wins, matching
                // the reference implementation's `findLabel'` scan.
                switch (instr) {
                    .label => |id| {
                        const label = &ctx.labels.items[id];
                        if (label.pos == null) label.pos = index;
                    },
                    else => {},
                }
            },
        }
    }

    return .{
        .instrs = try instrs.toOwnedSlice(alloc),
        .labels = try ctx.labels.toOwnedSlice(alloc),
        .err = err,
    };
}
