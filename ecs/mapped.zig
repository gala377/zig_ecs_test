/// Used to create a proxy for a resource that can be used as a system parameter.
///
/// type that derives it has to implement
///
/// pub const resource_proxy_info = ResourceProxy(T);
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
pub fn ResourceProxy(comptime T: type) ResourceProxyInfo(T) {
    return .{};
}

pub fn ResourceProxyInfo(comptime T: type) type {
    return struct {
        pub const MappedResource = T;
    };
}
