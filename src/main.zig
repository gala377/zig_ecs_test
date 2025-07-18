const std = @import("std");
const lua = @import("lua_lib");
const Game = @import("game.zig").Game;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
        .retain_metadata = true,
    }).init;
    defer {
        switch (gpa.deinit()) {
            .leak => {
                std.debug.print("Leaks found!\n", .{});
            },
            else => {
                std.debug.print("no leaks found\n", .{});
            },
        }
    }
    var game = try Game.init(gpa.allocator(), .{ .window = .{ .targetFps = 60, .title = "Hello?", .size = .{
        .width = 1080,
        .height = 720,
    } } });
    defer game.deinit();
    try game.run();
}
