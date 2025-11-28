const Game = @import("game.zig").Game;
const System = @import("game.zig").System;
const std = @import("std");
const utils = @import("utils.zig");

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
                    @hasDecl(para_t, "resource_proxy_info"))
                {
                    // it's a resource proxy so we will get a resource and creare it
                    var query = game.query(.{@TypeOf(para_t.resource_proxy_info).MappedResource}, .{});
                    const resource = query.single()[0];
                    queries[index] = para_t.fromResource(resource);
                } else if (comptime @typeInfo(para_t) == .pointer and
                    @typeInfo(@typeInfo(para_t).pointer.child) == .@"struct" and
                    @hasDecl(@typeInfo(para_t).pointer.child, "resource_proxy_info"))
                {
                    // it's also a resource proxy but taken by a pointer.
                    // Needed for mutability because zig is weird with its function arguments
                    var query = game.query(.{@TypeOf(@typeInfo(para_t).pointer.child.resource_proxy_info).MappedResource}, .{});
                    const resource = query.single()[0];
                    var mapped = @typeInfo(para_t).pointer.child.fromResource(resource);
                    queries[index] = &mapped;
                } else if (comptime @typeInfo(para_t) == .@"struct" and
                    @hasDecl(para_t, "is_resource_marker"))
                {
                    // this is a resource so we are just going to get it
                    var query = game.query(.{para_t.component_t}, .{});
                    queries[index] = .init(query.single()[0]);
                } else {
                    if (@typeInfo(para_t) != .pointer) {
                        @compileError("Queries have to be accepted by pointer " ++ @typeName(para_t));
                    }
                    // this is a query but we should also get exclusion types
                    const unpack_pointer = @typeInfo(para_t).pointer.child;
                    const component_types = unpack_pointer.ComponentTypes;
                    const exclude_t = unpack_pointer.FilterTypes;
                    if (comptime exclude_t == void) {
                        var query = game.query(component_types, .{});
                        queries[index] = &query;
                    } else {
                        var query = game.query(component_types, exclude_t.ComponentTypes);
                        queries[index] = &query;
                    }
                }
            }
            // Call original function, expanding queries as arguments
            return @call(.auto, F, queries);
        }
    }.call;
}
