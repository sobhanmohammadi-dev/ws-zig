//! Command-line entry point: `wspace FILE`.
//!
//! Argument handling matches the reference interpreter exactly: a single
//! argument is a file to run, anything else prints the usage banner and exits
//! successfully. There are no options.

const std = @import("std");
const builtin = @import("builtin");
const parse = @import("parse.zig");
const sys = @import("sys.zig");
const Vm = @import("vm.zig").Vm;

/// the banner
const usage =
    "wspace 0.3 (c) 2003 Edwin Brady\n" ++
    "-------------------------------\n" ++
    "Usage: wspace [file]\n";

pub fn main(init: std.process.Init.Minimal) u8 {
    sys.init();

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var raw_args: [2][]const u8 = undefined;
    if (collectArgs(init, arena, &raw_args) != 2) {
        sys.write(sys.stdout, usage);
        return 0;
    }
    const path = raw_args[1];

    const source = readFile(arena, path) catch |err| {
        report(@errorName(err), path);
        return 1;
    };

    const program = parse.parse(arena, source) catch {
        report("out of memory", path);
        return 1;
    };

    var machine = Vm.init(std.heap.page_allocator, program.instrs, program.labels, program.err);
    defer machine.deinit();
    machine.run() catch return 1;
    return 0;
}

/// Fills `out` with the first arguments and returns the true argument count, so
/// too many arguments can be rejected. Unix passes NUL-terminated byte strings;
/// Windows passes the raw WTF-16 command line, which needs the standard
/// library's reimplementation of the C runtime parsing rules plus a transcode,
/// so those slices are copied into the arena that outlives the iterator.
fn collectArgs(init: std.process.Init.Minimal, arena: std.mem.Allocator, out: *[2][]const u8) usize {
    if (builtin.os.tag == .windows) {
        var it = std.process.Args.Iterator.initAllocator(init.args, arena) catch return 0;
        defer it.deinit();
        var count: usize = 0;
        while (it.next()) |arg| : (count += 1) {
            if (count < out.len) out[count] = arena.dupe(u8, arg) catch return count;
        }
        return count;
    }

    const vector = init.args.vector;
    const copied = @min(vector.len, out.len);
    for (0..copied) |i| out[i] = std.mem.span(vector[i]);
    return vector.len;
}

fn readFile(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try sys.openReadOnly(alloc, path);
    defer sys.closeSource(file);

    var contents: std.ArrayList(u8) = .empty;
    var buf: [16384]u8 = undefined;
    while (true) {
        const len = sys.readSource(file, &buf);
        if (len == 0) break;
        try contents.appendSlice(alloc, buf[0..len]);
    }
    return contents.toOwnedSlice(alloc);
}

fn report(message: []const u8, path: []const u8) void {
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "wspace: {s}: {s}\n", .{ path, message }) catch
        "wspace: error\n";
    sys.write(sys.stderr, text);
}
