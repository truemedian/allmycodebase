pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.option(bool, "shared", "Build Lua as a shared library.") orelse false;
    const upstream = b.dependency("lua", .{});

    const liblua = if (shared) b.addSharedLibrary(.{
        .name = "liblua",
        .target = target,
        .optimize = optimize,
        .link_libc = true,

        .version = .{ .major = 5, .minor = 4, .patch = 7 },
    }) else b.addStaticLibrary(.{
        .name = "liblua",
        .target = target,
        .optimize = optimize,
        .link_libc = true,

        .version = .{ .major = 5, .minor = 4, .patch = 7 },
    });

    liblua.root_module.sanitize_c = false;
    liblua.root_module.linkSystemLibrary("m", .{});

    liblua.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &.{
            "lapi.c",     "lcode.c",    "lctype.c",   "ldebug.c",   "ldo.c",
            "ldump.c",    "lfunc.c",    "lgc.c",      "llex.c",     "lmem.c",
            "lobject.c",  "lopcodes.c", "lparser.c",  "lstate.c",   "lstring.c",
            "ltable.c",   "ltm.c",      "lundump.c",  "lvm.c",      "lzio.c",
            "lauxlib.c",  "lbaselib.c", "lcorolib.c", "ldblib.c",   "liolib.c",
            "lmathlib.c", "loslib.c",   "ltablib.c",  "lutf8lib.c", "lstrlib.c",
            "loadlib.c",  "linit.c",
        },
    });

    liblua.installHeader(upstream.path("src/lua.h"), "lua.h");
    liblua.installHeader(upstream.path("src/lua.hpp"), "lua.hpp");
    liblua.installHeader(upstream.path("src/luaconf.h"), "luaconf.h");
    liblua.installHeader(upstream.path("src/lualib.h"), "lualib.h");
    liblua.installHeader(upstream.path("src/lauxlib.h"), "lauxlib.h");

    const luac = b.addExecutable(.{
        .name = "luac",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    luac.root_module.sanitize_c = false;
    luac.linkLibrary(liblua);
    luac.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &.{"luac.c"},
    });

    const lua = b.addExecutable(.{
        .name = "lua",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    lua.root_module.sanitize_c = false;
    lua.linkLibrary(liblua);
    lua.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &.{"lua.c"},
    });

    liblua.root_module.addCMacro("LUA_COMPAT_5_3", "1");
    luac.root_module.addCMacro("LUA_COMPAT_5_3", "1");
    lua.root_module.addCMacro("LUA_COMPAT_5_3", "1");

    if (target.result.os.tag != .windows) {
        liblua.root_module.addCMacro("LUA_USE_POSIX", "1");
        luac.root_module.addCMacro("LUA_USE_POSIX", "1");
        lua.root_module.addCMacro("LUA_USE_POSIX", "1");

        liblua.root_module.linkSystemLibrary("dl", .{});
        liblua.root_module.addCMacro("LUA_USE_DLOPEN", "1");
    }

    if (optimize == .Debug) {
        liblua.root_module.addCMacro("LUA_USE_APICHECK", "1");
    }

    b.installArtifact(lua);
    if (!shared) // we can only provide luac when static linking
        b.installArtifact(luac);

    b.getInstallStep().dependOn(&b.addInstallArtifact(liblua, .{
        .dest_sub_path = b.fmt("liblua{s}", .{
            if (shared)
                target.result.dynamicLibSuffix()
            else
                target.result.staticLibSuffix(),
        }),
    }).step);

    const test_step = b.step("test", "Run Lua tests");
    const upstream_tests = b.dependency("lua-test", .{});

    const run_tests = b.addRunArtifact(lua);
    run_tests.addArg("-e");
    run_tests.addArg("_U=true");
    run_tests.addFileArg(upstream_tests.path("all.lua"));
    run_tests.cwd = upstream_tests.path("");

    test_step.dependOn(&run_tests.step);
}

const std = @import("std");
