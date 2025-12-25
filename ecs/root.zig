pub const component = @import("component.zig");
pub const Component = component.Component;
pub const ExportLua = component.ExportLua;

pub const entity = @import("entity.zig");

pub const game = @import("game.zig");
pub const Game = game.Game;
pub const Query = game.Query;

pub const imgui = @import("imgui/root.zig");

pub const scene = @import("scene.zig");
pub const Scene = scene.Scene;
pub const EntityId = entity.EntityId;

pub const system = @import("system.zig").system;

pub const utils = @import("utils.zig");

pub const DeclarationGenerator = @import("declaration_generator.zig");
pub const Resource = @import("resource.zig").Resource;
pub const Commands = @import("runtime/commands.zig").Commands;
pub const commands = @import("runtime/commands.zig");
pub const runtime = @import("runtime/root.zig");

pub const shapes = @import("shapes/root.zig");
pub const core = @import("core/root.zig");
pub const lua_script = @import("lua_script.zig");
