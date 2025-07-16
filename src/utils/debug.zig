const std = @import("std");

pub inline fn println(comptime format: []const u8, args: anytype) void {
    println_impl(format, args) catch |err| {
        std.debug.panic("error {any}", .{err});
    };
}

inline fn println_impl(comptime format: []const u8, args: anytype) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print(format, args);
    try stdout.writeByte('\n');
    try bw.flush(); // Don't forget to flush!
}
