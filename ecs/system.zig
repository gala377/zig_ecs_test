const std = @import("std");
const ecs = @import("prelude.zig");

const utils = ecs.utils;

const Game = ecs.Game;

pub const SystemVTable = struct {
    run: *const fn (?*anyopaque, *Game) anyerror!void,
    deinit: *const fn (?*anyopaque, []const u8) void,
    subsystems: *const fn (?*anyopaque) []const System,
};

pub const System = struct {
    const Self = @This();

    // should be static
    name: []const u8,
    context: ?*anyopaque,
    vtable: *const SystemVTable,

    pub fn run(self: *const Self, game: *Game) anyerror!void {
        return self.vtable.run(self.context, game);
    }

    pub fn deinit(self: *const Self) void {
        self.vtable.deinit(self.context, self.name);
    }

    pub fn subsystems(self: *const Self) []const System {
        return self.vtable.subsystems(self.context);
    }

    pub fn run_if(self: Self, allocator: std.mem.Allocator, comptime F: anytype) System {
        const condition = mkFunctionSystemRet(bool, F);
        const context = allocator.create(ConditionalContext) catch {
            @panic("could not allocate conditional context");
        };
        context.* = .{
            .inner_system = self,
            .allocator = allocator,
        };
        const run_impl = struct {
            pub fn run(ptr: ?*anyopaque, game: *Game) anyerror!void {
                const ctx: *ConditionalContext = @ptrCast(@alignCast(ptr.?));
                if (try condition(null, game)) {
                    try ctx.inner_system.run(game);
                }
            }
        }.run;

        return .{
            .name = "run_if",
            .context = @ptrCast(@alignCast(context)),
            .vtable = &.{
                .run = &run_impl,
                .deinit = &ConditionalContext.deinit,
                .subsystems = &noSubsystems,
            },
        };
    }
};

fn noSubsystems(self: ?*anyopaque) []const System {
    _ = self;
    return &.{};
}

const ConditionalContext = struct {
    inner_system: System,
    allocator: std.mem.Allocator,

    pub fn deinit(ptr: ?*anyopaque, name: []const u8) void {
        _ = name;
        const context: *ConditionalContext = @ptrCast(@alignCast(ptr.?));
        context.inner_system.deinit();
        context.allocator.destroy(context);
    }
};

const ChainContext = struct {
    systems: []const System,
    allocator: std.mem.Allocator,

    pub fn run(ptr: ?*anyopaque, game: *Game) anyerror!void {
        const context: *ChainContext = @ptrCast(@alignCast(ptr.?));
        for (context.systems) |sys| {
            try sys.run(game);
        }
    }

    pub fn deinit(ptr: ?*anyopaque, name: []const u8) void {
        _ = name;
        const context: *ChainContext = @ptrCast(@alignCast(ptr.?));
        for (context.systems) |sys| {
            sys.deinit();
        }
        context.allocator.free(context.systems);
        context.allocator.destroy(context);
    }

    pub fn subsystems(ptr: ?*anyopaque) []const System {
        const context: *ChainContext = @ptrCast(@alignCast(ptr.?));
        return context.systems;
    }
};

pub fn chain(allocator: std.mem.Allocator, systems: []const System) !System {
    const context = try allocator.create(ChainContext);
    context.* = .{
        .systems = try allocator.dupe(System, systems),
        .allocator = allocator,
    };
    return .{
        .name = "chain",
        .context = @ptrCast(@alignCast(context)),
        .vtable = &.{
            .deinit = &ChainContext.deinit,
            .run = &ChainContext.run,
            .subsystems = &ChainContext.subsystems,
        },
    };
}

fn ignore(context: ?*anyopaque, name: []const u8) void {
    _ = name;
    _ = context;
}

pub fn system(comptime F: anytype) System {
    return .{
        .name = @typeName(@TypeOf(F)),
        .context = null,
        .vtable = &.{
            .deinit = &ignore,
            .run = &mkFnSystem(F),
            .subsystems = &noSubsystems,
        },
    };
}

pub fn labeledSystem(name: []const u8, comptime F: anytype) System {
    var s = system(F);
    s.name = name;
    return s;
}

pub const func = system;

fn mkFunctionSystemRet(comptime Ret: type, comptime F: anytype) fn (?*anyopaque, *Game) anyerror!Ret {
    const info = @typeInfo(@TypeOf(F));
    if (comptime info != .@"fn") {
        @compileError("Expected a function type");
    }
    const FnRet = info.@"fn".return_type.?;
    const ret_info = @typeInfo(FnRet);
    comptime {
        const is_error = ret_info == .error_union;
        if (is_error) {
            if (ret_info.error_union.payload != Ret) {
                @compileError("return of the function (excluding error set) and passed type have to match");
            }
        } else {
            if (Ret != FnRet) {
                @compileError("return type of the function and passed type have to match " ++ @typeName(FnRet) ++ " and expected " ++ @typeName(Ret));
            }
        }
    }
    const params = info.@"fn".params;

    return struct {
        fn call(context: ?*anyopaque, game: *Game) anyerror!Ret {
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

fn mkFnSystem(comptime F: anytype) fn (?*anyopaque, *Game) anyerror!void {
    return mkFunctionSystemRet(void, F);
}

const ConcurrentContext = struct {
    systems: []const System,
    allocator: std.mem.Allocator,

    pub fn run(ptr: ?*anyopaque, game: *Game) anyerror!void {
        const context: *ConcurrentContext = @ptrCast(@alignCast(ptr.?));
        for (context.systems) |sys| {
            try sys.run(game);
        }
    }

    pub fn deinit(ptr: ?*anyopaque, name: []const u8) void {
        _ = name;
        const context: *ConcurrentContext = @ptrCast(@alignCast(ptr.?));
        for (context.systems) |sys| {
            sys.deinit();
        }
        context.allocator.free(context.systems);
        context.allocator.destroy(context);
    }

    pub fn subsystems(ptr: ?*anyopaque) []const System {
        const context: *ConcurrentContext = @ptrCast(@alignCast(ptr.?));
        return context.systems;
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
        .name = "concurrent",
        .context = @ptrCast(@alignCast(context)),
        .vtable = &.{
            .deinit = &ConcurrentContext.deinit,
            .run = &ConcurrentContext.run,
            .subsystems = &ConcurrentContext.subsystems,
        },
    };
}
