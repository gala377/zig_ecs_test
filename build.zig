const std = @import("std");
const Step = std.Build.Step;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main library module with lua imports
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("lua/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addIncludePath(b.path("libs/lua-5.4.8/install/include"));
    lib_mod.addObjectFile(b.path("libs/lua-5.4.8/install/lib/liblua.a"));

    // library target for the library module
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "lua",
        .root_module = lib_mod,
    });
    const check_lua = checkForLuaFiles(b);
    lib.step.dependOn(check_lua);
    b.installArtifact(lib);

    const ecs_mod = b.createModule(.{
        .root_source_file = b.path("ecs/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ecs_mod.addImport("lua_lib", lib_mod);

    const ecs_options = b.addOptions();
    ecs_options.addOption([]const u8, "components_prefix", "ecs");
    ecs_mod.addOptions("build_options", ecs_options);

    const ecs_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "ecs",
        .root_module = ecs_mod,
    });
    // build and link raylib
    const raylib = buildRaylib(b, target, optimize);
    raylib.linkToModule(ecs_lib);
    // build lib
    b.installArtifact(ecs_lib);

    // main executable module
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("lua_lib", lib_mod);
    exe_mod.addImport("ecs", ecs_mod);
    // executable for the executable module
    const exe = b.addExecutable(.{
        .name = "lua",
        .root_module = exe_mod,
    });

    // lua build command
    const build_lua = buildLua(b);

    // run command for the executable
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // build unit tests for the test library
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    // create a test command in the `zig build`
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // builf tests for the executable module
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    // create a runner for exe unit tests
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // create integration tests
    const integration_tests_sources = b.addModule("integration", .{
        .root_source_file = b.path("tests/main.zig"),
        .target = target,
    });
    integration_tests_sources.addImport("ecs", ecs_mod);
    integration_tests_sources.addImport("lua", lib_mod);
    const integration_tests_module = b.addTest(.{
        .name = "integration",
        .root_module = integration_tests_sources,
    });
    const run_integration_tests = b.addRunArtifact(integration_tests_module);

    // create the run command in the `zig build`
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // add lua command to the zig buld, that will build lua
    const lua_step = b.step("lua", "Build lua libraries");
    lua_step.dependOn(&build_lua.step);
    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    const build_exe_step = b.step("build_exe", "Build the main executable");
    build_exe_step.dependOn(&exe.step);

    const intergtaion_tests_step = b.step("integration", "run integration tests");
    intergtaion_tests_step.dependOn(&run_integration_tests.step);
}

fn checkForLuaFiles(b: *std.Build) *Step {
    var check_files = b.step("check-lua-files", "Checks if the lua library files are present. If this fails run `zig build lua`");
    const check_object = b.addCheckFile(b.path("libs/lua-5.4.8/install/lib/liblua.a"), .{});
    check_files.dependOn(&check_object.step);
    const include_files = [_][]const u8{ "lualib.h", "lua.h", "luaconf.h", "lauxlib.h" };
    const include_dir = b.path("libs/lua-5.4.8/install/include");
    for (include_files) |file| {
        const fullpath = include_dir.path(b, file);
        const check_include = b.addCheckFile(fullpath, .{});
        check_files.dependOn(&check_include.step);
    }
    return check_files;
}

fn buildLua(b: *std.Build) *Step.Run {
    const run_make = b.addSystemCommand(&.{ "make", "all", "local" });
    run_make.cwd = b.path("libs/lua-5.4.8");
    return run_make;
}

const RayLibBuild = struct {
    dependency: *std.Build.Dependency,
    raylib: *std.Build.Module,
    raygui: *std.Build.Module,
    artifact: *std.Build.Step.Compile,
    b: *std.Build,

    fn linkToModule(self: RayLibBuild, module: *std.Build.Step.Compile) void {
        module.linkLibrary(self.artifact);
        module.root_module.addImport("raylib", self.raylib);
        module.root_module.addImport("raygui", self.raygui);
    }
};

fn buildRaylib(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) RayLibBuild {
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library
    return .{
        .dependency = raylib_dep,
        .raylib = raylib,
        .raygui = raygui,
        .artifact = raylib_artifact,
        .b = b,
    };
}
