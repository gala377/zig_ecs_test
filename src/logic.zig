const std = @import("std");

const ecs = @import("ecs");
const lua = @import("lua_lib");

const Component = ecs.Component;
const Game = ecs.Game;
const GameActions = ecs.runtime.game_actions;
const LuaRuntime = ecs.runtime.lua_runtime;
const EventReader = ecs.runtime.events.EventReader;
const EventWriter = ecs.runtime.events.EventWriter;
const Query = ecs.Query;
const system = ecs.system;
const imgui = ecs.imgui;
const Button = imgui.components.Button;
const Vec2 = ecs.core.Vec2;
const Resource = ecs.Resource;
const ExportLua = ecs.ExportLua;
const scene = ecs.scene;
const Commands = ecs.Commands;
const EntityId = ecs.EntityId;
const Without = ecs.game.Without;
const lua_script = ecs.lua_script;
const Marker = ecs.Marker;
const GameAllocator = ecs.runtime.allocators.GlobalAllocator;

pub fn install(game: *Game) !void {
    std.debug.print("adding systems\n", .{});
    try game.addSystems(.update, &.{
        system(print_on_button),
        system(call_ref),
        system(spawn_on_click),
        system(read_new_entities),
        system(remove_last_entity),
        system(read_events),
        system(move_player_marker),
        system(spawn_circle),
        system(add_player),
    });
    try game.addSystems(.setup, &.{
        system(setup_circle),
    });
    try game.addSystem(.post_update, finish_run);

    std.debug.print("adding resources\n", .{});
    try game.addResource(RunOnce{});

    std.debug.print("exporting components\n", .{});
    game.exportComponent(ButtonOpen);
    game.exportComponent(ButtonClose);
    game.exportComponent(Bar);
    game.exportComponent(Foo);

    std.debug.print("adding lua systems\n", .{});
    try game.addLuaSystems(.update, "scripts/systems.lua");

    std.debug.print("adding lua callback\n", .{});
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

    std.debug.print("adding entities\n", .{});
    const buttons_size = Vec2{ .x = 100.0, .y = 25.0 };
    const position = Vec2{ .x = 50.0, .y = 50.0 };
    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position,
            .size = buttons_size,
            .title = @ptrCast(open_title),
        },
        ButtonOpen{},
    });
    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position.add_y(buttons_size.y),
            .size = buttons_size,
            .title = @ptrCast(close_title),
            .visible = false,
        },
        ButtonClose{},
    });

    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position.add_y(buttons_size.y * 2),
            .size = buttons_size,
            .title = @ptrCast(lua_title),
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
        },
        ButtonSpawn{},
    });

    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position.add_y(buttons_size.y * 4),
            .size = buttons_size,
            .title = @ptrCast(remove_last_title),
        },
        ButtonRemoveLast{},
    });

    const add_circle_title: [:0]u8 = try game.allocator.dupeZ(u8, "New circle");
    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position.add_y(buttons_size.y * 5),
            .size = buttons_size,
            .title = @ptrCast(add_circle_title),
        },
        ButtonAddCircle{},
    });

    const add_player_title: [:0]u8 = try game.allocator.dupeZ(u8, "Add player");
    _ = try game.newGlobalEntity(.{
        imgui.components.Button{
            .pos = position.add_y(buttons_size.y * 6),
            .size = buttons_size,
            .title = @ptrCast(add_player_title),
        },
        ButtonAddPlayer{},
    });

    const bar = try game.allocator.create(Bar);
    bar.* = .{ .x = 1, .y = 100 };
    const foo: Foo = .{
        .bar = bar,
    };
    _ = try game.newGlobalEntity(.{
        foo,
    });

    std.debug.print("adding event\n", .{});
    try game.addEvent(MyEvent);

    std.debug.print("adding lua script\n", .{});
    const object = try game.luaLoad(
        \\ local f = {}
        \\ function f:Init()
        \\   self.msg = "hello"
        \\   print("IN LUA IN LUA")
        \\   print("executed")
        \\   zig_yield("dispatch to zig: " .. self.msg)
        \\   print("past yield")
        \\   self.msg = "yoyoyo" 
        \\   self.counter = 0
        \\ end
        \\ function f:Update()
        \\  self.counter = self.counter + 1
        \\  if self.counter % 100 == 0 then
        \\    self.counter = 1
        \\    zig_yield(self.msg)
        \\  end
        \\ end
        \\ return f
    );
    const script = lua_script.LuaScript.fromLua(game.allocator, game.lua_state, object) catch @panic("could not create object");
    _ = try game.newGlobalEntity(.{
        script,
    });

    std.debug.print("adding more systems\n", .{});
    try lua_script.install(game);
    std.debug.print("done... running\n", .{});
    try game.addSystems(.setup, &.{
        try ecs.chain(game.allocator, &.{
            system(chain1),
            system(chain2),
            system(chain3),
        }),
    });
    try game.addSystems(.update, &.{
        system(spam_me).run_if(
            game.allocator,
            test_item_exists,
        ),
    });
}

pub const MyEvent = usize;

pub const TestItem = struct {
    pub const component_info = Component(TestItem);

    index: usize,
    already_logged: bool = false,
};

pub fn spawn_on_click(
    commands: Commands,
    buttons: *Query(.{ Button, ButtonSpawn }),
    entities: *Query(.{TestItem}),
) void {
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
        _ = cmd.addSceneEntity(.{TestItem{
            .index = next_index,
        }}) catch @panic("could not make new scene entity");
    }
}

pub fn test_item_exists(q: *Query(.{TestItem})) bool {
    return q.next() != null;
}

pub fn spam_me(q: *Query(.{TestItem})) void {
    _ = q;
    std.debug.print("spam\n", .{});
}

const NewCircle = struct {
    pub const component_info = Component(NewCircle);
    marker: Marker = .empty,
};

pub fn spawn_circle(commands: Commands, buttons: *Query(.{ Button, ButtonAddCircle })) void {
    const button, _ = buttons.single();
    const cmd: *ecs.commands = commands.get();
    if (button.clicked) {
        _ = cmd.addSceneEntity(.{ Circle{ .radius = 50.0 }, Position{ .x = 1080.0 / 2, .y = 720.0 / 2 }, Style{
            .background_color = Color.white,
        }, NewCircle{} }) catch @panic("could not spawn circle");
    }
}

pub fn add_player(
    commands: Commands,
    buttons: *Query(.{ Button, ButtonAddPlayer }),
    circles: *Query(.{ EntityId, Circle, Without(.{PlayerMarker}) }),
) void {
    const button, _ = buttons.single();
    const cmd: *ecs.commands = commands.get();
    if (button.clicked) {
        if (circles.next()) |c| {
            const id: EntityId = c[0].*;
            cmd.addComponents(id, .{PlayerMarker{}}) catch @panic("could not add component to entity");
        }
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

pub fn remove_last_entity(
    commands: Commands,
    buttons: *Query(.{ Button, ButtonRemoveLast }),
    entities: *Query(.{ EntityId, TestItem }),
    event: EventWriter(MyEvent),
) void {
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
            event.add(id.entity_id);
            commands.get().removeEntity(id) catch @panic("oom");
        }
    }
}

pub fn read_events(events: *EventReader(MyEvent)) void {
    while (events.next()) |e| {
        std.log.info("Got event that entity {} got removed", .{e});
    }
}

pub const ButtonSpawn = struct {
    pub const component_info = Component(ButtonSpawn);
    marker: Marker = .empty,
};

pub const ButtonOpen = struct {
    pub const component_info = Component(ButtonOpen);
    pub const lua_info = ExportLua(ButtonOpen, .{});
    marker: Marker = .empty,
};

pub const ButtonClose = struct {
    pub const component_info = Component(ButtonClose);
    pub const lua_info = ExportLua(ButtonClose, .{});
    marker: Marker = .empty,
};

pub const ButtonRemoveLast = struct {
    pub const component_info = Component(ButtonRemoveLast);
    marker: Marker = .empty,
};

pub const ButtonAddCircle = struct {
    pub const component_info = Component(ButtonAddCircle);
    marker: Marker = .empty,
};

pub const ButtonAddPlayer = struct {
    pub const component_info = Component(ButtonAddPlayer);
    marker: Marker = .empty,
};

const ButtonLua = struct {
    pub const component_info = Component(ButtonLua);
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
    game_allocator: Resource(GameAllocator),
    lua_button: *Query(.{ Button, ButtonLua }),
    close_button: *Query(.{ Button, ButtonClose }),
) void {
    const allocator = game_allocator.get().allocator;
    const lua_btn: *Button, const lua_clb: *ButtonLua = lua_button.single();
    if (lua_btn.clicked) {
        const lstate: *lua.State = state.get().lua;
        const cls_btn: *Button, _ = close_button.single();

        lstate.pushRef(lua_clb.callback);
        @TypeOf(@TypeOf(cls_btn.*).lua_info).luaPush(cls_btn, @ptrCast(lstate.state), allocator);

        lstate.callDontPop(1, 1);
        lstate.pop() catch {};
    }
}

const Circle = ecs.core.shapes.Circle;
const Color = ecs.core.Color;
const Style = ecs.core.Style;
const Position = ecs.core.Position;

pub const RunOnce = struct {
    pub const component_info = Component(RunOnce);
    already_run: bool = false,
};

pub const Foo = struct {
    pub const component_info = Component(Foo);
    pub const lua_info = ExportLua(Foo, .{});

    bar: *Bar,

    pub fn setBar(self: *Foo, bar: Bar, allocator: std.mem.Allocator) bool {
        _ = allocator;
        self.bar.* = bar;
        return true;
    }

    pub fn getX(self: *Foo) isize {
        return self.bar.x;
    }

    pub fn getY(self: *Foo) isize {
        return self.bar.y;
    }

    pub fn deinit(self: *Foo, allocator: std.mem.Allocator) void {
        allocator.destroy(self.bar);
    }
};

pub const Bar = struct {
    pub const component_info = Component(Bar);
    pub const lua_info = ExportLua(Bar, .{});

    x: isize,
    y: isize,
};

pub const PlayerMarker = struct {
    pub const component_info = Component(PlayerMarker);
    marker: Marker = .empty,
};

fn never_run(cond: Resource(RunOnce)) bool {
    return !cond.get().already_run;
}

fn setup_circle(commands: Commands) void {
    _ = commands.get().addSceneEntity(.{
        Circle{ .radius = 50.0 },
        Position{ .x = 1080.0 / 2, .y = 720.0 / 2 },
        Style{
            .background_color = Color{
                .a = 255,
                .r = 100,
                .b = 100,
                .g = 0,
            },
        },
        PlayerMarker{},
    }) catch @panic("failed to spawn entity");
}

fn move_player_marker(player: *Query(.{ PlayerMarker, Position })) void {
    while (player.next()) |components| {
        _, const position: *Position = components;
        position.x += 1.0;
    }
}

fn finish_run(cond: Resource(RunOnce)) void {
    cond.get().already_run = true;
}

fn chain1(cond: Resource(RunOnce)) void {
    _ = cond;
    std.debug.print("hello 1\n", .{});
}

fn chain2(cond: Resource(RunOnce)) void {
    _ = cond;
    std.debug.print("hello 2\n", .{});
}

fn chain3(cond: Resource(RunOnce)) void {
    _ = cond;
    std.debug.print("hello 3\n", .{});
}
