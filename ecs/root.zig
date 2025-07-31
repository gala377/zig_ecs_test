pub const component = @import("component.zig");
pub const Component = component.Component;

pub const entity = @import("entity.zig");

pub const game = @import("game.zig");
pub const Game = game.Game;
pub const Query = game.Query;

pub const imgui = @import("imgui/root.zig");

pub const scene = @import("scene.zig");
pub const Scene = scene.Scene;
pub const EntityId = scene.EntityId;

pub const system = @import("system.zig").system;

pub const utils = @import("utils.zig");

pub const DeclarationGenerator = @import("declaration_generator.zig");
pub const Resource = @import("resource.zig").Resource;
