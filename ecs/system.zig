const Game = @import("game.zig").Game;
const std = @import("std");
const utils = @import("utils.zig");

pub const SystemVTable = struct {
    run: *const fn (?*anyopaque, *Game) void,
    deinit: *const fn (?*anyopaque) void,
};

pub const System = struct {
    const Self = @This();

    context: ?*anyopaque,
    vtable: *const SystemVTable,

    pub fn run(self: *const Self, game: *Game) void {
        self.vtable.run(self.context, game);
    }

    pub fn deinit(self: *const Self) void {
        self.vtable.deinit(self.context);
    }
};

const ChainContext = struct {
    systems: []const System,
    allocator: std.mem.Allocator,

    pub fn run(ptr: ?*anyopaque, game: *Game) void {
        const context: *ChainContext = @ptrCast(@alignCast(ptr.?));
        for (context.systems) |sys| {
            sys.run(game);
        }
    }

    pub fn deinit(ptr: ?*anyopaque) void {
        const context: *ChainContext = @ptrCast(@alignCast(ptr.?));
        for (context.systems) |sys| {
            sys.deinit();
        }
        context.allocator.free(context.systems);
        context.allocator.destroy(context);
    }
};

pub fn chain(allocator: std.mem.Allocator, systems: []const System) !System {
    const context = try allocator.create(ChainContext);
    context.* = .{
        .systems = try allocator.dupe(System, systems),
        .allocator = allocator,
    };
    return .{
        .context = @ptrCast(@alignCast(context)),
        .vtable = &.{
            .deinit = &ChainContext.deinit,
            .run = &ChainContext.run,
        },
    };
}

fn ignore(context: ?*anyopaque) void {
    _ = context;
}

pub fn system(comptime F: anytype) System {
    return .{
        .context = null,
        .vtable = &.{
            .deinit = &ignore,
            .run = &mkFnSystem(F),
        },
    };
}

fn mkFnSystem(comptime F: anytype) fn (?*anyopaque, *Game) void {
    const info = @typeInfo(@TypeOf(F));
    if (comptime info != .@"fn") {
        @compileError("Expected a function type");
    }
    const params = info.@"fn".params;

    return struct {
        fn call(context: ?*anyopaque, game: *Game) void {
            _ = context;
            // Generate compile-time array of query results
            var queries: std.meta.ArgsTuple(@TypeOf(F)) = undefined;
            inline for (params, 0..) |p, index| {
                const para_t = p.type.?;
                if (comptime para_t == *Game) {
                    // allow accessing game directly
                    queries[index] = game;
                } else if (comptime @typeInfo(para_t) == .@"struct" and
                    @hasDecl(para_t, "resource_proxy_info"))
                {
                    // allow getting resource proxies (readonly)
                    // it's a resource proxy so we will get a resource and creare it
                    var query = game.query(.{@TypeOf(para_t.resource_proxy_info).MappedResource}, .{});
                    const resource = query.single()[0];
                    queries[index] = para_t.fromResource(resource);
                } else if (comptime @typeInfo(para_t) == .pointer and
                    @typeInfo(@typeInfo(para_t).pointer.child) == .@"struct" and
                    @hasDecl(@typeInfo(para_t).pointer.child, "resource_proxy_info"))
                {

                    // allow resource proxies by pointer (not const, can be mutated)
                    // it's also a resource proxy but taken by a pointer.
                    // Needed for mutability because zig is weird with its function arguments
                    var query = game.query(.{@TypeOf(@typeInfo(para_t).pointer.child.resource_proxy_info).MappedResource}, .{});
                    const resource = query.single()[0];
                    var mapped = @typeInfo(para_t).pointer.child.fromResource(resource);
                    queries[index] = &mapped;
                } else if (comptime @typeInfo(para_t) == .@"struct" and
                    @hasDecl(para_t, "is_resource_marker"))
                {
                    // allow resources
                    // this is a resource so we are just going to get it
                    var query = game.query(.{para_t.component_t}, .{});
                    queries[index] = .init(query.single()[0]);
                } else {
                    // allow queries
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

const ConcurrentContext = struct {
    systems: []const System,
    allocator: std.mem.Allocator,

    pub fn run(ptr: ?*anyopaque, game: *Game) void {
        const context: *ConcurrentContext = @ptrCast(@alignCast(ptr.?));
        for (context.systems) |sys| {
            sys.run(game);
        }
    }

    pub fn deinit(ptr: ?*anyopaque) void {
        const context: *ConcurrentContext = @ptrCast(@alignCast(ptr.?));
        for (context.systems) |sys| {
            sys.deinit();
        }
        context.allocator.free(context.systems);
        context.allocator.destroy(context);
    }
};

/// Used to make group of systems concurrent
/// TODO:
/// Doesn't do anything now, it's there for 0.16 Io green threads implementation
pub fn concurrent(allocator: std.mem.Allocator, systems: []const System) !System {
    const context = try allocator.create(ConcurrentContext);
    context.* = .{
        .systems = try allocator.dupe(System, systems),
        .allocator = allocator,
    };
    return .{
        .context = @ptrCast(@alignCast(context)),
        .vtable = &.{
            .deinit = &ConcurrentContext.deinit,
            .run = &ConcurrentContext.run,
        },
    };
}
