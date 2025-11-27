const std = @import("std");
const lua = @import("lua_lib");

const component_prefix = @import("build_options").components_prefix;
const component = @import("../component.zig");
const Component = component.LibComponent;
const ExportLua = component.ExportLua;
const ResourceProxy = @import("../mapped.zig").ResourceProxy;
const Resource = @import("../resource.zig").Resource;
const Game = @import("../game.zig").Game;

pub const GameActions = struct {
    pub const component_info = Component(component_prefix, GameActions);
    pub const lua_info = ExportLua(GameActions, .{});

    should_close: bool,
    log: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *GameActions, allocator: std.mem.Allocator) void {
        _ = allocator;
        for (self.log) |log| {
            self.allocator.free(log);
        }
        if (self.log.len > 0) {
            self.allocator.free(self.log);
        }
    }
};

pub const LuaRuntime = struct {
    pub const component_info = Component(component_prefix, LuaRuntime);

    lua: *lua.State,
};

pub fn EventBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const component_info = Component(component_prefix, Self);
        pub const lua_info = ExportLua(Self, .{"allocator"});

        events: []T,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Self) void {
            if (self.events.len > 0) {
                if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "deinit")) {
                    for (self.events) |event| {
                        event.deinit();
                    }
                }
                self.allocator.free(self.events);
                self.events = &.{};
            }
        }
    };
}

pub fn EventReader(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const resource_proxy_info = ResourceProxy(EventBuffer(T));

        buffer: []T,
        pos: usize = 0,

        pub fn fromResource(buffer: *EventBuffer(T)) Self {
            return .{
                .buffer = buffer.events,
            };
        }

        pub fn next(self: *Self) ?T {
            if (self.pos < self.buffer.len) {
                self.pos += 1;
                return self.buffer[self.pos - 1];
            }
            return null;
        }
    };
}

pub fn EventWriterBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const component_info = Component(component_prefix, Self);

        events: std.ArrayList(T),

        pub fn deinit(self: *Self) void {
            if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "deinit")) {
                for (self.events.items) |event| {
                    event.deinit();
                }
            }
            self.events.deinit();
        }
    };
}

pub fn EventWriter(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const resource_proxy_info = ResourceProxy(EventWriterBuffer(T));

        buffer: *std.ArrayList(T),

        pub fn fromResource(buffer: *EventWriterBuffer(T)) Self {
            return .{
                .buffer = &buffer.events,
            };
        }

        pub fn add(self: *const Self, event: T) void {
            self.buffer.append(event) catch @panic("could not add event");
        }
    };
}

pub fn eventSystem(comptime T: type) *const fn (*Game) void {
    return &struct {
        fn call(game: *Game) void {
            const event_buffer = game.getResource(EventBuffer(T));
            const event_writer = game.getResource(EventWriterBuffer(T));
            if (event_writer.inner.events.items.len > 0) {
                const new_buffer = event_writer.inner.events.toOwnedSlice() catch @panic("could not own the slice");
                if (event_buffer.inner.events.len > 0) {
                    event_buffer.inner.deinit();
                }
                event_buffer.inner.events = new_buffer;
            } else if (event_buffer.inner.events.len > 0) {
                // no events to copy but some to free
                event_buffer.inner.deinit();
            }
            // nothing to copy, nothing to free
        }
    }.call;
}
