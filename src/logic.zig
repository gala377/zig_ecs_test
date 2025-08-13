const std = @import("std");

const ecs = @import("ecs");
const lua = @import("lua_lib");

const Component = ecs.Component;
const Game = ecs.Game;
const GameActions = ecs.runtime.components.GameActions;
const LuaRuntime = ecs.runtime.components.LuaRuntime;
const Query = ecs.Query;
const system = ecs.system;
const imgui = ecs.imgui;
const Button = imgui.components.Button;
const Vec2 = ecs.utils.Vec2;
const Resource = ecs.Resource;
const ExportLua = ecs.component.ExportLua;
const scene = ecs.scene;
const Commands = ecs.Commands;
const EntityId = ecs.EntityId;

pub fn installMainLogic(game: *Game) !void {
    try game.addSystems(.{
        system(print_on_button),
        system(call_ref),
        system(spawn_on_click),
        system(read_new_entities),
        system(remove_last_entity),
    });
    game.exportComponent(ButtonOpen);
    game.exportComponent(ButtonClose);
    try game.addLuaSystems("scripts/systems.lua");

    const ref = try game.luaLoad(
        \\ return function(button)
        \\  print("visible = " .. tostring(button.visible));
        \\  if button.visible then
        \\    button.visible = false;
        \\  end
        \\ end
    );

    const open_title: [:0]u8 = try game.allocator.dupeZ(u8, "Open");
    const close_title: [:0]u8 = try game.allocator.dupeZ(u8, "Close");
    const lua_title: [:0]u8 = try game.allocator.dupeZ(u8, "Lua Callback");
    const spawn_title: [:0]u8 = try game.allocator.dupeZ(u8, "Spawn Title");
    const remove_last_title: [:0]u8 = try game.allocator.dupeZ(u8, "Remove last title");

    const buttons_size = Vec2{ .x = 100.0, .y = 25.0 };
    const position = Vec2{ .x = 50.0, .y = 50.0 };
    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position,
            .size = buttons_size,
            .title = @ptrCast(open_title),
            .allocator = game.allocator,
        },
        ButtonOpen{},
    });
    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position.add_y(buttons_size.y),
            .size = buttons_size,
            .title = @ptrCast(close_title),
            .visible = false,
            .allocator = game.allocator,
        },
        ButtonClose{},
    });

    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position.add_y(buttons_size.y * 2),
            .size = buttons_size,
            .title = @ptrCast(lua_title),
            .allocator = game.allocator,
        },
        ButtonLua{
            .callback = ref,
        },
    });

    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position.add_y(buttons_size.y * 3),
            .size = buttons_size,
            .title = @ptrCast(spawn_title),
            .allocator = game.allocator,
        },
        ButtonSpawn{},
    });

    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position.add_y(buttons_size.y * 4),
            .size = buttons_size,
            .title = @ptrCast(remove_last_title),
            .allocator = game.allocator,
        },
        ButtonRemoveLast{},
    });
}

pub const TestItem = struct {
    pub usingnamespace Component(TestItem);

    index: usize,
    already_logged: bool = false,
};

pub fn spawn_on_click(commands: Commands, buttons: *Query(.{ Button, ButtonSpawn }), entities: *Query(.{TestItem})) void {
    const button: *Button, _ = buttons.single();
    const cmd: *ecs.commands = commands.get();
    if (button.clicked) {
        var max: usize = 0;
        while (entities.next()) |ent| {
            const test_item: *TestItem = ent[0];
            if (test_item.index > max) {
                max = test_item.index;
            }
        }
        const next_index = max + 1;
        _ = cmd.newSceneEntity(.{TestItem{
            .index = next_index,
        }}) catch @panic("could not make new scene entity");
    }
}

pub fn read_new_entities(entities: *Query(.{TestItem})) void {
    var index: usize = 0;
    while (entities.next()) |e| : (index += 1) {
        var entity: *TestItem = e[0];
        if (!entity.already_logged) {
            entity.already_logged = true;
            std.debug.print("Saw new entity {}\n", .{entity.index});
        }
    }
}

pub fn remove_last_entity(commands: Commands, buttons: *Query(.{ Button, ButtonRemoveLast }), entities: *Query(.{ EntityId, TestItem })) void {
    const button: *Button, _ = buttons.single();
    if (button.clicked) {
        var last: ?EntityId = null;
        var max: usize = 0;
        while (entities.next()) |pack| {
            const entity: *EntityId, const item: *TestItem = pack;
            if (item.index >= max) {
                max = item.index;
                last = entity.*;
            }
        }
        if (last) |id| {
            commands.get().removeEntity(id) catch @panic("oom");
        }
    }
}

pub const ButtonSpawn = struct {
    pub usingnamespace Component(ButtonSpawn);
};

pub const ButtonOpen = struct {
    pub usingnamespace Component(ButtonOpen);
    pub usingnamespace ExportLua(ButtonOpen, .{});
};

pub const ButtonClose = struct {
    pub usingnamespace Component(ButtonClose);
    pub usingnamespace ExportLua(ButtonClose, .{});
};

pub const ButtonRemoveLast = struct {
    pub usingnamespace Component(ButtonRemoveLast);
};

const ButtonLua = struct {
    pub usingnamespace Component(ButtonLua);
    callback: lua.Ref,

    pub fn deinit(self: *ButtonLua) void {
        self.callback.release();
    }
};

fn print_on_button(
    iter: *Query(.{ Button, ButtonOpen }),
    close_iter: *Query(.{ Button, ButtonClose }),
) void {
    const button, _ = iter.single();
    if (button.clicked) {
        const close_button, _ = close_iter.single();
        close_button.visible = !close_button.visible;
    }
}

fn close_on_button(
    game_actions: Resource(GameActions),
    iter: *Query(.{ Button, ButtonClose }),
) void {
    const button, _ = iter.single();
    if (button.clicked) {
        game_actions.get().should_close = true;
    }
}

fn call_ref(
    state: Resource(LuaRuntime),
    lua_button: *Query(.{ Button, ButtonLua }),
    close_button: *Query(.{ Button, ButtonClose }),
) void {
    const lua_btn: *Button, const lua_clb: *ButtonLua = lua_button.single();
    if (lua_btn.clicked) {
        const lstate: *lua.State = state.get().lua;
        const cls_btn: *Button, _ = close_button.single();

        lstate.pushRef(lua_clb.callback);
        cls_btn.luaPush(lstate.state);

        lstate.callDontPop(1, 1);
        lstate.pop() catch {};
    }
}
