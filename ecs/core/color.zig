const Self = @This();
const rl = @import("raylib");

r: u8,
g: u8,
b: u8,
a: u8,

pub const white: Self = .{
    .r = 255,
    .g = 255,
    .b = 255,
    .a = 255,
};

pub const black: Self = .{
    .r = 0,
    .g = 0,
    .b = 0,
    .a = 255,
};

pub fn toRaylib(self: Self) rl.Color {
    return .init(self.r, self.g, self.b, self.a);
}
