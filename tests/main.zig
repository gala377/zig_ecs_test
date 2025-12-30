const std = @import("std");
const ecs = @import("ecs");

test "system tests" {
    std.testing.refAllDecls(@import("system.zig"));
}
