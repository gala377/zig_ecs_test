const std = @import("std");

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
