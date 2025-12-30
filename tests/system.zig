const std = @import("std");
const ecs = @import("ecs");

fn Result(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const component_info = ecs.Component(Self);
        res: T,
    };
}

fn modify_result(res: ecs.Resource(Result(bool))) void {
    res.get().res = true;
}

test "running system executes it" {
    const allocator = std.testing.allocator;
    var game = try ecs.Game.init(allocator, .{ .window = .{
        .title = "test",
        .size = .{ .height = 0, .width = 0 },
    } });
    defer game.deinit();
    try game.addResource(Result(bool){ .res = false });
    try game.addSystem(.update, modify_result);
    try game.runHeadlessOnce();
    const resource = game.getResource(Result(bool));
    const result = resource.get().res;
    try std.testing.expect(result);
}
