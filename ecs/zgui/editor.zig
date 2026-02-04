const std = @import("std");
const ecs = @import("../prelude.zig");
const zgui = @import("zgui");
const utils = ecs.utils;
const entity = ecs.entity;
const entity_storage = ecs.EntityStorage;

const Game = ecs.game.Game;

pub fn allEntities(game: *Game) void {
    if (!zgui.begin("entities", .{})) {
        return;
    }
    const type_registry = &game.type_registry;
    const scene_archetypes = game.current_scene.?.entity_storage.archetypes;
    const global_archetypes = game.global_entity_storage.archetypes;
    printFromArchetype(
        global_archetypes.items,
        game.allocator,
        type_registry,
        "global",
        0,
    );
    printFromArchetype(
        scene_archetypes.items,
        game.allocator,
        type_registry,
        "scene",
        @intCast(game.current_scene.?.id),
    );
    zgui.end();
}

fn printFromArchetype(
    archetypes: []const entity_storage.Archetype,
    allocator: std.mem.Allocator,
    type_registry: *ecs.TypeRegistry,
    label: []const u8,
    id: i32,
) void {
    const group_label = std.fmt.allocPrintSentinel(
        allocator,
        "{s}::{any}",
        .{ label, id },
        0,
    ) catch @panic("oom");
    defer allocator.free(group_label);
    if (zgui.collapsingHeader(group_label, .collapsing_header)) {
        for (archetypes) |*archetype| {
            for (0..archetype.capacity) |entity_index| {
                if (archetype.freelist.contains(entity_index)) {
                    continue;
                }
                var id_column_search: ?*entity_storage.ComponentColumn = null;
                for (archetype.components.items) |*column| {
                    if (column.component_id == utils.typeId(entity.Id)) {
                        id_column_search = column;
                        break;
                    }
                }
                const id_column = id_column_search orelse @panic("missing entity id");
                const entity_id: *const entity.Id = @ptrCast(@alignCast(id_column.getOpaque(entity_index)));
                zgui.pushIntId(@intCast(entity_id.entity_id));
                const entity_label: [:0]const u8 = std.fmt.allocPrintSentinel(
                    allocator,
                    "entity {any}::{any}",
                    .{ entity_id.scene_id, entity_id.entity_id },
                    0,
                ) catch @panic("could not allocate memory");
                defer allocator.free(entity_label);
                if (zgui.collapsingHeader(entity_label, .collapsing_header)) {
                    zgui.indent(.{});
                    for (archetype.components.items) |*column| {
                        const component_id = column.component_id;
                        const metadata = type_registry.metadata.get(component_id);
                        if (metadata) |meta| {
                            const name = meta.name;
                            zgui.bulletText("{s}", .{name});
                        } else {
                            zgui.bulletText("Unknown component", .{});
                        }
                    }
                    zgui.unindent(.{});
                }
                zgui.popId();
            }
        }
    }
}

pub fn allSystems(game: *Game) void {
    const schedule: *ecs.Schedule = &game.schedule;
    if (zgui.begin("systems", .{})) {
        printPhase(.setup, schedule, game.allocator);
        printPhase(.update, schedule, game.allocator);
        printPhase(.pre_render, schedule, game.allocator);
        printPhase(.render, schedule, game.allocator);
        printPhase(.post_render, schedule, game.allocator);
        printPhase(.tear_down, schedule, game.allocator);
        printPhase(.close, schedule, game.allocator);
    }
    zgui.end();
}

fn printPhase(phase: ecs.Schedule.Phase, schedule: *ecs.Schedule, allocator: std.mem.Allocator) void {
    const schedules = schedule.getPhase(phase);
    zgui.pushIntId(@intFromEnum(phase));
    if (zgui.treeNode(@tagName(phase))) {
        for (schedules.items, 0..) |schdl, idx| {
            zgui.pushIntId(@intCast(idx + 100));
            const headerName = allocator.dupeZ(u8, schdl.name) catch @panic("oom");
            defer allocator.free(headerName);
            if (zgui.treeNode(headerName)) {
                for (schdl.systems.items) |system| {
                    zgui.bulletText("{s}", .{system.name});
                }
                zgui.treePop();
            }
            zgui.popId();
        }
        zgui.treePop();
    }
    zgui.popId();
}
