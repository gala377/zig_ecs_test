const std = @import("std");

const system = @import("system.zig");
const System = system.System;
const Game = @import("game.zig").Game;
const utils = @import("utils.zig");

const Self = @This();

pub const Phase = enum {
    setup,
    update,
    post_update,
    pre_render,
    render,
    post_render,
    tear_down,
};

pub const DefaultSchedule = struct {};

pub const ScheduleId = usize;

pub const Schedule = struct {
    identifier: ScheduleId,
    systems: std.ArrayList(System),

    pub fn run(self: *const @This(), game: *Game) void {
        for (self.systems.items) |s| {
            s.run(game);
        }
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (self.systems.items) |sys| {
            sys.deinit();
        }
        self.systems.deinit(allocator);
    }
};

setup_systems: std.ArrayList(Schedule),

update_systems: std.ArrayList(Schedule),
post_update_systems: std.ArrayList(Schedule),

pre_render_systems: std.ArrayList(Schedule),
render_systems: std.ArrayList(Schedule),
post_render_systems: std.ArrayList(Schedule),

tear_down_systems: std.ArrayList(Schedule),

allocator: std.mem.Allocator,
id_provider: utils.IdProvider,

pub fn init(allocator: std.mem.Allocator, id_provider: utils.IdProvider) Self {
    return .{
        .setup_systems = .empty,
        .update_systems = .empty,
        .post_update_systems = .empty,
        .pre_render_systems = .empty,
        .render_systems = .empty,
        .post_render_systems = .empty,
        .tear_down_systems = .empty,
        .allocator = allocator,
        .id_provider = id_provider,
    };
}

pub fn addDefaultSchedule(self: *Self) !void {
    std.debug.print("adding default schedules\n", .{});
    inline for (@typeInfo(Phase).@"enum".fields) |f| {
        try self.addSchedule(@enumFromInt(f.value), DefaultSchedule{}, .{});
    }
}

pub fn addSchedule(self: *Self, phase: Phase, label: anytype, after: anytype) !void {
    const after_info = @typeInfo(@TypeOf(after));
    const fields = after_info.@"struct".fields;
    var after_ids: [fields.len]ScheduleId = undefined;
    inline for (after, 0..) |schedule, idx| {
        after_ids[idx] = utils.dynamicTypeId(@TypeOf(schedule), self.id_provider);
    }
    const phase_schedules = self.getPhase(phase);
    var max: ?usize = null;
    for (phase_schedules.items, 0..) |*schedule, idx| {
        for (after_ids) |schedule_id| {
            if (schedule_id == schedule.identifier) {
                if (max) |inner| {
                    max = @max(inner, idx);
                } else {
                    max = idx;
                }
            }
        }
    }
    const new_schedule = Schedule{
        .identifier = utils.dynamicTypeId(@TypeOf(label), self.id_provider),
        .systems = .empty,
    };
    std.debug.print("created schedule {s} with id {any}\n", .{
        @typeName(@TypeOf(label)), new_schedule.identifier,
    });
    if (max) |inner| {
        try phase_schedules.insert(self.allocator, inner + 1, new_schedule);
    } else {
        // we can put it anywhere
        try phase_schedules.append(self.allocator, new_schedule);
    }
}

pub fn getSchedule(self: *Self, phase: Phase, schedule: anytype) !*Schedule {
    const schedules = self.getPhase(phase);
    const id = utils.dynamicTypeId(@TypeOf(schedule), self.id_provider);
    std.debug.print("looking for schedule {s} with id {any}\n", .{
        @typeName(@TypeOf(schedule)), id,
    });
    for (schedules.items) |*s| {
        if (s.identifier == id) {
            return s;
        }
    }
    return error.scheduleDoesNotExist;
}

pub fn addToSchedule(self: *Self, phase: Phase, schedule: anytype, sys: System) !void {
    const s = try self.getSchedule(phase, schedule);
    try s.systems.append(self.allocator, sys);
}

pub fn add(self: *Self, phase: Phase, sys: System) !void {
    try self.addToSchedule(phase, DefaultSchedule{}, sys);
}

pub fn runPhase(self: *Self, phase: Phase, game: *Game) void {
    const schedule = self.getPhase(phase);
    for (schedule.items) |s| {
        s.run(game);
    }
}
pub fn deinitPhase(self: *Self, phase: Phase) void {
    const systems = self.getPhase(phase);
    for (systems.items) |*sys| {
        sys.deinit(self.allocator);
    }
    systems.deinit(self.allocator);
}

fn getPhase(self: *Self, phase: Phase) *std.ArrayList(Schedule) {
    return switch (phase) {
        .setup => &self.setup_systems,
        .update => &self.update_systems,
        .post_update => &self.post_update_systems,
        .pre_render => &self.pre_render_systems,
        .render => &self.render_systems,
        .post_render => &self.post_render_systems,
        .tear_down => &self.tear_down_systems,
    };
}

pub fn deinit(self: *Self) void {
    inline for (@typeInfo(Phase).@"enum".fields) |f| {
        self.deinitPhase(@enumFromInt(f.value));
    }
}
