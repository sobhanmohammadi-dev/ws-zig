//! Minimal Linux bindings.
//!
//! The interpreter only needs `read`, `write`, `openat` and `close`. Binding
//! those directly to the kernel keeps the standard library's buffered I/O
//! stack (and its allocator plumbing) out of the binary.
//!
//! Zig 0.17 puts its portable I/O layer behind `std.Io`, which drags in thread
//! and event-loop machinery. A batch interpreter that reads bytes and writes
//! bytes needs none of that, so this module talks to the kernel instead.

const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

comptime {
    if (builtin.os.tag != .linux)
        @compileError("wspace's syscall layer currently supports Linux only");
}

pub const stdin: linux.fd_t = 0;
pub const stdout: linux.fd_t = 1;
pub const stderr: linux.fd_t = 2;

/// `EINTR` is 4 on every Linux architecture.
const eintr = 4;

fn errno(rc: usize) ?usize {
    const signed: isize = @bitCast(rc);
    if (signed >= 0) return null;
    return @intCast(-signed);
}

/// Reads up to `buf.len` bytes. Returns 0 at end of file or on a read error;
/// interrupted reads are retried.
pub fn read(fd: linux.fd_t, buf: []u8) usize {
    while (true) {
        const rc = linux.read(fd, buf.ptr, buf.len);
        if (errno(rc)) |e| {
            if (e == eintr) continue;
            return 0;
        }
        return rc;
    }
}

/// Writes all of `bytes`, retrying short writes. Output is best effort: a
/// closed pipe or a hard write error ends the write instead of aborting the
/// interpreter.
pub fn write(fd: linux.fd_t, bytes: []const u8) void {
    var written: usize = 0;
    while (written < bytes.len) {
        const rc = linux.write(fd, bytes.ptr + written, bytes.len - written);
        if (errno(rc)) |e| {
            if (e == eintr) continue;
            return;
        }
        if (rc == 0) return;
        written += rc;
    }
}

pub fn close(fd: linux.fd_t) void {
    _ = linux.close(fd);
}

pub fn openReadOnly(path: []const u8) std.posix.OpenError!linux.fd_t {
    return std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0);
}
