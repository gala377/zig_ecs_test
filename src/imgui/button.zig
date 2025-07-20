const lua = @import("lua_lib");
const rg = @import("raygui");
const rl = @import("raylib");
const std = @import("std");
const Game = @import("../game.zig").Game;

pub const Button = struct {
    pub const ScriptArgs = struct {
        callback: lua.Ref,
        title: [:0]const u8,
        size: struct { x: f32, y: f32 },
        position: struct { x: f32, y: f32 },

        pub fn deinit(self: ScriptArgs, allocator: std.mem.Allocator) void {
            self.callback.release();
            allocator.free(self.title);
        }
    };
    initArgs: ScriptArgs,
    game: *Game,

    pub fn run(self: *Button) !?lua.Value {
        const res = rg.button(rl.Rectangle.init(
            self.initArgs.position.x,
            self.initArgs.position.y,
            self.initArgs.size.x,
            self.initArgs.size.y,
        ), self.initArgs.title);
        if (res) {
            self.game.luaState.pushRef(self.initArgs.callback);
            self.game.luaState.call(0, 1, self.game.allocator);
        }
    }
};
