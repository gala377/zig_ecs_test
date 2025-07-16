const std = @import("std");
const lua = @import("lua_lib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
        .retain_metadata = true,
    }).init;
    defer {
        switch (gpa.deinit()) {
            .leak => {
                std.debug.print("Leaks found!\n", .{});
            },
            else => {
                std.debug.print("no leaks found\n", .{});
            },
        }
    }
    var luaState = try lua.State.init(gpa.allocator());
    defer luaState.deinit();

    const value = try luaState.exec("return 1 + 4", gpa.allocator());
    std.debug.print("The result is {any}\n", .{value});
    const exec =
        \\local a = "hello";
        \\local b = "world";
        \\return a .. " " .. b;
    ;
    const ret = try luaState.exec(exec, gpa.allocator());
    defer ret.deinit();
    switch (ret) {
        .String => |s| {
            std.debug.print("The result is {s}\n", .{s.value});
        },
        else => unreachable,
    }
    try startRaylib(&luaState, gpa.allocator());
}

const rl = @import("raylib");
const rg = @import("raygui");

fn getColor(hex: i32) rl.Color {
    var color: rl.Color = .black;
    // zig fmt: off
    color.r = @intCast((hex >> 24) & 0xFF);
    color.g = @intCast((hex >> 16) & 0xFF);
    color.b = @intCast((hex >>  8) & 0xFF);
    color.a = @intCast((hex >>  0) & 0xFF);
    // zig fmt: on
    return color;
}

fn makeLuaCloseCheck(l: *lua.State) anyerror!lua.Ref {
    try l.load(
        \\ local firstTime = true;
        \\ return function()
        \\  if firstTime then  
        \\    print "Called lua close function"; 
        \\    firstTime = false;
        \\    return false;
        \\  end
        \\  return true;
        \\ end
    );
    return l.makeRef();
}

fn startRaylib(l: *lua.State, allocator: std.mem.Allocator) anyerror!void {
    rl.setConfigFlags(.{ .window_highdpi = true });
    rl.initWindow(1080, 720, "raygui - controls test suite");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    var show_message_box = false;
    //const color_int = rg.getStyle(.default, .{ .default = .background_color });
    var shouldClose = false;
    const closeFunction = try makeLuaCloseCheck(l);
    defer closeFunction.release();
    while (!shouldClose) : (shouldClose = rl.windowShouldClose() or shouldClose) {
        rl.beginDrawing();

        rl.clearBackground(.black);
        if (rg.button(.init(24, 24, 120, 30), "#191#Show Message")) {
            show_message_box = true;
        }
        if (rg.button(.init(24, 48, 120, 30), "Close")) {
            l.pushRef(closeFunction);
            const res = try l.call(0, 1, allocator);
            switch (res) {
                .Boolean => |inner| {
                    shouldClose = inner;
                },
                else => @panic("Unexpected type, wanted Bool"),
            }
        }
        if (show_message_box) {
            const result = rg.messageBox(
                .init(85, 70, 250, 100),
                "#191#Message Box",
                "Hi! This is a message",
                "Yes;No",
            );
            if (result >= 0) {
                const message: []const u8 = switch (result) {
                    1 => "yes",
                    2 => "no",
                    else => @panic("unknown option"),
                };
                std.debug.print("Chosen option is {s}\n", .{message});
                show_message_box = false;
            }
        }
        rl.endDrawing();
    }
}
