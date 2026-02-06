const ecs = @import("prelude.zig");

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

/// Used to create a proxy for a resource that can be used as a system parameter.
///
/// type that derives it has to implement
///
/// pub const resource_proxy_info = resource.Proxy(T);
/// fn fromResource(res: *T) Self { ... }
///
/// That returns self when given a resource.
/// This should be really cheap as this will be created every time
/// a system is invoked.
///
/// Then the system will be provided an instance of resource proxy.
///
/// This can be used to provide different interfaces for resources.
/// Like read only / write only interface.
///
/// For examples look at EventReader and EventWriter.
pub fn Proxy(comptime T: type) ProxyMetaData(T) {
    return .{};
}

pub fn ProxyMetaData(comptime T: type) type {
    return struct {
        pub const MappedResource = T;
    };
}

pub const ResourceMarker = struct {
    pub const component_info = ecs.Component(ResourceMarker);
    marker: ecs.Marker = .empty,
};
