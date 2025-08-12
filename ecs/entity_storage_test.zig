const Component = @import("component.zig").Component;
const std = @import("std");
const Storage = @import("entity_storage.zig");
const VTableStorage = @import("comp_vtable_storage.zig");

const Foo = struct {
    pub usingnamespace Component(Foo);
    value: usize,
};
const Bar = struct {
    pub usingnamespace Component(Bar);
    value: usize,
};

test "make an entity with 2 components" {
    const allocator = std.testing.allocator;
    var storage = try Storage.init(allocator);
    defer storage.deinit();
    try storage.makeEntity(0, .{
        Foo{ .value = 1 },
        Bar{ .value = 2 },
    });
}

test "iterate over components" {
    const allocator = std.testing.allocator;
    var storage = try Storage.init(allocator);
    defer storage.deinit();
    try storage.makeEntity(0, .{
        Foo{ .value = 1 },
        Bar{ .value = 2 },
    });

    var iter = storage.query(.{Foo});
    const next = iter.next();
    try std.testing.expect(next != null);
    const comp: *Foo = next.?.@"0";
    try std.testing.expect(comp.value == 1);
    try std.testing.expect(iter.next() == null);
}

test "iterate over multiple components" {
    const allocator = std.testing.allocator;
    var storage = try Storage.init(allocator);
    defer storage.deinit();
    try storage.makeEntity(0, .{
        Foo{ .value = 1 },
        Bar{ .value = 2 },
    });

    var iter = storage.query(.{ Foo, Bar });
    const next = iter.next();
    try std.testing.expect(next != null);
    const foo: *Foo, const bar: *Bar = next.?;
    try std.testing.expect(foo.value == 1);
    try std.testing.expect(bar.value == 2);
    try std.testing.expect(iter.next() == null);
}

test "iterate over multiple archetypes" {
    std.debug.print("\n\n\nTEST TEST\n\n\n", .{});
    const allocator = std.testing.allocator;
    var storage = try Storage.init(allocator);
    defer storage.deinit();
    try storage.makeEntity(0, .{
        Foo{ .value = 1 },
        Bar{ .value = 2 },
    });
    try storage.makeEntity(1, .{
        Foo{ .value = 3 },
    });

    var iter = storage.query(.{Foo});
    var next = iter.next();
    try std.testing.expect(next != null);
    var foo = next.?.@"0";
    try std.testing.expect(foo.value == 1);
    next = iter.next();
    try std.testing.expect(next != null);
    foo = next.?.@"0";
    try std.testing.expect(foo.value == 3);
    try std.testing.expect(iter.next() == null);
}
