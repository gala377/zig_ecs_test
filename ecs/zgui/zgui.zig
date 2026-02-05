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
const ZguiDockSpaceSchedule = struct {};

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
    try game.schedule.addScheduleAfter(.pre_render, ZguiDockSpaceSchedule{}, .{
        ZguiSchedule{},
    });
    try game.schedule.addScheduleBefore(
        .post_render,
        ZguiDockSpaceSchedule{},
        .{ZguiSchedule{}},
    );
    try game.addSystemToSchedule(.setup, ZguiSchedule{}, initZgui);
    //try game.addSystemToSchedule(.tear_down, ZguiSchedule{}, deinitZgui);
    try game.addSystemToSchedule(.pre_render, ZguiSchedule{}, zguiBegin);
    try game.addSystemToSchedule(.post_render, ZguiSchedule{}, zguiEnd);
    try game.addSystemToSchedule(.close, ZguiSchedule{}, deinitZgui);
    try game.addSystemToSchedule(.pre_render, ZguiDockSpaceSchedule{}, zguiDockSpace);
    try game.addSystemToSchedule(.post_render, ZguiDockSpaceSchedule{}, zguiDockSpaceEnd);

    try game.addResource(editor.EntityDetailsView.init(game.allocator));
    try game.addSystem(.render, editor.allEntities);
    try game.addSystem(.render, editor.allSystems);
    try game.addSystem(.render, editor.showEntityDetails);
}

fn zguiBegin() void {
    ri.rlImGuiBegin();
}

fn zguiEnd() void {
    ri.rlImGuiEnd();
}

fn zguiDockSpace() void {
    const viewport = zgui.getMainViewport();

    // 1. Position the window to match the main viewport
    zgui.setNextWindowPos(.{ .x = viewport.pos[0], .y = viewport.pos[1] });
    zgui.setNextWindowSize(.{ .w = viewport.size[0], .h = viewport.size[1] });
    zgui.setNextWindowViewport(viewport.id);
    const window_flags: zgui.WindowFlags = .{
        .no_docking = true,
        .no_title_bar = true,
        .no_collapse = true,
        .no_resize = true,
        .no_move = true,
        .no_bring_to_front_on_focus = true,
        .no_nav_focus = true,
        .no_background = true,
    };
    zgui.pushStyleVar1f(.{ .idx = .window_rounding, .v = 0.0 });
    zgui.pushStyleVar1f(.{ .idx = .window_border_size, .v = 0.0 });
    zgui.pushStyleVar2f(.{ .idx = .window_padding, .v = .{ 0.0, 0.0 } });
    _ = zgui.begin("MyMainDockSpace", .{ .flags = window_flags });
    zgui.popStyleVar(.{ .count = 3 });
    _ = zgui.dockSpace("MainDockSpace", .{ 0.0, 0.0 }, .{ .passthru_central_node = true });
}

fn zguiDockSpaceEnd() void {
    zgui.end();
}

fn initZgui(allocator: Resource(GlobalAllocator)) void {
    ri.rlImGuiSetup(true);
    const context = ri.rlGetCurrentContext() orelse @panic("context is null");
    zgui.initWithExistingContext(allocator.get().allocator, @ptrCast(@alignCast(context)));
    _ = zgui.io.addFontDefault(null);
    zgui.io.setConfigFlags(.{ .dock_enable = true });
}

fn deinitZgui() void {
    zgui.deinit();
}
