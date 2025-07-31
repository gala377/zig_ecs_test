const Component = @import("component.zig").Component;
const LibComponent = @import("component.zig").LibComponent;

pub fn Resource(comptime T: type) type {
    return struct {
        pub const is_resource_marker = void{};
        pub const component_t = T;

        inner: *T,

        pub fn init(value: *T) Resource(T) {
            return .{ .inner = value };
        }

        pub fn get(self: Resource(T)) *T {
            return self.inner;
        }
    };
}
