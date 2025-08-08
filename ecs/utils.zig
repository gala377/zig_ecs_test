const std = @import("std");
const ComponentId = @import("component.zig").ComponentId;

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn add_x(self: Vec2, value: f32) Vec2 {
        return .{
            .x = self.x + value,
            .y = self.y,
        };
    }

    pub fn add_y(self: Vec2, value: f32) Vec2 {
        return .{
            .x = self.x,
            .y = self.y + value,
        };
    }
};

pub fn assertSorted(comptime T: type, s: []T) Sorted([]T) {
    if (s.len != 0) {
        for (1..s.len) |idx| {
            const prev = s[idx - 1];
            const curr = s[idx];
            if (prev > curr) {
                unreachable;
            }
        }
    }
    return s;
}
/// Used to mark a slice as sorted.
pub fn Sorted(T: type) type {
    switch (@typeInfo(T)) {
        .pointer => |ptrInfo| if (ptrInfo.size != .slice) {
            @compileError("Sorted only accepts slices");
        },
        else => {},
    }
    return T;
}

/// Accepts a tuple of types and returns a type
/// of a tuple that accepts pointers to those types.
/// Basically maps
/// { 1: type, 2: type, ..., n: type }
/// to
/// { 1: *1, 2: *2, ...,  n: *n }
pub fn PtrTuple(comptime Types: anytype) type {
    const info = @typeInfo(@TypeOf(Types));
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("Expected a tuple of types");
    }

    const fields = info.@"struct".fields;
    // Build new tuple fields, each being a pointer to original type
    var new_fields: [fields.len]std.builtin.Type.StructField = undefined;

    inline for (Types, fields, 0..) |Type, field, i| {
        new_fields[i] = .{
            .name = field.name,
            .type = *Type, // pointer to the original type
            .is_comptime = false,
            .default_value_ptr = null,
            .alignment = @alignOf(*Type),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .is_tuple = true,
            .layout = .auto,
            .fields = &new_fields,
            .decls = &.{},
        },
    });
}

pub fn isSubset(set: Sorted([]const ComponentId), of: Sorted([]const ComponentId)) bool {
    if (set.len > of.len) {
        return false;
    }
    var set_idx: usize = 0;
    var of_idx: usize = 0;
    while (set_idx < set.len and of_idx < of.len) {
        const set_id = set[set_idx];
        const of_id = of[of_idx];
        if (set_id == of_id) {
            set_idx += 1;
            of_idx += 1;
        } else if (set_id > of_id) {
            of_idx += 1;
        } else if (set_id < of_id) {
            // component is higher, meaing we did not find a match
            // for the given id - so this is not the archetype
            return false;
        } else {
            unreachable;
        }
    }
    return set_idx == set.len;
}

pub fn ZigPointer(comptime T: type) type {
    return struct {
        ptr: *T,
    };
}

pub const IdProvider = struct {
    ctx: *anyopaque,
    nextFn: *const fn (*anyopaque) usize,

    pub fn next(self: *const IdProvider) usize {
        const next_id = (self.nextFn)(self.ctx);
        return next_id;
    }
};

pub fn dynamicTypeId(comptime T: type, id_provider: ?IdProvider) usize {
    const id = &struct {
        const _ = T;
        var id: ?usize = null;
    }.id;
    if (id.*) |val| {
        return val;
    }
    if (id_provider == null) {
        @panic("both null cannot do much about it");
    }
    id.* = id_provider.?.next();
    return id.*.?;
}
