const std = @import("std");
const ecs = @import("../prelude.zig");

fn noop(_: *anyopaque, _: std.mem.Allocator) void {}

fn generic_free(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) void {
    return &struct {
        fn free(ptr: *anyopaque, allocator: std.mem.Allocator) void {
            const c: *T = @ptrCast(@alignCast(ptr));
            allocator.destroy(c);
        }
    }.free;
}

pub const ScheduledSystem = struct {
    const Self = @This();

    system: ecs.system.System,
    alloctor: std.mem.Allocator,

    args: ?*anyopaque = null,
    args_free: *const fn (*anyopaque, std.mem.Allocator) void,
    args_deinit: *const fn (*anyopaque, std.mem.Allocator) void = &noop,

    pub fn init(
        system: ecs.system.System,
        args: anytype,
        allocator: std.mem.Allocator,
    ) !Self {
        const Args = @TypeOf(args);
        const allocated = try allocator.create(Args);
        if (std.meta.hasMethod(Args, "deinit")) {
            @panic("we don't support deinit yet");
        }
        var new = initVoid(system, allocator);
        new.args = @ptrCast(@alignCast(allocated));
        new.args_free = generic_free(Args);
        return new;
    }

    pub fn initVoid(
        system: ecs.system.System,
        allocator: std.mem.Allocator,
    ) Self {
        return .{
            .system = system,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.system.deinit();
        if (self.args) |args| {
            self.args_deinit(args, self.alloctor);
            self.args_free(self.args, self.alloctor);
        }
    }
};

pub const OneShotScheduler = struct {
    const Self = @This();

    systems: std.ArrayList(ScheduledSystem) = .empty,
    allocator: std.mem.Allocator,

    pub fn clear(self: *Self) void {
        for (self.systems.items) |sys| {
            sys.deinit();
        }
        self.systems.clearRetainingCapacity();
    }

    pub fn scheduled(self: *Self) []ScheduledSystem {
        return self.systems.items;
    }

    pub fn deinit(self: *Self) void {
        self.clear();
        self.systems.deinit(self.allocator);
    }
};
