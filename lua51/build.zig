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

        .version = .{ .major = 5, .minor = 1, .patch = 5 },
    }) else b.addStaticLibrary(.{
        .name = "liblua",
        .target = target,
        .optimize = optimize,
        .link_libc = true,

        .version = .{ .major = 5, .minor = 1, .patch = 5 },
    });

    liblua.root_module.linkSystemLibrary("m", .{});

    liblua.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &.{
            "lapi.c",     "lcode.c",   "ldebug.c",  "ldo.c",      "ldump.c",
            "lfunc.c",    "lgc.c",     "llex.c",    "lmem.c",     "lobject.c",
            "lopcodes.c", "lparser.c", "lstate.c",  "lstring.c",  "ltable.c",
            "ltm.c",      "lundump.c", "lvm.c",     "lzio.c",     "lauxlib.c",
            "lbaselib.c", "ldblib.c",  "liolib.c",  "lmathlib.c", "loslib.c",
            "ltablib.c",  "lstrlib.c", "loadlib.c", "linit.c",
        },
    });

    liblua.installHeader(upstream.path("src/lua.h"), "lua.h");
    liblua.installHeader(upstream.path("etc/lua.hpp"), "lua.hpp");
    liblua.installHeader(upstream.path("src/luaconf.h"), "luaconf.h");
    liblua.installHeader(upstream.path("src/lualib.h"), "lualib.h");
    liblua.installHeader(upstream.path("src/lauxlib.h"), "lauxlib.h");

    const luac = b.addExecutable(.{
        .name = "luac",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    luac.linkLibrary(liblua);
    luac.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &.{ "luac.c", "print.c" },
    });

    const lua = b.addExecutable(.{
        .name = "lua",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    lua.linkLibrary(liblua);
    lua.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &.{"lua.c"},
    });
    
    liblua.root_module.addCMacro("LUAI_FUNC", "extern");

    if (target.result.isDarwin()) {
        liblua.root_module.addCMacro("LUA_USE_MACOSX", "1");
        luac.root_module.addCMacro("LUA_USE_MACOSX", "1");
        lua.root_module.addCMacro("LUA_USE_MACOSX", "1");
    } else if (target.result.os.tag != .windows) {
        liblua.root_module.addCMacro("LUA_USE_POSIX", "1");
        luac.root_module.addCMacro("LUA_USE_POSIX", "1");
        lua.root_module.addCMacro("LUA_USE_POSIX", "1");

        liblua.root_module.linkSystemLibrary("dl", .{});
        liblua.root_module.addCMacro("LUA_USE_DLOPEN", "1");
    }

    if (optimize == .Debug) {
        liblua.root_module.addCMacro("LUA_USE_APICHECK", "1");
    }

    b.installArtifact(luac);
    b.installArtifact(lua);

    b.getInstallStep().dependOn(&b.addInstallArtifact(liblua, .{
        .dest_sub_path = b.fmt("liblua{s}", .{
            if (shared)
                target.result.dynamicLibSuffix()
            else
                target.result.staticLibSuffix(),
        }),
    }).step);
}

const std = @import("std");
