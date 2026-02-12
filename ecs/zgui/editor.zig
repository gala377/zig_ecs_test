const std = @import("std");
const ecs = @import("../prelude.zig");
const zgui = @import("zgui");
const utils = ecs.utils;
const entity = ecs.entity;
const entity_storage = ecs.EntityStorage;

const Game = ecs.game.Game;

pub const EntityDetailsView = struct {
    pub const component_info = ecs.Component(EntityDetailsView);
    entity: entity.Id,
};

pub fn showEntityDetails(game: *Game) void {
    const primitives = game.getResource(PrimiteTypeStorage);
    const commands = game.getResource(ecs.runtime.commands);
    const type_registry = &game.type_registry;
    var remove_views: std.ArrayList(entity.Id) = .empty;
    defer remove_views.deinit(game.allocator);
    const scene = if (game.current_scene) |*s| s else null;
    var views = game.query(.{ ecs.entity.Id, EntityDetailsView }, .{});
    var entity_index: usize = 0;
    while (views.next()) |view_data| {
        var view: *entity.Id = undefined;
        var details: *EntityDetailsView = undefined;
        view, details = view_data;
        const e = details.entity;
        if (e.scene_id == 0) {
            // global entity
            const storage = &game.global_entity_storage;
            const archetype_record = storage.entity_map.get(e);
            if (archetype_record) |record| {
                if (entityDetailsWindow(
                    e,
                    entity_index,
                    record,
                    type_registry,
                    storage,
                    game.allocator,
                    primitives.get(),
                )) {
                    remove_views.append(game.allocator, view.*) catch @panic("oom");
                }
            } else {
                if (showEmptyWindow(
                    e,
                    entity_index,
                    "Entity has been deleted",
                    game.allocator,
                )) {
                    remove_views.append(game.allocator, view.*) catch {
                        @panic("oom");
                    };
                }
            }
        } else {
            // scene entity
            if (scene) |s| {
                if (s.id == e.scene_id) {
                    const storage = &s.entity_storage;
                    const archetype_record = storage.entity_map.get(e);
                    if (archetype_record) |record| {
                        if (entityDetailsWindow(
                            e,
                            entity_index,
                            record,
                            type_registry,
                            storage,
                            game.allocator,
                            primitives.get(),
                        )) {
                            remove_views.append(game.allocator, view.*) catch @panic("oom");
                        }
                    } else {
                        if (showEmptyWindow(
                            e,
                            entity_index,
                            "Entity has been deleted",
                            game.allocator,
                        )) {
                            remove_views.append(game.allocator, view.*) catch {
                                @panic("oom");
                            };
                        }
                    }
                } else {
                    if (showEmptyWindow(
                        e,
                        entity_index,
                        "Active scene is not the same as entities scene",
                        game.allocator,
                    )) {
                        remove_views.append(game.allocator, view.*) catch {
                            @panic("oom");
                        };
                    }
                }
            } else {
                if (showEmptyWindow(
                    e,
                    entity_index,
                    "This is a scene entity but there is no scene active",
                    game.allocator,
                )) {
                    remove_views.append(game.allocator, view.*) catch {
                        @panic("oom");
                    };
                }
            }
        }
        entity_index += 1;
    }
    for (remove_views.items) |id| {
        commands.get().removeEntity(id) catch @panic("oom");
    }
}

// pub const EntityDetailsView = struct {
//     pub const component_info = ecs.Component(EntityDetailsView);
//     allocator: std.mem.Allocator,
//     entities: std.ArrayList(entity.Id),
//
//     pub fn init(allocator: std.mem.Allocator) EntityDetailsView {
//         return .{
//             .allocator = allocator,
//             .entities = .empty,
//         };
//     }
//
//     pub fn add(self: *EntityDetailsView, id: entity.Id) !void {
//         return self.entities.append(self.allocator, id);
//     }
//
//     pub fn remove(self: *EntityDetailsView, id: entity.Id) void {
//         var index: ?usize = null;
//         for (self.entities.items, 0..) |e, idx| {
//             if (e.scene_id == id.scene_id and e.entity_id == id.entity_id) {
//                 index = idx;
//                 break;
//             }
//         }
//         if (index) |idx| {
//             _ = self.entities.orderedRemove(idx);
//         }
//     }
//
//     pub fn deinit(self: *EntityDetailsView, allocator: std.mem.Allocator) void {
//         _ = allocator;
//         self.entities.deinit(self.allocator);
//     }
// };

// pub fn showEntityDetails(game: *Game) void {
//     const view = game.getResource(EntityDetailsView);
//     const primitives = game.getResource(PrimiteTypeStorage);
//     const type_registry = &game.type_registry;
//     const entity_view = view.get();
//     const entities: []const entity.Id = entity_view.entities.items;
//     var remove_views: std.ArrayList(entity.Id) = .empty;
//     defer remove_views.deinit(game.allocator);
//     for (entities, 0..) |e, entity_index| {
//         const scene = if (game.current_scene) |*s| s else null;
//         if (e.scene_id == 0) {
//             // global entity
//             const storage = &game.global_entity_storage;
//             const archetype_record = storage.entity_map.get(e);
//             if (archetype_record) |record| {
//                 if (entityDetailsWindow(
//                     e,
//                     entity_index,
//                     record,
//                     type_registry,
//                     storage,
//                     game.allocator,
//                     primitives.get(),
//                 )) {
//                     remove_views.append(game.allocator, e) catch @panic("oom");
//                 }
//             } else {
//                 if (showEmptyWindow(
//                     e,
//                     entity_index,
//                     "Entity has been deleted",
//                     game.allocator,
//                 )) {
//                     remove_views.append(game.allocator, e) catch {
//                         @panic("oom");
//                     };
//                 }
//             }
//         } else {
//             // scene entity
//             if (scene) |s| {
//                 if (s.id == e.scene_id) {
//                     const storage = &s.entity_storage;
//                     const archetype_record = storage.entity_map.get(e);
//                     if (archetype_record) |record| {
//                         if (entityDetailsWindow(
//                             e,
//                             entity_index,
//                             record,
//                             type_registry,
//                             storage,
//                             game.allocator,
//                             primitives.get(),
//                         )) {
//                             remove_views.append(game.allocator, e) catch @panic("oom");
//                         }
//                     } else {
//                         if (showEmptyWindow(
//                             e,
//                             entity_index,
//                             "Entity has been deleted",
//                             game.allocator,
//                         )) {
//                             remove_views.append(game.allocator, e) catch {
//                                 @panic("oom");
//                             };
//                         }
//                     }
//                 } else {
//                     if (showEmptyWindow(
//                         e,
//                         entity_index,
//                         "Active scene is not the same as entities scene",
//                         game.allocator,
//                     )) {
//                         remove_views.append(game.allocator, e) catch {
//                             @panic("oom");
//                         };
//                     }
//                 }
//             } else {
//                 if (showEmptyWindow(
//                     e,
//                     entity_index,
//                     "This is a scene entity but there is no scene active",
//                     game.allocator,
//                 )) {
//                     remove_views.append(game.allocator, e) catch {
//                         @panic("oom");
//                     };
//                 }
//             }
//         }
//     }
//     for (remove_views.items) |id| {
//         entity_view.remove(id);
//     }
// }

fn entityDetailsWindow(
    e: entity.Id,
    entity_index: usize,
    record: ecs.EntityStorage.EntityArchetypeRecord,
    type_registry: *ecs.TypeRegistry,
    storage: *ecs.EntityStorage,
    allocator: std.mem.Allocator,
    primitives: *PrimiteTypeStorage,
) bool {
    const title: [:0]const u8 = std.fmt.allocPrintSentinel(
        allocator,
        "Entity {any}::{any}###{any}",
        .{ e.scene_id, e.entity_id, entity_index },
        0,
    ) catch {
        @panic("oom");
    };
    defer allocator.free(title);
    var show = true;
    if (zgui.begin(title, .{ .popen = &show })) {
        const archetype = &storage.archetypes.items[record.archetype_index];
        for (archetype.components.items) |*column| {
            const component_id = column.component_id;
            const metadata = type_registry.metadata.get(component_id);
            const component_pointer = column.getOpaque(record.row_id);
            if (metadata) |meta| {
                const reflected = ecs.type_registry.ReflectedAny{
                    .is_const = false,
                    .ptr = component_pointer,
                    .type_id = column.component_id,
                };
                printType(
                    type_registry,
                    meta,
                    allocator,
                    reflected,
                    primitives,
                );
            } else {
                zgui.bulletText("Unknown component", .{});
            }
        }
    }
    zgui.end();
    return !show;
}

fn showEmptyWindow(id: entity.Id, entity_index: usize, msg: []const u8, allocator: std.mem.Allocator) bool {
    const title: [:0]const u8 = std.fmt.allocPrintSentinel(
        allocator,
        "Entity {any}::{any}###{any}",
        .{ id.scene_id, id.entity_id, entity_index },
        0,
    ) catch {
        @panic("oom");
    };
    defer allocator.free(title);
    var show_window = true;
    if (zgui.begin(title, .{ .popen = &show_window })) {
        zgui.text("ERROR: {s}", .{msg});
    }
    zgui.end();
    return !show_window;
}

pub fn allEntities(game: *Game, commands: ecs.runtime.commands.Commands) void {
    if (zgui.begin("entities", .{})) {
        const type_registry = &game.type_registry;
        const scene_archetypes = game.current_scene.?.entity_storage.archetypes;
        const global_archetypes = game.global_entity_storage.archetypes;
        const primitives = game.getResource(PrimiteTypeStorage);
        printFromArchetype(
            global_archetypes.items,
            game.allocator,
            type_registry,
            "global",
            0,
            commands,
            primitives.get(),
        );
        printFromArchetype(
            scene_archetypes.items,
            game.allocator,
            type_registry,
            "scene",
            @intCast(game.current_scene.?.id),
            commands,
            primitives.get(),
        );
    }
    zgui.end();
}

pub fn allResources(game: *Game, commands: ecs.runtime.commands.Commands) void {
    if (zgui.begin("resources", .{})) {
        const type_registry = &game.type_registry;
        const scene_archetypes = game.current_scene.?.entity_storage.archetypes;
        const global_archetypes = game.global_entity_storage.archetypes;
        const primitives = game.getResource(PrimiteTypeStorage);
        printResourceFromArchetype(
            global_archetypes.items,
            game.allocator,
            type_registry,
            "global",
            0,
            commands,
            primitives.get(),
        );
        printResourceFromArchetype(
            scene_archetypes.items,
            game.allocator,
            type_registry,
            "scene",
            @intCast(game.current_scene.?.id),
            commands,
            primitives.get(),
        );
    }
    zgui.end();
}

fn printFromArchetype(
    archetypes: []const entity_storage.Archetype,
    allocator: std.mem.Allocator,
    type_registry: *ecs.TypeRegistry,
    label: []const u8,
    id: i32,
    commands: ecs.runtime.commands.Commands,
    primitives: *PrimiteTypeStorage,
) void {
    const group_label = std.fmt.allocPrintSentinel(
        allocator,
        "{s}::{any}",
        .{ label, id },
        0,
    ) catch @panic("oom");
    defer allocator.free(group_label);
    if (zgui.treeNode(group_label)) {
        for (archetypes) |*archetype| {
            for (0..archetype.capacity) |entity_index| {
                if (archetype.freelist.contains(entity_index)) {
                    continue;
                }
                var id_column_search: ?*entity_storage.ComponentColumn = null;
                var name_column: ?*entity_storage.ComponentColumn = null;
                var resource_marker: ?*entity_storage.ComponentColumn = null;
                for (archetype.components.items) |*column| {
                    if (column.component_id == utils.typeId(entity.Id)) {
                        id_column_search = column;
                    }
                    if (column.component_id == utils.typeId(ecs.core.Name)) {
                        name_column = column;
                    }
                    if (column.component_id == utils.typeId(ecs.resource.ResourceMarker)) {
                        resource_marker = column;
                    }
                }
                if (resource_marker != null) {
                    continue;
                }
                const id_column = id_column_search orelse @panic("missing entity id");
                const entity_id: entity.Id = id_column.getAs(entity_index, entity.Id).*;
                zgui.pushIntId(@intCast(entity_id.entity_id));
                const entity_name = if (name_column) |column|
                    column.getAs(entity_index, ecs.core.Name).name
                else
                    "entity";
                const entity_label: [:0]const u8 = std.fmt.allocPrintSentinel(
                    allocator,
                    "{s} {any}::{any}",
                    .{ entity_name, entity_id.scene_id, entity_id.entity_id },
                    0,
                ) catch @panic("could not allocate memory");
                defer allocator.free(entity_label);
                if (zgui.smallButton("E")) {
                    _ = commands.get().addGlobalEntity(.{
                        EntityDetailsView{
                            .entity = entity_id,
                        },
                    }) catch @panic("oom");
                }
                zgui.sameLine(.{});
                if (zgui.smallButton("X")) {
                    std.debug.print("Adding entity to remove {any}\n", .{entity_id});
                    commands.get().removeEntity(entity_id) catch @panic("oom");
                }
                zgui.sameLine(.{});
                const show_entity = zgui.treeNode(entity_label);
                if (zgui.beginPopupContextItem()) {
                    if (zgui.menuItem("Details", .{})) {
                        _ = commands.get().addGlobalEntity(.{
                            EntityDetailsView{
                                .entity = entity_id,
                            },
                        }) catch @panic("oom");
                    }
                    if (zgui.menuItem("Delete", .{})) {
                        commands.get().removeEntity(entity_id) catch @panic("oom");
                    }
                    zgui.endPopup();
                }
                if (show_entity) {
                    for (archetype.components.items) |*column| {
                        const component_id = column.component_id;
                        const metadata = type_registry.metadata.get(component_id);
                        const component_pointer = column.getOpaque(entity_index);
                        if (metadata) |meta| {
                            const reflected = ecs.type_registry.ReflectedAny{
                                .is_const = false,
                                .ptr = component_pointer,
                                .type_id = column.component_id,
                            };
                            printType(
                                type_registry,
                                meta,
                                allocator,
                                reflected,
                                primitives,
                            );
                        } else {
                            zgui.bulletText("Unknown component", .{});
                        }
                    }
                    zgui.treePop();
                }
                zgui.popId();
            }
        }
        zgui.treePop();
    }
}

fn printResourceFromArchetype(
    archetypes: []const entity_storage.Archetype,
    allocator: std.mem.Allocator,
    type_registry: *ecs.TypeRegistry,
    label: []const u8,
    id: i32,
    commands: ecs.runtime.commands.Commands,
    primitives: *PrimiteTypeStorage,
) void {
    const group_label = std.fmt.allocPrintSentinel(
        allocator,
        "{s}::{any}",
        .{ label, id },
        0,
    ) catch @panic("oom");
    defer allocator.free(group_label);
    if (zgui.treeNode(group_label)) {
        for (archetypes) |*archetype| {
            for (0..archetype.capacity) |entity_index| {
                if (archetype.freelist.contains(entity_index)) {
                    continue;
                }
                var id_column_search: ?*entity_storage.ComponentColumn = null;
                var name_column: ?*entity_storage.ComponentColumn = null;
                var resource_marker: ?*entity_storage.ComponentColumn = null;
                for (archetype.components.items) |*column| {
                    if (column.component_id == utils.typeId(entity.Id)) {
                        id_column_search = column;
                    }
                    if (column.component_id == utils.typeId(ecs.core.Name)) {
                        name_column = column;
                    }
                    if (column.component_id == utils.typeId(ecs.resource.ResourceMarker)) {
                        resource_marker = column;
                    }
                }
                if (resource_marker == null) {
                    continue;
                }
                const id_column = id_column_search orelse @panic("missing entity id");
                const entity_id: *const entity.Id = @ptrCast(@alignCast(id_column.getOpaque(entity_index)));
                zgui.pushIntId(@intCast(entity_id.entity_id));
                const entity_name = if (name_column) |column|
                    @as(*const ecs.core.Name, @ptrCast(@alignCast(column.getOpaque(
                        entity_index,
                    )))).name
                else
                    "entity";
                const entity_label: [:0]const u8 = std.fmt.allocPrintSentinel(
                    allocator,
                    "{s} {any}::{any}",
                    .{ entity_name, entity_id.scene_id, entity_id.entity_id },
                    0,
                ) catch @panic("could not allocate memory");
                defer allocator.free(entity_label);
                const show_entity = zgui.treeNode(entity_label);
                if (zgui.beginPopupContextItem()) {
                    if (zgui.menuItem("Details", .{})) {
                        _ = commands.get().addGlobalEntity(.{
                            EntityDetailsView{
                                .entity = entity_id.*,
                            },
                        }) catch @panic("oom");
                    }
                    if (zgui.menuItem("Delete", .{})) {
                        commands.get().removeEntity(entity_id.*) catch @panic("oom");
                    }
                    zgui.endPopup();
                }
                if (show_entity) {
                    for (archetype.components.items) |*column| {
                        const component_id = column.component_id;
                        const metadata = type_registry.metadata.get(component_id);
                        const component_pointer = column.getOpaque(entity_index);
                        if (metadata) |meta| {
                            const reflected = ecs.type_registry.ReflectedAny{
                                .is_const = false,
                                .ptr = component_pointer,
                                .type_id = column.component_id,
                            };
                            printType(
                                type_registry,
                                meta,
                                allocator,
                                reflected,
                                primitives,
                            );
                        } else {
                            zgui.bulletText("Unknown component", .{});
                        }
                    }
                    zgui.treePop();
                }
                zgui.popId();
            }
        }
        zgui.treePop();
    }
}

fn printType(
    type_registry: *ecs.TypeRegistry,
    metadata: *ecs.type_registry.ReflectionMetaData,
    allocator: std.mem.Allocator,
    reflected: ?ecs.type_registry.ReflectedAny,
    primitives: *PrimiteTypeStorage,
) void {
    const name = allocator.dupeZ(u8, metadata.name) catch @panic("oom");
    defer allocator.free(name);
    printTypeWithName(
        type_registry,
        metadata,
        allocator,
        name,
        reflected,
        primitives,
    );
}

fn printTypeWithName(
    type_registry: *ecs.TypeRegistry,
    metadata: *ecs.type_registry.ReflectionMetaData,
    allocator: std.mem.Allocator,
    name: [:0]const u8,
    maybe_reflected: ?ecs.type_registry.ReflectedAny,
    primitive_type_storage: *PrimiteTypeStorage,
) void {
    if (maybe_reflected) |reflected| {
        if (metadata.kind == .string) {
            const svalue = metadata.to_string.?(reflected.ptr, allocator) catch @panic("oom");
            defer allocator.free(svalue);
            zgui.bulletText("{s} = {s}", .{ name, svalue });
        } else if (metadata.child_type) |child| {
            printPointer(
                type_registry,
                child,
                metadata,
                reflected,
                allocator,
                name,
                primitive_type_storage,
            );
        } else if (metadata.fields.len > 0) {
            printStruct(
                name,
                type_registry,
                metadata,
                reflected,
                allocator,
                primitive_type_storage,
            );
        } else {
            printValue(
                name,
                metadata,
                reflected,
                allocator,
                primitive_type_storage,
                type_registry,
            );
        }
    } else {
        zgui.bulletText("{s} = null", .{name});
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

fn printValue(
    name: [:0]const u8,
    metadata: *ecs.type_registry.ReflectionMetaData,
    reflected: ecs.type_registry.ReflectedAny,
    allocator: std.mem.Allocator,
    primitive_type_storage: *PrimiteTypeStorage,
    type_registry: *ecs.TypeRegistry,
) void {
    _ = type_registry;
    if (metadata.to_string) |to_string| {
        switch (metadata.kind) {
            .@"enum" => {
                zgui.alignTextToFramePadding();
                zgui.bulletText("{s} = ", .{name});
                zgui.sameLine(.{});
                drawEnumDropdown(metadata, reflected, allocator);
            },
            else => {
                const maybe_primitive = primitive_type_storage.map.get(reflected.type_id);
                if (maybe_primitive) |primitive| {
                    zgui.pushPtrId(reflected.ptr);
                    switch (primitive) {
                        .byte => {
                            intInput(u8, name, reflected, allocator);
                        },
                        .int => {
                            intInput(isize, name, reflected, allocator);
                        },
                        .uint => {
                            intInput(usize, name, reflected, allocator);
                        },
                        .int32 => {
                            intInput(i32, name, reflected, allocator);
                        },
                        .uint32 => {
                            intInput(u32, name, reflected, allocator);
                        },
                        .int64 => {
                            intInput(i64, name, reflected, allocator);
                        },
                        .uint64 => {
                            intInput(u64, name, reflected, allocator);
                        },
                        .bool => {
                            boolInput(name, reflected, allocator);
                        },
                        else => {
                            const repr = to_string(reflected.ptr, allocator) catch @panic("oom");
                            defer allocator.free(repr);
                            zgui.bulletText("{s} = {s}", .{ name, repr });
                        },
                    }
                    zgui.popId();
                } else {
                    const repr = to_string(reflected.ptr, allocator) catch @panic("oom");
                    defer allocator.free(repr);
                    zgui.bulletText("{s} = {s}", .{ name, repr });
                }
            },
        }
    } else {
        // not a pointer and doesn't have fields so we can safely print the value here
        zgui.bulletText("{s} = unknown", .{name});
    }
}

fn boolInput(name: [:0]const u8, reflected: ecs.type_registry.ReflectedAny, allocator: std.mem.Allocator) void {
    const boolValue: *bool = @ptrCast(@alignCast(reflected.ptr));
    var returned: bool = boolValue.*;
    zgui.alignTextToFramePadding();
    zgui.bulletText("{s} = ", .{name});
    zgui.sameLine(.{});
    const label: [:0]const u8 = std.fmt.allocPrintSentinel(
        allocator,
        "##{any}",
        .{reflected.ptr},
        0,
    ) catch @panic("oom");
    defer allocator.free(label);
    if (zgui.checkbox(label, .{ .v = &returned })) {
        boolValue.* = returned;
    }
}

fn intInput(comptime T: type, name: [:0]const u8, reflected: ecs.type_registry.ReflectedAny, allocator: std.mem.Allocator) void {
    const intValue: *T = @ptrCast(@alignCast(reflected.ptr));
    var returned: i32 = @intCast(intValue.*);
    zgui.alignTextToFramePadding();
    zgui.bulletText("{s} = ", .{name});
    zgui.sameLine(.{});
    zgui.setNextItemWidth(100.0);
    const label: [:0]const u8 = std.fmt.allocPrintSentinel(
        allocator,
        "##{any}",
        .{reflected.ptr},
        0,
    ) catch @panic("oom");
    defer allocator.free(label);
    const changed = zgui.inputInt(label, .{ .v = &returned });
    if (zgui.isItemDeactivatedAfterEdit() or changed) {
        intValue.* = @intCast(returned);
    }
}

fn printStruct(
    name: [:0]const u8,
    type_registry: *ecs.TypeRegistry,
    metadata: *ecs.type_registry.ReflectionMetaData,
    reflected: ecs.type_registry.ReflectedAny,
    allocator: std.mem.Allocator,
    primitives: *PrimiteTypeStorage,
) void {
    const show = zgui.treeNode(name);
    if (show) {
        for (metadata.fields) |field| {
            const field_meta = type_registry.metadata.get(field.field_type_id);
            if (field_meta) |meta| {
                var label: [:0]u8 = allocator.allocSentinel(u8, field.name.len + 2 + meta.name.len, 0) catch @panic("oom");
                defer allocator.free(label);
                @memcpy(label[0..field.name.len], field.name);
                @memcpy(label[field.name.len .. field.name.len + 2], ": ");
                @memcpy(label[field.name.len + 2 ..], meta.name);
                const next_reflected = field.get(reflected.ptr);
                printTypeWithName(
                    type_registry,
                    meta,
                    allocator,
                    label,
                    next_reflected,
                    primitives,
                );
            } else {
                var label = allocator.alloc(u8, field.name.len + 2 + "unknown type".len) catch @panic("oom");
                defer allocator.free(label);
                @memcpy(label[0..field.name.len], field.name);
                @memcpy(label[field.name.len..], ": unknown type");
                zgui.bulletText("{s}", .{label});
            }
        }
        zgui.treePop();
    }
}

fn printPointer(
    type_registry: *ecs.TypeRegistry,
    child: usize,
    metadata: *ecs.type_registry.ReflectionMetaData,
    reflected: ecs.type_registry.ReflectedAny,
    allocator: std.mem.Allocator,
    name: [:0]const u8,
    primitives: *PrimiteTypeStorage,
) void {
    const child_metadata = type_registry.metadata.get(child);
    if (child_metadata) |meta| {
        var next_reflected: ?ecs.type_registry.ReflectedAny = undefined;
        if (metadata.kind == .pointer) {
            if (metadata.deref) |deref| {
                next_reflected = deref(reflected.ptr);
            } else {
                next_reflected = null;
            }
        } else if (metadata.kind == .optional) {
            next_reflected = metadata.deref_opt.?(reflected.ptr);
        } else {
            next_reflected = null;
        }
        printTypeWithName(
            type_registry,
            meta,
            allocator,
            name,
            next_reflected,
            primitives,
        );
    } else {
        zgui.bulletText("{s}", .{name});
    }
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
                    printSystem(system, allocator);
                }
                zgui.treePop();
            }
            zgui.popId();
        }
        zgui.treePop();
    }
    zgui.popId();
}

fn printSystem(system: ecs.system.System, allocator: std.mem.Allocator) void {
    const subsystems = system.subsystems();
    if (subsystems.len == 0) {
        zgui.bulletText("{s}", .{system.name});
    } else {
        const name = allocator.dupeZ(u8, system.name) catch @panic("oom");
        defer allocator.free(name);
        if (zgui.treeNode(name)) {
            for (subsystems) |s| {
                printSystem(s, allocator);
            }
            zgui.treePop();
        }
    }
}

const PrimitiveTypes = enum {
    byte,
    bool,
    uint,
    int,
    int32,
    uint32,
    int64,
    uint64,
    float32,
    float64,
};

pub const PrimiteTypeStorage = struct {
    pub const component_info = ecs.Component(PrimiteTypeStorage);

    map: std.AutoHashMap(usize, PrimitiveTypes),

    pub fn init(allocator: std.mem.Allocator) !PrimiteTypeStorage {
        var map: std.AutoHashMap(usize, PrimitiveTypes) = .init(allocator);
        try map.put(utils.typeId(u8), .byte);
        try map.put(utils.typeId(isize), .int);
        std.debug.print("put type {any} as int\n", .{utils.typeId(isize)});
        try map.put(utils.typeId(usize), .uint);
        std.debug.print("put type {any} as uint\n", .{utils.typeId(usize)});
        try map.put(utils.typeId(bool), .bool);
        std.debug.print("put type {any} as bool\n", .{utils.typeId(bool)});
        try map.put(utils.typeId(i32), .int32);
        std.debug.print("put type {any} as int32\n", .{utils.typeId(i32)});
        try map.put(utils.typeId(u32), .uint32);
        std.debug.print("put type {any} as uint32\n", .{utils.typeId(u32)});
        try map.put(utils.typeId(i64), .int64);
        std.debug.print("put type {any} as int64\n", .{utils.typeId(i64)});
        try map.put(utils.typeId(u64), .uint64);
        std.debug.print("put type {any} as uint64\n", .{utils.typeId(u64)});
        try map.put(utils.typeId(f32), .float32);
        std.debug.print("put type {any} as float32\n", .{utils.typeId(f32)});
        try map.put(utils.typeId(f64), .float64);
        std.debug.print("put type {any} as float64\n", .{utils.typeId(f64)});
        return .{
            .map = map,
        };
    }

    pub fn deinit(self: *PrimiteTypeStorage, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.map.deinit();
    }
};

pub fn drawEnumDropdown(
    meta: *ecs.type_registry.ReflectionMetaData,
    value: ecs.type_registry.ReflectedAny,
    allocator: std.mem.Allocator,
) void {
    const current_int = meta.tag_to_int.?(value.ptr);
    var preview_name: []const u8 = "Unknown";
    for (meta.tags) |tag| {
        if (tag.tag == current_int) {
            preview_name = tag.name;
            break;
        }
    }

    // 3. Render the Dropdown (Combo)
    const preview = allocator.dupeZ(u8, preview_name) catch @panic("oom");
    defer allocator.free(preview);
    zgui.pushPtrId(value.ptr); // Prevent ID collisions if multiple enums are on screen
    if (zgui.beginCombo("##enum_drop", .{
        .preview_value = preview,
        .flags = .{
            .height_small = true,
            .width_fit_preview = true,
            .popup_align_left = true,
        },
    })) {
        for (meta.tags) |tag| {
            const is_selected = (tag.tag == current_int);
            const selectable = allocator.dupeZ(u8, tag.name) catch @panic("oom");
            defer allocator.free(selectable);
            // Render the selectable item
            if (zgui.selectable(selectable, .{ .selected = is_selected })) {
                // 4. Update the actual value using your metadata helper
                meta.set_tag_from_int.?(value.ptr, tag.tag);
            }

            if (is_selected) {
                zgui.setItemDefaultFocus();
            }
        }
        zgui.endCombo();
    }
    zgui.popId();
}
