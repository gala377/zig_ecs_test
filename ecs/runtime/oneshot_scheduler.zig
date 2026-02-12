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

pub const OneShotSchedule = struct {};

pub const ScheduledSystem = struct {
    const Self = @This();

    system: ecs.system.System,
    allocator: std.mem.Allocator,
    phase: ?ecs.Schedule.Phase = null,

    run: bool = false,

    args: ?*anyopaque = null,
    args_free: *const fn (*anyopaque, std.mem.Allocator) void = &noop,
    args_deinit: *const fn (*anyopaque, std.mem.Allocator) void = &noop,

    pub fn initArgs(
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
            self.args_deinit(args, self.allocator);
            self.args_free(args, self.allocator);
        }
    }
};

pub const OneShotScheduler = struct {
    const Self = @This();
    pub const component_info = ecs.Component(Self);

    systems: std.ArrayList(ScheduledSystem) = .empty,
    freelist: std.AutoHashMap(usize, void),
    allocator: std.mem.Allocator,
    system_registry: *ecs.SystemsRegistry,

    pub fn init(allocator: std.mem.Allocator, system_registry: *ecs.SystemsRegistry) Self {
        return .{
            .allocator = allocator,
            .freelist = .init(allocator),
            .system_registry = system_registry,
        };
    }

    pub fn runByName(self: *Self, phase: ecs.Schedule.Phase, sys: []const u8) !void {
        const s = self.system_registry.getByName(sys) orelse {
            return error.systemNotRegistered;
        };
        return self.run(phase, s);
    }

    pub fn run(self: *Self, phase: ecs.Schedule.Phase, sys: ecs.System) !void {
        var defered = ScheduledSystem.initVoid(sys, self.allocator);
        defered.phase = phase;
        return self.systems.append(
            self.allocator,
            defered,
        );
    }

    fn put(self: *Self, system: ScheduledSystem) !usize {
        var keys = self.freelist.keyIterator();
        if (keys.next()) |key| {
            const index = key.*;
            self.freelist.remove(index);
            self.systems[index] = system;
            return index;
        } else {
            const index = self.systems.items.len;
            try self.systems.append(self.allocator, system);
            return index;
        }
    }

    pub fn clear(self: *Self) void {
        for (self.systems.items) |*sys| {
            // TODO: args free?
            sys.deinit();
        }
        self.systems.clearRetainingCapacity();
    }

    pub fn deinit(self: *Self) void {
        self.clear();
        self.systems.deinit(self.allocator);
        self.freelist.deinit();
    }
};

pub fn install(game: *ecs.Game) !void {
    try game.addResource(OneShotScheduler.init(
        game.allocator,
        &game.systems_registry,
    ));
    try game.addSystems(.setup, &.{
        ecs.system.labeledSystem("initOneShotScheduler", installScheduler),
    });
    try game.type_registry.registerType(OneShotScheduler);
    try game.type_registry.registerType(ScheduledSystem);
}

fn installScheduler(game: *ecs.Game) !void {
    inline for (@typeInfo(ecs.Schedule.Phase).@"enum".fields) |f| {
        try game.schedule.addScheduleAfter(
            @enumFromInt(f.value),
            OneShotSchedule{},
            .{},
        );
        try game.schedule.addToSchedule(
            @enumFromInt(f.value),
            OneShotSchedule{},
            oneShotRunner(@enumFromInt(f.value)),
        );
    }
}

fn oneShotRunner(comptime phase: ecs.Schedule.Phase) ecs.System {
    const f = struct {
        fn run(game: *ecs.Game) anyerror!void {
            const runner = game.getResource(OneShotScheduler).get();
            const systems = runner.systems.items;
            for (systems, 0..) |*system, index| {
                if (system.run) {
                    continue;
                }
                if (system.phase) |system_phase| {
                    if (system_phase != phase) {
                        continue;
                    }
                }
                system.run = true;
                try system.system.run(game);
                system.deinit();
                runner.freelist.put(index, void{}) catch @panic("oom");
            }
        }
    }.run;
    return ecs.system.labeledSystem(
        "ecs.runtime.oneShotRunner(" ++ @tagName(phase) ++ ")",
        f,
    );
}
