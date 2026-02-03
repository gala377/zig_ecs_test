const std = @import("std");
const lua = @import("lua_lib");
const ecs = @import("prelude.zig");

const clua = lua.clib;
const utils = ecs.utils;
const component = ecs.component;

const LuaVTable = ecs.lua.export_component.VTable;
const EntityStorage = ecs.EntityStorage;

pub const OpaqueSelf = anyopaque;

pub const ReflectedAny = struct {
    ptr: *anyopaque,
    type_id: usize,
};

pub const ReflectionField = struct {
    /// Name of the field
    name: []const u8,
    /// Type of the field
    field_type_id: usize,
    /// Field getter
    get: *const fn (*OpaqueSelf) ReflectedAny,
    /// Field setter
    set: *const fn (*OpaqueSelf, ReflectedAny) void,
};

pub const TypeKind = enum {
    value,
    pointer,
    slice,
};

pub const ReflectionMetaData = struct {
    /// name of this type
    name: []const u8,
    /// kind of a type, so pointers and so on can have special
    /// handling if needed
    kind: TypeKind,
    /// id of a child type if any,
    child_type: ?usize,
    /// information about fields if any
    fields: []const ReflectionField,
    /// set value of this field from any value
    set: *const fn (*OpaqueSelf, ReflectedAny) void,
    /// If callable can be used to invoke
    call: ?*const fn (*OpaqueSelf, []ReflectedAny) ReflectedAny,
    /// If pointer can be used to dereference it
    deref: ?*const fn (*OpaqueSelf) ReflectedAny,
    /// If pointer can be used to set underlying memory
    ref: ?*const fn (*OpaqueSelf, ReflectedAny) void,
    /// component vtable if any
    component_vtable: ?*const component.Opaque.VTable,
};

pub const TypeRegistry = struct {
    metadata: std.AutoHashMap(usize, *ReflectionMetaData),
    names_to_ids: std.StringHashMap(usize),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TypeRegistry {
        return .{
            .allocator = allocator,
            .names_to_ids = .init(allocator),
            .metadata = .init(allocator),
        };
    }

    pub fn registerStruct(self: *TypeRegistry, comptime T: type) !void {
        const meta = try structMetaData(T, self.allocator);
        try self.registerPointer(*T);
        return self.registerWithMetaData(T, meta);
    }

    pub fn registerPointer(self: *TypeRegistry, comptime T: type) !void {
        try self.registerWithMetaData(T, .{
            .name = @typeName(T),
            .kind = .pointer,
            .child_type = utils.typeId(@typeInfo(T).pointer.child),
            .call = null,
            .ref = ref(T),
            .deref = deref(T),
            .set = simpleValueSetter(T),
            .fields = &.{},
            .component_vtable = null,
        });
    }

    pub fn registerStdTypes(self: *TypeRegistry) !void {
        try self.registerValueType(usize);
        try self.registerValueType(isize);
        try self.registerValueType(i64);
        try self.registerValueType(u64);
        try self.registerValueType(bool);
        try self.registerValueType(f64);
        try self.registerValueType(f32);
        try self.registerValueType(u8);
        try self.registerWithMetaData([]const u8, .{
            .name = @typeName([]const u8),
            .kind = .slice,
            .child_type = utils.typeId(u8),
            .call = null,
            .deref = null,
            .ref = null,
            .set = simpleValueSetter([]const u8),
            .component_vtable = null,
            .fields = try self.allocator.dupe(ReflectionField, &.{
                .{
                    .name = "len",
                    .field_type_id = utils.typeId(usize),
                    .get = sliceLenGetter(u8),
                    .set = sliceLenSetter(u8),
                },
            }),
        });
    }

    pub fn registerValueType(self: *TypeRegistry, comptime T: type) !void {
        try self.registerWithMetaData(T, .{
            .name = @typeName(T),
            .kind = .value,
            .child_type = null,
            .fields = &.{},
            .set = simpleValueSetter(T),
            .call = null,
            .deref = null,
            .ref = null,
            .component_vtable = null,
        });
        try self.registerPointer(*T);
    }

    pub fn registerWithMetaData(self: *TypeRegistry, comptime T: type, metadata: ReflectionMetaData) !void {
        const id = utils.typeId(T);
        const name = @typeName(T);
        try self.names_to_ids.put(name, id);
        const meta = try self.allocator.create(ReflectionMetaData);
        meta.* = metadata;
        try self.metadata.put(id, meta);
    }

    pub fn deinit(self: *TypeRegistry) void {
        self.names_to_ids.deinit();
        var values = self.metadata.valueIterator();
        while (values.next()) |v| {
            const fields = v.*.fields;
            const fields_len = fields.len;
            if (fields_len > 0) {
                self.allocator.free(fields);
            }
            self.allocator.destroy(v.*);
        }
        self.metadata.deinit();
    }
};

fn structMetaData(comptime T: type, allocator: std.mem.Allocator) !ReflectionMetaData {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        @compileError("expected a struct");
    }
    const fields = std.meta.fields(T);
    var reflected_fields: [fields.len]ReflectionField = undefined;
    inline for (fields, 0..) |field, idx| {
        const fname: []const u8 = field.name;
        reflected_fields[idx] = .{
            .name = fname,
            .field_type_id = utils.typeId(field.type),
            .get = fieldGetter(T, @enumFromInt(idx)),
            .set = fieldSetter(T, @enumFromInt(idx)),
        };
    }
    const fields_heaped = try allocator.dupe(ReflectionField, &reflected_fields);
    const component_vtable: ?*const component.Opaque.VTable = if (comptime @hasDecl(T, "component_info"))
        component.vtableOf(T)
    else
        null;
    return .{
        .name = @typeName(T),
        .fields = fields_heaped,
        .kind = .value,
        .child_type = null,
        .set = simpleValueSetter(T),
        .call = null,
        .deref = null,
        .ref = null,
        .component_vtable = component_vtable,
    };
}

fn ref(comptime T: type) *const fn (*anyopaque, ReflectedAny) void {
    if (comptime @typeInfo(T) != .pointer) {
        @compileError("expected T to be a pointer");
    }
    const ValT = @typeInfo(T).pointer.child;
    return &struct {
        fn ref(this: *anyopaque, value: ReflectedAny) void {
            const self: *T = @ptrCast(@alignCast(this));
            const child_id = utils.typeId(ValT);
            if (value.type_id != child_id) {
                @panic("trying to set value of pointer to wrong type");
            }
            const casted: *ValT = @ptrCast(@alignCast(value.ptr));
            // deref once to get pointer to value, deref twice to get to value
            self.*.* = casted.*;
        }
    }.ref;
}

fn deref(comptime T: type) *const fn (*anyopaque) ReflectedAny {
    if (comptime @typeInfo(T) != .pointer) {
        @compileError("expected T to be a pointer");
    }
    const ValT = @typeInfo(T).pointer.child;
    return &struct {
        fn deref(this: *anyopaque) ReflectedAny {
            const self: *T = @ptrCast(@alignCast(this));
            return .{
                .ptr = self.*,
                .type_id = utils.typeId(ValT),
            };
        }
    }.deref;
}

fn sliceLenGetter(
    comptime T: type,
) *const fn (*anyopaque) ReflectedAny {
    return &struct {
        fn get(this: *anyopaque) ReflectedAny {
            const self: *[]T = @ptrCast(@alignCast(this));
            return .{
                .ptr = @ptrCast(@alignCast(&self.len)),
                .type_id = utils.typeId(usize),
            };
        }
    }.get;
}

fn sliceLenSetter(
    comptime T: type,
) *const fn (*anyopaque, ReflectedAny) void {
    return &struct {
        fn set(this: *anyopaque, value: ReflectedAny) void {
            const self: *[]T = @ptrCast(@alignCast(this));
            std.debug.assert(value.type_id == utils.typeId(usize));
            const casted: *usize = @ptrCast(@alignCast(value.ptr));
            self.len = casted.*;
        }
    }.set;
}

fn fieldGetter(
    comptime T: type,
    comptime field: std.meta.FieldEnum(T),
) *const fn (*anyopaque) ReflectedAny {
    const fields = std.meta.fields(T);
    const f = fields[@intFromEnum(field)];
    return &struct {
        fn get(this: *anyopaque) ReflectedAny {
            const self: *T = @ptrCast(@alignCast(this));
            const fval = &@field(self, f.name);
            const ptr_id = utils.typeId(@TypeOf(f.type));
            return .{
                .ptr = @ptrCast(@alignCast(fval)),
                .type_id = ptr_id,
            };
        }
    }.get;
}

fn fieldSetter(
    comptime T: type,
    comptime field: std.meta.FieldEnum(T),
) *const fn (*OpaqueSelf, ReflectedAny) void {
    const fields = std.meta.fields(T);
    const f = fields[@intFromEnum(field)];
    return &struct {
        fn set(this: *anyopaque, val: ReflectedAny) void {
            const self: *T = @ptrCast(@alignCast(this));
            const field_id = utils.typeId(f.type);
            if (val.type_id != field_id) {
                @panic("trying to set value of field to a wrong type");
            }
            const val_as_t: *f.type = @ptrCast(@alignCast(val.ptr));
            @field(self, f.name) = val_as_t.*;
        }
    }.set;
}

fn simpleValueSetter(
    comptime T: type,
) *const fn (*anyopaque, ReflectedAny) void {
    return &struct {
        fn set(
            this: *anyopaque,
            other: ReflectedAny,
        ) void {
            const this_id = utils.typeId(T);
            std.debug.assert(this_id == other.type_id);
            const this_ptr: *T = @ptrCast(@alignCast(this));
            const other_ptr: *T = @ptrCast(@alignCast(other.ptr));
            this_ptr.* = other_ptr.*;
        }
    }.set;
}

fn printIndent(indent: usize) void {
    for (0..indent) |i| {
        _ = i;
        std.debug.print("{s}", .{" "});
    }
}

pub fn printReflected(type_registry: *TypeRegistry, id: usize, indent: usize) void {
    const metadata = type_registry.metadata.get(id).?;
    std.debug.print("{s}", .{metadata.name});
    if (metadata.fields.len > 0) {
        std.debug.print(" [\n", .{});
        for (metadata.fields) |*f| {
            printIndent(indent);
            std.debug.print("  {s}: ", .{f.name});
            const field_meta = type_registry.metadata.get(f.field_type_id).?;
            if (field_meta.kind == .pointer) {
                printReflected(type_registry, field_meta.child_type.?, indent + 2);
            } else {
                printReflected(type_registry, f.field_type_id, indent + 2);
            }
        }
        printIndent(indent);
        std.debug.print("]\n", .{});
    } else {
        std.debug.print(",\n", .{});
    }
}
