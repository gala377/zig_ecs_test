const std = @import("std");

const system = @import("system.zig");
const System = system.System;
const Game = @import("game.zig").Game;

const Self = @This();

pub const Phase = enum {
    setup,
    update,
    post_update,
    render,
    post_render,
    tear_down,
};

setup_systems: std.ArrayList(System),
update_systems: std.ArrayList(System),
post_update_systems: std.ArrayList(System),
render_systems: std.ArrayList(System),
post_render_systems: std.ArrayList(System),
tear_down_systems: std.ArrayList(System),

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .setup_systems = .empty,
        .update_systems = .empty,
        .post_update_systems = .empty,
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
        sys(game);
    }
}

fn getSystems(self: *Self, phase: Phase) *std.ArrayList(System) {
    return switch (phase) {
        .setup => &self.setup_systems,
        .update => &self.update_systems,
        .post_update => &self.post_update_systems,
        .render => &self.render_systems,
        .post_render => &self.post_render_systems,
        .tear_down => &self.tear_down_systems,
    };
}

pub fn deinit(self: *Self) void {
    self.setup_systems.deinit(self.allocator);
    self.update_systems.deinit(self.allocator);
    self.post_update_systems.deinit(self.allocator);
    self.render_systems.deinit(self.allocator);
    self.post_render_systems.deinit(self.allocator);
    self.tear_down_systems.deinit(self.allocator);
}
