const std = @import("std");

const system = @import("system.zig");
const System = system.System;
const Game = @import("game.zig").Game;

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

setup_systems: std.ArrayList(System),

update_systems: std.ArrayList(System),
post_update_systems: std.ArrayList(System),

pre_render_systems: std.ArrayList(System),
render_systems: std.ArrayList(System),
post_render_systems: std.ArrayList(System),

tear_down_systems: std.ArrayList(System),

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .setup_systems = .empty,
        .update_systems = .empty,
        .post_update_systems = .empty,
        .pre_render_systems = .empty,
        .render_systems = .empty,
        .post_render_systems = .empty,
        .tear_down_systems = .empty,
        .allocator = allocator,
    };
}

pub fn add(self: *Self, phase: Phase, sys: System) !void {
    const schedule = self.getSystems(phase);
    try schedule.append(self.allocator, sys);
}

pub fn runPhase(self: *Self, phase: Phase, game: *Game) void {
    const schedule = self.getSystems(phase);
    for (schedule.items) |sys| {
        sys.run(game);
    }
}
pub fn deinitPhase(self: *Self, phase: Phase) void {
    const systems = self.getSystems(phase);
    for (systems.items) |sys| {
        sys.deinit();
    }
    systems.deinit(self.allocator);
}

fn getSystems(self: *Self, phase: Phase) *std.ArrayList(System) {
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
