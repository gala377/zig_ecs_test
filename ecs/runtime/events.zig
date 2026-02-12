const std = @import("std");
const ecs = @import("../prelude.zig");

const component = ecs.component;
const resource = ecs.resource;

const Component = component.Component;
const ExportLua = ecs.ExportLua;
const Resource = ecs.Resource;
const Game = ecs.Game;
const System = ecs.system.System;

pub fn EventBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const component_info = Component(Self);
        pub const lua_info = ExportLua(Self, .{
            .ignored_fields = &.{.allocator},
        });

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

fn noSubsystems(this: ?*anyopaque) []const System {
    _ = this;
    return &.{};
}

pub fn EventReader(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const resource_proxy_info = resource.Proxy(EventBuffer(T));

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
        pub const component_info = Component(Self);

        events: std.ArrayList(T),
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Self) void {
            if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "deinit")) {
                for (self.events.items) |event| {
                    event.deinit();
                }
            }
            self.events.deinit(self.allocator);
        }
    };
}

pub fn EventWriter(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const resource_proxy_info = resource.Proxy(EventWriterBuffer(T));

        buffer: *std.ArrayList(T),
        allocator: std.mem.Allocator,

        pub fn fromResource(buffer: *EventWriterBuffer(T)) Self {
            return .{
                .buffer = &buffer.events,
                .allocator = buffer.allocator,
            };
        }

        pub fn add(self: *const Self, event: T) void {
            self.buffer.append(self.allocator, event) catch @panic("could not add event");
        }
    };
}

fn ignore(context: ?*anyopaque) void {
    _ = context;
}

pub fn eventSystem(comptime T: type) System {
    const run = struct {
        fn call(context: ?*anyopaque, game: *Game) anyerror!void {
            _ = context;
            const event_buffer = game.getResource(EventBuffer(T));
            const event_writer = game.getResource(EventWriterBuffer(T));
            if (event_writer.inner.events.items.len > 0) {
                const new_buffer = try event_writer.inner.events.toOwnedSlice(
                    event_writer.inner.allocator,
                );
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
    return .{
        .name = "event(" ++ @typeName(T) ++ ")",
        .context = null,
        .vtable = &.{
            .deinit = &ignore,
            .run = &run,
            .subsystems = &noSubsystems,
        },
    };
}
