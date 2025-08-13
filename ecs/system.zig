const Game = @import("game.zig").Game;
const System = @import("game.zig").System;
const std = @import("std");

pub fn system(comptime F: anytype) System {
    const info = @typeInfo(@TypeOf(F));
    if (comptime info != .@"fn") {
        @compileError("Expected a function type");
    }
    const params = info.@"fn".params;

    return struct {
        fn call(game: *Game) void {
            // Generate compile-time array of query results
            var queries: std.meta.ArgsTuple(@TypeOf(F)) = undefined;
            inline for (params, 0..) |p, index| {
                const para_t = p.type.?;
                if (comptime @typeInfo(para_t) == .@"struct" and
                    @hasDecl(para_t, "is_resource_proxy"))
                {
                    var query = game.query(.{para_t.MappedResource});
                    const resource = query.single()[0];
                    queries[index] = para_t.fromResource(resource);
                } else if (comptime @typeInfo(para_t) == .pointer and
                    @typeInfo(@typeInfo(para_t).pointer.child) == .@"struct" and
                    @hasDecl(@typeInfo(para_t).pointer.child, "is_resource_proxy"))
                {
                    var query = game.query(.{@typeInfo(para_t).pointer.child.MappedResource});
                    const resource = query.single()[0];
                    var mapped = @typeInfo(para_t).pointer.child.fromResource(resource);
                    queries[index] = &mapped;
                } else if (comptime @typeInfo(para_t) == .@"struct" and
                    @hasDecl(para_t, "is_resource_marker"))
                {
                    var query = game.query(.{para_t.component_t});
                    queries[index] = .init(query.single()[0]);
                } else {
                    if (@typeInfo(para_t) != .pointer) {
                        @compileError("Queries have to be accepted by pointer " ++ @typeName(para_t));
                    }
                    const unpack_pointer = @typeInfo(para_t).pointer.child;
                    const component_types = unpack_pointer.ComponentTypes;
                    var query = game.query(component_types);
                    queries[index] = &query;
                }
            }
            // Call original function, expanding queries as arguments
            return @call(.auto, F, queries);
        }
    }.call;
}
