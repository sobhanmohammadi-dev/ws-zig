//! Minimal platform layer.
//!
//! Linux binds `read`, `write`, `openat` and `close` straight to the kernel,
//! which keeps libc and the standard library's buffered I/O stack out of the
//! shipped binary. macOS and Windows go through libc because neither provides a
//! stable raw-call ABI for these operations: libSystem on Darwin, the C runtime
//! (`_open`/`_read`/`_write`) on Windows. All backends expose the same four
//! operations, so the VM and `main` never see the difference.

const std = @import("std");
const builtin = @import("builtin");
const os = builtin.os.tag;

const is_linux = os == .linux;
const is_windows = os == .windows;
const is_macos = os == .macos;

comptime {
    if (!(is_linux or is_macos or is_windows))
        @compileError("wspace supports Linux, macOS and Windows; add a backend in src/sys.zig for another target");
}

/// Standard stream selector. Not a bare `0`/`1`/`2` on every platform, but the
/// C runtime and POSIX both use those numbers, so they are the values here.
pub const Std = enum { in, out, err };

pub const stdin: Std = .in;
pub const stdout: Std = .out;
pub const stderr: Std = .err;

/// An open program file: a file descriptor on every supported platform.
pub const Source = c_int;

fn streamFd(stream: Std) c_int {
    return switch (stream) {
        .in => 0,
        .out => 1,
        .err => 2,
    };
}

/// `EINTR` is 4 on Linux and Darwin; Windows has no equivalent for these calls.
const eintr = 4;

// ---------------------------------------------------------------------------
// Linux: raw syscalls
// ---------------------------------------------------------------------------

const linux = std.os.linux;

fn linuxErrno(rc: usize) ?usize {
    const signed: isize = @bitCast(rc);
    if (signed >= 0) return null;
    return @intCast(-signed);
}

fn linuxRead(fd: linux.fd_t, buf: []u8) usize {
    while (true) {
        const rc = linux.read(fd, buf.ptr, buf.len);
        if (linuxErrno(rc)) |e| {
            if (e == eintr) continue;
            return 0;
        }
        return rc;
    }
}

fn linuxWrite(fd: linux.fd_t, bytes: []const u8) void {
    var written: usize = 0;
    while (written < bytes.len) {
        const rc = linux.write(fd, bytes.ptr + written, bytes.len - written);
        if (linuxErrno(rc)) |e| {
            if (e == eintr) continue;
            return;
        }
        if (rc == 0) return;
        written += rc;
    }
}

// ---------------------------------------------------------------------------
// macOS: libSystem
// ---------------------------------------------------------------------------

const darwin = struct {
    extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
    extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;
    extern "c" fn close(fd: c_int) c_int;
    extern "c" fn __error() *c_int;
};

fn darwinRead(fd: c_int, buf: []u8) usize {
    while (true) {
        const rc = darwin.read(fd, buf.ptr, buf.len);
        if (rc < 0) {
            if (darwin.__error().* == eintr) continue;
            return 0;
        }
        return @intCast(rc);
    }
}

fn darwinWrite(fd: c_int, bytes: []const u8) void {
    var written: usize = 0;
    while (written < bytes.len) {
        const rc = darwin.write(fd, bytes.ptr + written, bytes.len - written);
        if (rc < 0) {
            if (darwin.__error().* == eintr) continue;
            return;
        }
        if (rc == 0) return;
        written += @intCast(rc);
    }
}

// ---------------------------------------------------------------------------
// Windows: C runtime
// ---------------------------------------------------------------------------

const win = struct {
    extern "c" fn _wopen(path: [*:0]const u16, oflag: c_int, ...) c_int;
    extern "c" fn _read(fd: c_int, buf: [*]u8, count: c_uint) c_int;
    extern "c" fn _write(fd: c_int, buf: [*]const u8, count: c_uint) c_int;
    extern "c" fn _close(fd: c_int) c_int;
    extern "c" fn _setmode(fd: c_int, mode: c_int) c_int;
    extern "c" fn _errno() *c_int;

    /// `_O_RDONLY` is 0; `_O_BINARY` stops the CRT translating `\n` to `\r\n`,
    /// so output is byte-identical to the Unix builds.
    const o_rdonly: c_int = 0;
    const o_binary: c_int = 0x8000;
};

fn winRead(fd: c_int, buf: []u8) usize {
    if (buf.len == 0) return 0;
    const cap: c_uint = @intCast(@min(buf.len, std.math.maxInt(c_uint)));
    const rc = win._read(fd, buf.ptr, cap);
    if (rc <= 0) return 0;
    return @intCast(rc);
}

fn winWrite(fd: c_int, bytes: []const u8) void {
    var written: usize = 0;
    while (written < bytes.len) {
        const chunk: c_uint = @intCast(@min(bytes.len - written, std.math.maxInt(c_uint)));
        const rc = win._write(fd, bytes.ptr + written, chunk);
        if (rc <= 0) return;
        written += @intCast(rc);
    }
}

fn winOpen(alloc: std.mem.Allocator, path: []const u8) !c_int {
    const units = try std.unicode.calcUtf16LeLen(path);
    const wide = try alloc.allocSentinel(u16, units, 0);
    _ = try std.unicode.utf8ToUtf16Le(wide, path);

    const fd = win._wopen(wide, win.o_rdonly | win.o_binary);
    if (fd >= 0) return fd;
    return switch (win._errno().*) {
        2 => error.FileNotFound,
        13 => error.AccessDenied,
        5 => error.AccessDenied,
        else => error.Unexpected,
    };
}

// ---------------------------------------------------------------------------
// Shared interface
// ---------------------------------------------------------------------------

/// Per-process setup. Windows needs its standard streams switched to binary
/// mode so program output is not line-ending translated; elsewhere this does
/// nothing.
pub fn init() void {
    if (is_windows) {
        _ = win._setmode(streamFd(.in), win.o_binary);
        _ = win._setmode(streamFd(.out), win.o_binary);
        _ = win._setmode(streamFd(.err), win.o_binary);
    }
}

/// Reads up to `buf.len` bytes. Returns 0 at end of file or on a read error;
/// interrupted reads are retried.
pub fn read(stream: Std, buf: []u8) usize {
    if (is_linux) return linuxRead(streamFd(stream), buf);
    if (is_windows) return winRead(streamFd(stream), buf);
    return darwinRead(streamFd(stream), buf);
}

/// Writes all of `bytes`, retrying short writes. Output is best effort: a
/// closed pipe or a hard error ends the write instead of aborting.
pub fn write(stream: Std, bytes: []const u8) void {
    if (is_linux) return linuxWrite(streamFd(stream), bytes);
    if (is_windows) return winWrite(streamFd(stream), bytes);
    darwinWrite(streamFd(stream), bytes);
}

/// Opens a program file read-only. The allocator is only used on Windows,
/// where the path is transcoded to UTF-16.
pub fn openReadOnly(alloc: std.mem.Allocator, path: []const u8) !Source {
    if (is_windows) return winOpen(alloc, path);
    return std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0);
}

pub fn readSource(src: Source, buf: []u8) usize {
    if (is_linux) return linuxRead(src, buf);
    if (is_windows) return winRead(src, buf);
    return darwinRead(src, buf);
}

pub fn closeSource(src: Source) void {
    if (is_linux) {
        _ = linux.close(src);
        return;
    }
    if (is_windows) {
        _ = win._close(src);
        return;
    }
    _ = darwin.close(src);
}
