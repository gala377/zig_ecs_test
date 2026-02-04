const std = @import("std");
const zgui = @import("zgui");
const rl = @import("raylib");

// Import the C glue
const ri = @cImport({
    @cInclude("rlImGui.h");
});

const ecs = @import("../prelude.zig");
const Game = ecs.Game;
const Resource = ecs.Resource;
const GlobalAllocator = ecs.runtime.allocators.GlobalAllocator;
const RaylibSchedule = ecs.raylib.RaylibSchedule;

const ZguiSchedule = struct {};

const editor = @import("editor.zig");

pub fn install(game: *Game) !void {
    try game.schedule.addScheduleAfter(
        .setup,
        ZguiSchedule{},
        .{RaylibSchedule{}},
    );
    try game.schedule.addScheduleAfter(
        .pre_render,
        ZguiSchedule{},
        .{RaylibSchedule{}},
    );
    try game.schedule.addScheduleBefore(
        .post_render,
        ZguiSchedule{},
        .{RaylibSchedule{}},
    );
    try game.schedule.addScheduleBefore(
        .tear_down,
        ZguiSchedule{},
        .{RaylibSchedule{}},
    );
    try game.schedule.addScheduleAfter(.close, ZguiSchedule{}, .{});
    try game.addSystemToSchedule(.setup, ZguiSchedule{}, initZgui);
    //try game.addSystemToSchedule(.tear_down, ZguiSchedule{}, deinitZgui);
    try game.addSystemToSchedule(.pre_render, ZguiSchedule{}, zguiBegin);
    try game.addSystemToSchedule(.post_render, ZguiSchedule{}, zguiEnd);
    try game.addSystemToSchedule(.close, ZguiSchedule{}, deinitZgui);
    try game.addSystem(.render, editor.allEntities);
    try game.addSystem(.render, editor.allSystems);
}

fn zguiBegin() void {
    ri.rlImGuiBegin();
}

fn zguiEnd() void {
    ri.rlImGuiEnd();
}

fn initZgui(allocator: Resource(GlobalAllocator)) void {
    ri.rlImGuiSetup(true);
    const context = ri.rlGetCurrentContext() orelse @panic("context is null");
    zgui.initWithExistingContext(allocator.get().allocator, @ptrCast(@alignCast(context)));
    _ = zgui.io.addFontDefault(null);
}

fn deinitZgui() void {
    zgui.deinit();
}
