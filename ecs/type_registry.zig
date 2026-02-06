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
    is_const: bool,
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
    optional,
    tagged_union,
    @"enum",
    string,
};

pub const EnumTag = struct {
    tag: usize,
    name: []const u8,
};

pub const ReflectionMetaData = struct {
    /// name of this type
    name: []const u8,
    /// kind of a type, so pointers and so on can have special
    /// handling if needed
    kind: TypeKind,
    /// id of a child type if any,
    child_type: ?usize = null,
    /// if enum list of possible tags
    tags: []const EnumTag = &.{},
    /// information about fields if any
    fields: []const ReflectionField = &.{},
    /// set value of this field from any value
    set: *const fn (*OpaqueSelf, ReflectedAny) void,
    /// If callable can be used to invoke
    call: ?*const fn (*OpaqueSelf, []ReflectedAny) ReflectedAny = null,
    /// If pointer can be used to dereference it
    deref: ?*const fn (*OpaqueSelf) ReflectedAny = null,
    /// If pointer can be used to set underlying memory
    ref: ?*const fn (*OpaqueSelf, ReflectedAny) void = null,
    /// If optional - can be used to get value underneath
    deref_opt: ?*const fn (*OpaqueSelf) ?ReflectedAny = null,
    /// Representation as string
    to_string: ?*const fn (*OpaqueSelf, std.mem.Allocator) std.mem.Allocator.Error![]const u8 = null,
    /// If enum / tagged union - get the enum tag as int
    tag_to_int: ?*const fn (*OpaqueSelf) usize = null,
    /// If enum - set it's tag from int,
    set_tag_from_int: ?*const fn (*OpaqueSelf, tag: usize) void = null,
    /// component vtable if any
    component_vtable: ?*const component.Opaque.VTable = null,
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

    pub fn registerType(self: *TypeRegistry, comptime T: type) std.mem.Allocator.Error!void {
        const id = utils.typeId(T);
        if (self.metadata.contains(id)) {
            return;
        }
        const info = @typeInfo(T);
        switch (info) {
            .@"struct" => {
                return self.registerStruct(T);
            },
            .pointer => |ptr| {
                switch (ptr.size) {
                    .one => {
                        return self.registerPointer(T);
                    },
                    .slice => {
                        std.debug.print("slices not supported for type_registry yet\n", .{});
                    },
                    else => {
                        std.debug.print("many pointers not supported for type_registry yet\n", .{});
                    },
                }
            },
            .@"enum" => {
                try self.registerEnum(T);
            },
            .optional => |opt| {
                try self.registerOptional(T);
                return self.registerType(opt.child);
            },
            .int, .float, .bool => {
                return self.registerValueType(T);
            },
            else => |t| {
                std.debug.print("{s} not supported for type_registry yet\n", .{@tagName(t)});
            },
        }
    }

    pub fn registerEnum(self: *TypeRegistry, comptime T: type) !void {
        try self.registerPointer(*T);
        try self.registerPointer(*const T);
        const info = @typeInfo(T);
        const tags = info.@"enum".fields;
        const static_tags = comptime blk: {
            var temp_tags: [tags.len]EnumTag = undefined;
            for (tags, 0..) |tag, i| {
                temp_tags[i] = .{
                    .tag = tag.value,
                    .name = tag.name,
                };
            }
            // without this line we cannot evaluate this within comptime
            // for some reason
            const final_array = temp_tags;
            break :blk &final_array;
        };
        try self.registerWithMetaData(T, .{
            .name = @typeName(T),
            .kind = .@"enum",
            .tags = static_tags,
            .set = simpleValueSetter(T),
            .to_string = enumToString(T),
            .tag_to_int = tagToInt(T),
            .set_tag_from_int = enumFromInt(T),
        });
    }

    pub fn registerOptional(self: *TypeRegistry, comptime T: type) std.mem.Allocator.Error!void {
        const id = utils.typeId(T);
        if (self.metadata.contains(id)) {
            return;
        }
        try self.registerWithMetaData(T, .{
            .name = @typeName(T),
            .kind = .optional,
            .child_type = utils.typeId(@typeInfo(T).optional.child),
            .set = simpleValueSetter(T),
            .deref_opt = deref_opt(T),
        });
        try self.registerPointer(*T);
        try self.registerPointer(*const T);
    }

    pub fn registerStruct(self: *TypeRegistry, comptime T: type) std.mem.Allocator.Error!void {
        const id = utils.typeId(T);
        if (self.metadata.contains(id)) {
            return;
        }
        const meta = try structMetaData(T, self.allocator);
        try self.registerWithMetaData(T, meta);
        try self.registerType(*T);
        try self.registerType(*const T);
        const info = @typeInfo(T).@"struct";
        inline for (info.fields) |field| {
            try self.registerType(field.type);
        }
    }

    pub fn registerPointer(self: *TypeRegistry, comptime T: type) std.mem.Allocator.Error!void {
        const to_opaque = @typeInfo(@typeInfo(T).pointer.child) == .@"opaque";
        const id = utils.typeId(T);
        if (self.metadata.contains(id)) {
            return;
        }
        try self.registerWithMetaData(T, .{
            .name = @typeName(T),
            .kind = .pointer,
            .child_type = utils.typeId(@typeInfo(T).pointer.child),
            .ref = if (to_opaque) null else ref(T),
            .deref = if (to_opaque) null else deref(T),
            .set = simpleValueSetter(T),
        });
        try self.registerType(@typeInfo(T).pointer.child);
    }

    pub fn registerStdTypes(self: *TypeRegistry) std.mem.Allocator.Error!void {
        try self.registerValueTypeWithToString(usize, allocPrint(usize));
        try self.registerValueTypeWithToString(isize, allocPrint(isize));
        try self.registerValueTypeWithToString(i64, allocPrint(i64));
        try self.registerValueTypeWithToString(i32, allocPrint(i32));
        try self.registerValueTypeWithToString(u32, allocPrint(u32));
        try self.registerValueTypeWithToString(u64, allocPrint(u64));
        try self.registerValueTypeWithToString(bool, allocPrint(bool));
        try self.registerValueTypeWithToString(f64, allocPrint(f64));
        try self.registerValueTypeWithToString(f32, allocPrint(f32));
        try self.registerValueTypeWithToString(u8, allocPrint(u8));
        try self.registerWithMetaData([]const u8, .{
            .name = @typeName([]const u8),
            .kind = .string,
            .child_type = utils.typeId(u8),
            .set = simpleValueSetter([]const u8),
            .to_string = &strToStr,
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

    pub fn registerValueType(self: *TypeRegistry, comptime T: type) std.mem.Allocator.Error!void {
        const id = utils.typeId(T);
        if (self.metadata.contains(id)) {
            return;
        }
        try self.registerWithMetaData(T, .{
            .name = @typeName(T),
            .kind = .value,
            .set = simpleValueSetter(T),
        });
        try self.registerType(*T);
    }

    pub fn registerValueTypeWithToString(
        self: *TypeRegistry,
        comptime T: type,
        to_string: *const fn (*anyopaque, std.mem.Allocator) std.mem.Allocator.Error![]const u8,
    ) std.mem.Allocator.Error!void {
        const id = utils.typeId(T);
        if (self.metadata.contains(id)) {
            return;
        }
        try self.registerWithMetaData(T, .{
            .name = @typeName(T),
            .kind = .value,
            .set = simpleValueSetter(T),
            .to_string = to_string,
        });
        try self.registerType(*T);
        try self.registerType(*const T);
    }

    pub fn registerWithMetaData(self: *TypeRegistry, comptime T: type, metadata: ReflectionMetaData) std.mem.Allocator.Error!void {
        const id = utils.typeId(T);
        if (self.metadata.contains(id)) {
            return;
        }
        const name = @typeName(T);
        try self.names_to_ids.put(name, id);
        const meta = try self.allocator.create(ReflectionMetaData);
        errdefer self.allocator.destroy(meta);
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
            if (@typeInfo(T).pointer.is_const) {
                @panic("cannot set a const pointer");
            }
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
            // pointer to pointer because T is a pointer
            const self: *T = @ptrCast(@alignCast(this));
            return .{
                .ptr = @ptrCast(@alignCast(@constCast(self.*))),
                .type_id = utils.typeId(ValT),
                .is_const = @typeInfo(T).pointer.is_const,
            };
        }
    }.deref;
}

fn sliceLenGetter(
    comptime T: type,
) *const fn (*anyopaque) ReflectedAny {
    return &struct {
        fn get(this: *anyopaque) ReflectedAny {
            const self: *[]T = @ptrCast(@alignCast(@constCast(this)));
            return .{
                .ptr = @ptrCast(@alignCast(&self.len)),
                .type_id = utils.typeId(usize),
                .is_const = false,
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
            const fval: *f.type = &@field(self, f.name);
            const ptr_id = utils.typeId(f.type);
            return .{
                .ptr = @ptrCast(@alignCast(@constCast(fval))),
                .type_id = ptr_id,
                .is_const = false,
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

fn deref_opt(comptime T: type) *const fn (*anyopaque) ?ReflectedAny {
    return &struct {
        fn deref_opt(this: *anyopaque) ?ReflectedAny {
            const info = @typeInfo(T);
            const self: *T = @ptrCast(@alignCast(this));
            if (self.*) |*inner| {
                const id = utils.typeId(info.optional.child);
                return .{
                    .ptr = @ptrCast(@alignCast(inner)),
                    .type_id = id,
                    .is_const = false,
                };
            } else {
                return null;
            }
        }
    }.deref_opt;
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

fn allocPrint(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    return &struct {
        fn to_string(this: *anyopaque, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
            const as_t: *T = @ptrCast(@alignCast(this));
            return std.fmt.allocPrint(allocator, "{any}", .{as_t.*});
        }
    }.to_string;
}

fn enumToString(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    return &struct {
        fn enumToString(this: *anyopaque, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
            const self: *T = @ptrCast(@alignCast(this));
            const name = @tagName(self.*);
            return allocator.dupe(u8, name);
        }
    }.enumToString;
}

fn tagToInt(comptime T: type) *const fn (*anyopaque) usize {
    return &struct {
        fn tagToInt(this: *anyopaque) usize {
            const self: *T = @ptrCast(@alignCast(this));
            return @intFromEnum(self.*);
        }
    }.tagToInt;
}

fn enumFromInt(comptime T: type) *const fn (*anyopaque, usize) void {
    return &struct {
        fn enumFromInt(this: *anyopaque, tag: usize) void {
            const self: *T = @ptrCast(@alignCast(this));
            const new_val: T = @enumFromInt(tag);
            self.* = new_val;
        }
    }.enumFromInt;
}

fn strToStr(this: *anyopaque, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    const self: *[]const u8 = @ptrCast(@alignCast(this));
    return std.fmt.allocPrint(allocator, "\"{s}\"", .{self.*});
}
