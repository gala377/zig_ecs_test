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
    try game.addLabeledSystemToSchedule(.setup, ZguiSchedule{}, "ecs.zgui.initZgui", initZgui);
    try game.addLabeledSystemToSchedule(.pre_render, ZguiSchedule{}, "ecs.zgui.zguiBegin", zguiBegin);
    try game.addLabeledSystemToSchedule(.post_render, ZguiSchedule{}, "ecs.zgui.zguiEnd", zguiEnd);
    try game.addLabeledSystemToSchedule(.close, ZguiSchedule{}, "ecs.zgui.deinitZgui", deinitZgui);
    try game.addLabeledSystemToSchedule(.pre_render, ZguiDockSpaceSchedule{}, "ecs.zgui.zguiDockSpace", zguiDockSpace);
    try game.addLabeledSystemToSchedule(.post_render, ZguiDockSpaceSchedule{}, "ecs.zgui.zguiDockSpaceEnd", zguiDockSpaceEnd);

    try game.addResource(try editor.PrimiteTypeStorage.init(game.allocator));
    try game.type_registry.registerType(editor.EntityDetailsView);
    try game.type_registry.registerType(WindowSize);

    try game.addSystems(.render, &.{
        ecs.system.labeledSystem("ecs.zgui.editor.allEntities", editor.allEntities),
        ecs.system.labeledSystem("ecs.zgui.editor.allSystems", editor.allSystems),
        ecs.system.labeledSystem("ecs.zgui.editor.showEntityDetails", editor.showEntityDetails),
        ecs.system.labeledSystem("ecs.zgui.editor.allResources", editor.allResources),
        ecs.system.labeledSystem("ecs.zgui.editor.printPhaseTimes", editor.printPhaseTimes),
        ecs.system.labeledSystem("ecs.zgui.editor.plotSystems", editor.plotSystems),
        ecs.system.labeledSystem("ecs.zgui.editor.luaMemoryUsage", editor.luaMemoryUsage),
    });
    try game.addResource(WindowSize{ .width = 0, .height = 0, .changed = false });
    try game.addLabeledSystemToSchedule(.pre_render, ZguiSchedule{}, "ecs.zgui.updatewindowSize", WindowSize.update);
}

fn zguiBegin() void {
    ri.rlImGuiBegin();
}

fn zguiEnd() void {
    ri.rlImGuiEnd();
}

fn zguiDockSpace(window: Resource(WindowSize)) void {
    _ = window;
    // 1. Position the window to match the main viewport
    const viewport = zgui.getMainViewport();
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
        .always_auto_resize = true,
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
    ri.rlImGuiBeginInitImGui();
    // ri.rlImGuiSetup(true);
    zgui.initNoContext(allocator.inner.allocator);
    _ = zgui.io.addFontDefault(null);
    zgui.io.setConfigFlags(.{
        .dock_enable = true,
        .viewport_enable = true,
        .dpi_enable_scale_viewport = true,
        .dpi_enable_scale_fonts = true,
    });
    //zgui.io.setDisplayFramebufferScale(rl.getWindowScaleDPI().x, rl.getWindowScaleDPI().y);
    zgui.plot.init();
    ri.rlImGuiEndInitImGui();
}

fn deinitZgui() void {
    zgui.plot.deinit();
    zgui.deinitNoContext();
}

pub const WindowSize = struct {
    pub const component_info = ecs.Component(WindowSize);

    width: i32,
    height: i32,
    changed: bool = false,

    pub fn update(self: Resource(WindowSize)) void {
        const h = rl.getScreenHeight();
        const w = rl.getScreenWidth();
        if (self.inner.height != h or self.inner.width != w) {
            self.inner.height = h;
            self.inner.width = w;
            self.inner.changed = true;
        } else {
            self.inner.changed = false;
        }
    }
};
