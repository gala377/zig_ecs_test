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

pub fn showEntityDetails(game: *Game) anyerror!void {
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
                if (try entityDetailsWindow(
                    e,
                    entity_index,
                    record,
                    type_registry,
                    storage,
                    game.allocator,
                    primitives.get(),
                )) {
                    try remove_views.append(game.allocator, view.*);
                }
            } else {
                if (try showEmptyWindow(
                    e,
                    entity_index,
                    "Entity has been deleted",
                    game.allocator,
                )) {
                    try remove_views.append(game.allocator, view.*);
                }
            }
        } else {
            // scene entity
            if (scene) |s| {
                if (s.id == e.scene_id) {
                    const storage = &s.entity_storage;
                    const archetype_record = storage.entity_map.get(e);
                    if (archetype_record) |record| {
                        if (try entityDetailsWindow(
                            e,
                            entity_index,
                            record,
                            type_registry,
                            storage,
                            game.allocator,
                            primitives.get(),
                        )) {
                            try remove_views.append(game.allocator, view.*);
                        }
                    } else {
                        if (try showEmptyWindow(
                            e,
                            entity_index,
                            "Entity has been deleted",
                            game.allocator,
                        )) {
                            try remove_views.append(game.allocator, view.*);
                        }
                    }
                } else {
                    if (try showEmptyWindow(
                        e,
                        entity_index,
                        "Active scene is not the same as entities scene",
                        game.allocator,
                    )) {
                        try remove_views.append(game.allocator, view.*);
                    }
                }
            } else {
                if (try showEmptyWindow(
                    e,
                    entity_index,
                    "This is a scene entity but there is no scene active",
                    game.allocator,
                )) {
                    try remove_views.append(game.allocator, view.*);
                }
            }
        }
        entity_index += 1;
    }
    for (remove_views.items) |id| {
        try commands.get().removeEntity(id);
    }
}

fn entityDetailsWindow(
    e: entity.Id,
    entity_index: usize,
    record: ecs.EntityStorage.EntityArchetypeRecord,
    type_registry: *ecs.TypeRegistry,
    storage: *ecs.EntityStorage,
    allocator: std.mem.Allocator,
    primitives: *PrimiteTypeStorage,
) !bool {
    const title: [:0]const u8 = try std.fmt.allocPrintSentinel(
        allocator,
        "Entity {any}::{any}###{any}",
        .{ e.scene_id, e.entity_id, entity_index },
        0,
    );
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
                try printType(reflected, meta, .{
                    .type_registry = type_registry,
                    .allocator = allocator,
                    .primitives = primitives,
                });
            } else {
                zgui.bulletText("Unknown component", .{});
            }
        }
    }
    zgui.end();
    return !show;
}

fn showEmptyWindow(
    id: entity.Id,
    entity_index: usize,
    msg: []const u8,
    allocator: std.mem.Allocator,
) !bool {
    const title: [:0]const u8 = try std.fmt.allocPrintSentinel(
        allocator,
        "Entity {any}::{any}###{any}",
        .{ id.scene_id, id.entity_id, entity_index },
        0,
    );
    defer allocator.free(title);
    var show_window = true;
    if (zgui.begin(title, .{ .popen = &show_window })) {
        zgui.text("ERROR: {s}", .{msg});
    }
    zgui.end();
    return !show_window;
}

pub fn allEntities(game: *Game, commands: ecs.runtime.commands.Commands) anyerror!void {
    if (zgui.begin("entities", .{})) {
        const type_registry = &game.type_registry;
        const scene_archetypes = game.current_scene.?.entity_storage.archetypes;
        const global_archetypes = game.global_entity_storage.archetypes;
        const primitives = game.getResource(PrimiteTypeStorage);
        try printFromArchetype(
            global_archetypes.items,
            game.allocator,
            type_registry,
            "global",
            0,
            commands,
            primitives.get(),
        );
        try printFromArchetype(
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

pub fn allResources(game: *Game, commands: ecs.runtime.commands.Commands) anyerror!void {
    if (zgui.begin("resources", .{})) {
        const type_registry = &game.type_registry;
        const scene_archetypes = game.current_scene.?.entity_storage.archetypes;
        const global_archetypes = game.global_entity_storage.archetypes;
        const primitives = game.getResource(PrimiteTypeStorage);
        try printResourceFromArchetype(
            global_archetypes.items,
            game.allocator,
            type_registry,
            "global",
            0,
            commands,
            primitives.get(),
        );
        try printResourceFromArchetype(
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
) anyerror!void {
    const group_label = try std.fmt.allocPrintSentinel(
        allocator,
        "{s}::{any}",
        .{ label, id },
        0,
    );
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
                const entity_label: [:0]const u8 = try std.fmt.allocPrintSentinel(
                    allocator,
                    "{s} {any}::{any}",
                    .{ entity_name, entity_id.scene_id, entity_id.entity_id },
                    0,
                );
                defer allocator.free(entity_label);
                if (zgui.smallButton("E")) {
                    _ = try commands.get().addGlobalEntity(.{
                        EntityDetailsView{
                            .entity = entity_id,
                        },
                    });
                }
                zgui.sameLine(.{});
                if (zgui.smallButton("X")) {
                    std.debug.print("Adding entity to remove {any}\n", .{entity_id});
                    try commands.get().removeEntity(entity_id);
                }
                zgui.sameLine(.{});
                const show_entity = zgui.treeNode(entity_label);
                if (zgui.beginPopupContextItem()) {
                    if (zgui.menuItem("Details", .{})) {
                        _ = try commands.get().addGlobalEntity(.{
                            EntityDetailsView{
                                .entity = entity_id,
                            },
                        });
                    }
                    if (zgui.menuItem("Delete", .{})) {
                        try commands.get().removeEntity(entity_id);
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
                            try printType(reflected, meta, .{
                                .type_registry = type_registry,
                                .primitives = primitives,
                                .allocator = allocator,
                            });
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
) anyerror!void {
    const group_label = try std.fmt.allocPrintSentinel(
        allocator,
        "{s}::{any}",
        .{ label, id },
        0,
    );
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
                const entity_label: [:0]const u8 = try std.fmt.allocPrintSentinel(
                    allocator,
                    "{s} {any}::{any}",
                    .{ entity_name, entity_id.scene_id, entity_id.entity_id },
                    0,
                );
                defer allocator.free(entity_label);
                const show_entity = zgui.treeNode(entity_label);
                if (zgui.beginPopupContextItem()) {
                    if (zgui.menuItem("Details", .{})) {
                        _ = try commands.get().addGlobalEntity(.{
                            EntityDetailsView{
                                .entity = entity_id.*,
                            },
                        });
                    }
                    if (zgui.menuItem("Delete", .{})) {
                        try commands.get().removeEntity(entity_id.*);
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
                            const context = EditorContext{
                                .type_registry = type_registry,
                                .allocator = allocator,
                                .primitives = primitives,
                            };
                            try printType(reflected, meta, context);
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

const EditorContext = struct {
    type_registry: *ecs.TypeRegistry,
    allocator: std.mem.Allocator,
    primitives: *PrimiteTypeStorage,
};

fn printType(
    reflected: ?ecs.type_registry.ReflectedAny,
    metadata: *ecs.type_registry.ReflectionMetaData,
    context: EditorContext,
) anyerror!void {
    const name = try context.allocator.dupeZ(
        u8,
        metadata.name,
    );
    defer context.allocator.free(name);
    try printTypeWithName(
        name,
        reflected,
        metadata,
        context,
    );
}

fn printTypeWithName(
    name: [:0]const u8,
    maybe_reflected: ?ecs.type_registry.ReflectedAny,
    metadata: *ecs.type_registry.ReflectionMetaData,
    context: EditorContext,
) anyerror!void {
    if (maybe_reflected) |reflected| {
        if (metadata.kind == .string) {
            const svalue = try metadata.to_string.?(
                reflected.ptr,
                context.allocator,
            );
            defer context.allocator.free(svalue);
            zgui.bulletText("{s} = {s}", .{ name, svalue });
        } else if (metadata.child_type) |child| {
            try printPointer(
                child,
                name,
                reflected,
                metadata,
                context,
            );
        } else if (metadata.fields.len > 0) {
            try printStruct(
                name,
                reflected,
                metadata,
                context,
            );
        } else {
            try printValue(
                name,
                reflected,
                metadata,
                context,
            );
        }
    } else {
        zgui.bulletText("{s} = null", .{name});
    }
}

pub fn printPhaseTimes(
    execution_times: ecs.Resource(ecs.runtime.PhaseExecutionTimer),
    global_allocator: ecs.Resource(ecs.runtime.allocators.GlobalAllocator),
) !void {
    if (zgui.begin("phase executions", .{})) {
        const reading = &execution_times.inner.readings;
        inline for (std.meta.fields(ecs.Schedule.Phase)) |field| {
            try printReading(reading, @enumFromInt(field.value));
        }
        zgui.separator();
        if (zgui.collapsingHeader("plot", .{})) {
            if (zgui.plot.beginPlot("phase times", .{})) {
                zgui.plot.setupAxis(.x1, .{ .label = "time" });
                zgui.plot.setupAxisLimits(
                    .x1,
                    .{ .min = 1.0, .max = @floatFromInt(ecs.runtime.PhaseExecutionTimer.SAMPLE_COUNT) },
                );
                zgui.plot.setupAxis(.y1, .{ .label = "execution time" });
                zgui.plot.setupAxisLimits(.y1, .{ .min = 0.0, .max = 100.0 });
                zgui.plot.setupLegend(.{ .south = true, .west = true }, .{});
                zgui.plot.setupFinish();
                inline for (std.meta.fields(ecs.Schedule.Phase)) |field| {
                    try printPlot(reading, @enumFromInt(field.value), global_allocator.get().allocator);
                }
                zgui.plot.endPlot();
            }
        }
    }
    zgui.end();
}

fn printPlot(
    readings: *std.EnumArray(ecs.Schedule.Phase, ecs.runtime.PhaseExecutionTimer.Reading),
    phase: ecs.Schedule.Phase,
    allocator: std.mem.Allocator,
) !void {
    const read = readings.getPtr(phase);
    const name = @tagName(phase);
    if (read.read_once) {
        const ordered = try read.readingsOrdered(allocator);
        defer allocator.free(ordered);
        const asfloat = try allocator.alloc(f64, ordered.len);
        defer allocator.free(asfloat);
        for (ordered, 0..) |o, index| {
            asfloat[index] = o.toMilis();
        }
        zgui.plot.plotLineValues(name, f64, .{ .v = asfloat });
    }
}

fn printReading(
    readings: *std.EnumArray(ecs.Schedule.Phase, ecs.runtime.PhaseExecutionTimer.Reading),
    phase: ecs.Schedule.Phase,
) !void {
    const read = readings.getPtr(phase);
    const name = @tagName(phase);
    if (read.read_once) {
        zgui.text("{s} = {any}", .{ name, read.average().toSeconds() });
    } else {
        zgui.text("{s} = ...", .{name});
    }
}

pub fn allSystems(game: *Game) anyerror!void {
    const schedule: *ecs.Schedule = &game.schedule;
    if (zgui.begin("systems", .{})) {
        try printPhase(.setup, schedule, game.allocator);
        try printPhase(.pre_update, schedule, game.allocator);
        try printPhase(.update, schedule, game.allocator);
        try printPhase(.post_update, schedule, game.allocator);
        try printPhase(.pre_render, schedule, game.allocator);
        try printPhase(.render, schedule, game.allocator);
        try printPhase(.post_render, schedule, game.allocator);
        try printPhase(.tear_down, schedule, game.allocator);
        try printPhase(.close, schedule, game.allocator);
    }
    zgui.end();
}

fn printValue(
    name: [:0]const u8,
    reflected: ecs.type_registry.ReflectedAny,
    metadata: *ecs.type_registry.ReflectionMetaData,
    context: EditorContext,
) anyerror!void {
    if (metadata.to_string) |to_string| {
        switch (metadata.kind) {
            .@"enum" => {
                zgui.alignTextToFramePadding();
                zgui.bulletText("{s} = ", .{name});
                zgui.sameLine(.{});
                try drawEnumDropdown(metadata, reflected, context.allocator);
            },
            else => {
                const maybe_primitive = context.primitives.map.get(reflected.type_id);
                if (maybe_primitive) |primitive| {
                    zgui.pushPtrId(reflected.ptr);
                    switch (primitive) {
                        .byte => {
                            try intInput(u8, name, reflected, context.allocator);
                        },
                        .int => {
                            try intInput(i64, name, reflected, context.allocator);
                        },
                        .uint => {
                            try intInput(u64, name, reflected, context.allocator);
                        },
                        .int32 => {
                            try intInput(i32, name, reflected, context.allocator);
                        },
                        .uint32 => {
                            try intInput(u32, name, reflected, context.allocator);
                        },
                        .int64 => {
                            try intInput(i64, name, reflected, context.allocator);
                        },
                        .uint64 => {
                            try intInput(u64, name, reflected, context.allocator);
                        },
                        .bool => {
                            try boolInput(name, reflected, context.allocator);
                        },
                        .float32 => {
                            try floatInput(f32, name, reflected, context.allocator);
                        },
                        .float64 => {
                            try floatInput(f64, name, reflected, context.allocator);
                        },
                    }
                    zgui.popId();
                } else {
                    const repr = try to_string(reflected.ptr, context.allocator);
                    defer context.allocator.free(repr);
                    zgui.bulletText("{s} = {s}", .{ name, repr });
                }
            },
        }
    } else {
        // not a pointer and doesn't have fields so we can safely print the value here
        zgui.bulletText("{s} = unknown", .{name});
    }
}

fn boolInput(name: [:0]const u8, reflected: ecs.type_registry.ReflectedAny, allocator: std.mem.Allocator) anyerror!void {
    const boolValue: *bool = @ptrCast(@alignCast(reflected.ptr));
    var returned: bool = boolValue.*;
    zgui.alignTextToFramePadding();
    zgui.bulletText("{s} = ", .{name});
    zgui.sameLine(.{});
    const label: [:0]const u8 = try std.fmt.allocPrintSentinel(
        allocator,
        "##{any}",
        .{reflected.ptr},
        0,
    );
    defer allocator.free(label);
    if (zgui.checkbox(label, .{ .v = &returned })) {
        boolValue.* = returned;
    }
}

fn floatInput(
    comptime T: type,
    name: [:0]const u8,
    reflected: ecs.type_registry.ReflectedAny,
    allocator: std.mem.Allocator,
) anyerror!void {
    const intValue: *T = @ptrCast(@alignCast(reflected.ptr));
    zgui.alignTextToFramePadding();
    zgui.bulletText("{s} = ", .{name});
    zgui.sameLine(.{});
    zgui.setNextItemWidth(100.0);
    const label: [:0]const u8 = try std.fmt.allocPrintSentinel(
        allocator,
        "##{any}",
        .{reflected.ptr},
        0,
    );
    defer allocator.free(label);
    if (comptime T == f32) {
        var returned: f32 = intValue.*;
        const changed = zgui.inputFloat(label, .{ .v = &returned });
        if (zgui.isItemDeactivatedAfterEdit() or changed) {
            intValue.* = returned;
        }
    } else if (comptime T == f64) {
        var returned: f64 = intValue.*;
        const changed = zgui.inputDouble(label, .{ .v = &returned });
        if (zgui.isItemDeactivatedAfterEdit() or changed) {
            intValue.* = returned;
        }
    } else {
        @compileError("only f32 and f64 are supported");
    }
}

fn intInput(
    comptime T: type,
    name: [:0]const u8,
    reflected: ecs.type_registry.ReflectedAny,
    allocator: std.mem.Allocator,
) anyerror!void {
    const intValue: *T = @ptrCast(@alignCast(reflected.ptr));
    var returned: T = intValue.*;
    zgui.alignTextToFramePadding();
    zgui.bulletText("{s} = ", .{name});
    zgui.sameLine(.{});
    zgui.setNextItemWidth(100.0);
    const label: [:0]const u8 = try std.fmt.allocPrintSentinel(
        allocator,
        "##{any}",
        .{reflected.ptr},
        0,
    );
    defer allocator.free(label);
    const changed = zgui.inputScalar(label, T, .{
        .v = &returned,
    });
    if (zgui.isItemDeactivatedAfterEdit() or changed) {
        intValue.* = returned;
    }
}

fn printStruct(
    name: [:0]const u8,
    reflected: ecs.type_registry.ReflectedAny,
    metadata: *ecs.type_registry.ReflectionMetaData,
    context: EditorContext,
) anyerror!void {
    const show = zgui.treeNode(name);
    if (show) {
        for (metadata.fields) |field| {
            const field_meta = context.type_registry.metadata.get(field.field_type_id);
            if (field_meta) |meta| {
                var label: [:0]u8 = try context.allocator.allocSentinel(
                    u8,
                    field.name.len + 2 + meta.name.len,
                    0,
                );
                defer context.allocator.free(label);
                @memcpy(label[0..field.name.len], field.name);
                @memcpy(label[field.name.len .. field.name.len + 2], ": ");
                @memcpy(label[field.name.len + 2 ..], meta.name);
                const next_reflected = field.get(reflected.ptr);
                try printTypeWithName(
                    label,
                    next_reflected,
                    meta,
                    context,
                );
            } else {
                var label = try context.allocator.alloc(
                    u8,
                    field.name.len + 2 + "unknown type".len,
                );
                defer context.allocator.free(label);
                @memcpy(label[0..field.name.len], field.name);
                @memcpy(label[field.name.len..], ": unknown type");
                zgui.bulletText("{s}", .{label});
            }
        }
        zgui.treePop();
    }
}

fn printPointer(
    child: usize,
    name: [:0]const u8,
    reflected: ecs.type_registry.ReflectedAny,
    metadata: *ecs.type_registry.ReflectionMetaData,
    context: EditorContext,
) anyerror!void {
    const child_metadata = context.type_registry.metadata.get(child);
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
        try printTypeWithName(name, next_reflected, meta, context);
    } else {
        zgui.bulletText("{s}", .{name});
    }
}

fn printPhase(phase: ecs.Schedule.Phase, schedule: *ecs.Schedule, allocator: std.mem.Allocator) anyerror!void {
    const schedules = schedule.getPhase(phase);
    zgui.pushIntId(@intFromEnum(phase));
    if (zgui.treeNode(@tagName(phase))) {
        for (schedules.items, 0..) |schdl, idx| {
            zgui.pushIntId(@intCast(idx + 100));
            const headerName = try allocator.dupeZ(u8, schdl.name);
            defer allocator.free(headerName);
            if (zgui.treeNode(headerName)) {
                for (schdl.systems.items) |system| {
                    try printSystem(system, allocator);
                }
                zgui.treePop();
            }
            zgui.popId();
        }
        zgui.treePop();
    }
    zgui.popId();
}

fn printSystem(system: ecs.system.System, allocator: std.mem.Allocator) anyerror!void {
    const subsystems = system.subsystems();
    if (subsystems.len == 0) {
        zgui.bulletText("{s}", .{system.name});
    } else {
        const name = try allocator.dupeZ(u8, system.name);
        defer allocator.free(name);
        if (zgui.treeNode(name)) {
            for (subsystems) |s| {
                try printSystem(s, allocator);
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
) anyerror!void {
    const current_int = meta.tag_to_int.?(value.ptr);
    var preview_name: []const u8 = "Unknown";
    for (meta.tags) |tag| {
        if (tag.tag == current_int) {
            preview_name = tag.name;
            break;
        }
    }

    // 3. Render the Dropdown (Combo)
    const preview = try allocator.dupeZ(u8, preview_name);
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
            const selectable = try allocator.dupeZ(u8, tag.name);
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

pub fn plotSystems(game: *Game) !void {
    const schedule = &game.schedule;
    const readings = &game.schedule.system_execution_time;
    const allocator = game.allocator;
    if (zgui.begin("system_times", .{})) {
        for (std.enums.values(ecs.Schedule.Phase)) |phase| {
            if (zgui.treeNode(@tagName(phase))) {
                const phase_readings = readings.phases.getPtr(phase);
                const phase_schedule = schedule.getPhase(phase);
                for (phase_schedule.items) |current_schedule| {
                    const label = try allocator.dupeZ(u8, current_schedule.name);
                    defer allocator.free(label);
                    if (zgui.treeNode(label)) {
                        const schedule_readings = phase_readings.schedule_readings.getPtr(
                            current_schedule.identifier,
                        );
                        if (schedule_readings) |system_readings| {
                            var systems = system_readings.readings.iterator();
                            if (zgui.plot.beginPlot("system times", .{})) {
                                zgui.plot.setupAxis(.x1, .{ .label = "time" });
                                zgui.plot.setupAxisLimits(
                                    .x1,
                                    .{ .min = 1.0, .max = @floatFromInt(ecs.runtime.PhaseExecutionTimer.SAMPLE_COUNT) },
                                );
                                zgui.plot.setupAxis(.y1, .{ .label = "execution time" });
                                zgui.plot.setupAxisLimits(.y1, .{ .min = 0.0, .max = 100.0 });
                                zgui.plot.setupLegend(.{ .south = true, .west = true }, .{});
                                zgui.plot.setupFinish();

                                while (systems.next()) |entry| {
                                    const plot_label = try allocator.dupeZ(u8, entry.value_ptr.name);
                                    defer allocator.free(plot_label);

                                    const ordered = try entry.value_ptr.reading.readingsOrdered(allocator);
                                    defer allocator.free(ordered);

                                    const asfloat = try allocator.alloc(f64, ordered.len);
                                    defer allocator.free(asfloat);

                                    for (ordered, 0..) |o, index| {
                                        asfloat[index] = o.toMilis();
                                    }

                                    zgui.plot.plotLineValues(plot_label, f64, .{
                                        .v = asfloat,
                                    });
                                }

                                zgui.plot.endPlot();
                            }
                        } else {
                            zgui.text("No readings for this schedule", .{});
                        }
                        zgui.treePop();
                    }
                }
                zgui.treePop();
            }
        }
    }
    zgui.end();
}
