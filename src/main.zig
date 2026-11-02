//! Command-line entry point: `wspace FILE`.
//!
//! Argument handling matches the reference interpreter exactly: a single
//! argument is a file to run, anything else prints the usage banner and exits
//! successfully. There are no options.

const std = @import("std");
const parse = @import("parse.zig");
const sys = @import("sys.zig");
const Vm = @import("vm.zig").Vm;

/// Byte-for-byte the banner printed by the reference implementation.
const usage =
    "wspace 0.2 (c) 2003 Edwin Brady\n" ++
    "-------------------------------\n" ++
    "Usage: wspace [file]\n";

pub fn main(init: std.process.Init.Minimal) u8 {
    const args = init.args.vector;
    if (args.len != 2) {
        sys.write(sys.stdout, usage);
        return 0;
    }

    const path = std.mem.span(args[1]);

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

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

fn readFile(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    const fd = try sys.openReadOnly(path);
    defer sys.close(fd);

    var contents: std.ArrayList(u8) = .empty;
    var buf: [16384]u8 = undefined;
    while (true) {
        const len = sys.read(fd, &buf);
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
