pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const target_cpu = target.result.cpu;
    const target_os = target.result.os;

    const shared = b.option(bool, "shared", "Build Lua as a shared library.") orelse false;
    const upstream = b.dependency("luajit", .{});

    const disable_compat = b.option(bool, "enable-compat52", "Enable potentially breaking Lua 5.2 compatibility features") orelse true;
    const disable_jit = b.option(bool, "disable-jit", "Disable JIT compilation") orelse false;
    const disable_ffi = b.option(bool, "disable-ffi", "Disable FFI support") orelse false;
    const disable_gc64 = b.option(bool, "disable-gc64", "Disable 64-bit GC") orelse false;
    const enable_dualnum = b.option(bool, "enable-dualnum", "Enable dual-number mode when possible") orelse false;

    const liblua = if (shared) b.addSharedLibrary(.{
        .name = "liblua",
        .target = target,
        .optimize = optimize,
        .link_libc = true,

        .version = .{ .major = 5, .minor = 1, .patch = 0 },
        .omit_frame_pointer = optimize != .Debug,
    }) else b.addStaticLibrary(.{
        .name = "liblua",
        .target = target,
        .optimize = optimize,
        .link_libc = true,

        .version = .{ .major = 5, .minor = 1, .patch = 0 },
        .omit_frame_pointer = optimize != .Debug,
    });

    const luajit = b.addExecutable(.{
        .name = "luajit",
        .target = target,
        .optimize = optimize,
        .link_libc = true,

        .omit_frame_pointer = optimize != .Debug,
    });

    b.installArtifact(liblua);
    b.installArtifact(luajit);

    // Build minilua for the host and run dynasm to generate buildvm_arch.h
    const minilua = b.addExecutable(.{
        .name = "minilua",
        .target = b.graph.host,
        .optimize = optimize,
        .link_libc = true,
    });

    minilua.root_module.sanitize_c = false;
    minilua.addCSourceFiles(.{
        .root = upstream.path("src/host"),
        .files = minilua_sources,
    });

    // Generate luajit.h from luajit_rolling.h
    const generate_luajit_h = b.addRunArtifact(minilua);
    generate_luajit_h.addFileArg(upstream.path("src/host/genversion.lua"));
    generate_luajit_h.addFileArg(upstream.path("src/luajit_rolling.h"));
    generate_luajit_h.addFileArg(upstream.path(".relver"));
    const luajit_h = generate_luajit_h.addOutputFileArg("luajit.h");

    // buildvm needs to have the same pointer size as the target
    var buildvm_target = b.graph.host;
    if (buildvm_target.result.ptrBitWidth() != target.result.ptrBitWidth()) {
        switch (buildvm_target.result.cpu.arch) {
            .x86 => buildvm_target.query.cpu_arch = .x86_64,
            .x86_64 => buildvm_target.query.cpu_arch = .x86,
            else => std.debug.panic("cross-build with mismatched pointer sizes: {s}", .{@tagName(buildvm_target.result.cpu.arch)}),
        }

        buildvm_target = b.resolveTargetQuery(.{
            .cpu_arch = buildvm_target.query.cpu_arch,
        });
    }

    // Build buildvm for the host to generate the target-specific headers
    const buildvm = b.addExecutable(.{
        .name = "buildvm",
        .target = buildvm_target,
        .optimize = optimize,
        .link_libc = true,
    });

    buildvm.root_module.sanitize_c = false;
    buildvm.addCSourceFiles(.{
        .root = upstream.path("src/host"),
        .files = buildvm_sources,
    });

    // Generate buildvm_arch.h from the dynasm source files
    const dynasm_run = b.addRunArtifact(minilua);
    dynasm_run.addFileArg(upstream.path("dynasm/dynasm.lua"));

    if (target_cpu.arch.endian() == .little) {
        dynasm_run.addArgs(&.{ "-D", "ENDIAN_LE" });
    } else {
        dynasm_run.addArgs(&.{ "-D", "ENDIAN_BE" });
    }

    if (target.result.ptrBitWidth() == 64)
        dynasm_run.addArgs(&.{ "-D", "P64" });

    // not (ios or console or disable_jit)
    if (target_os.tag != .ios and // LJ_TARGET_IOS
        target_os.tag != .lv2 and // LJ_TARGET_CONSOLE
        target_os.tag != .ps4 and // LJ_TARGET_CONSOLE
        target_os.tag != .ps5 and // LJ_TARGET_CONSOLE
        !disable_jit)
    {
        dynasm_run.addArgs(&.{ "-D", "JIT" });
    }

    // not ((ppc and console) or disable_ffi)
    if ((!target_cpu.arch.isPPC() or
        (target_os.tag != .lv2 and
        target_os.tag != .ps4 and
        target_os.tag != .ps5)) and
        !disable_ffi)
    {
        dynasm_run.addArgs(&.{ "-D", "FFI" });
    }

    if ((target_cpu.arch.isX86() and enable_dualnum) or
        target_cpu.arch.isARM() or
        target_cpu.arch.isAARCH64() or
        target_cpu.arch.isPPC() or
        target_cpu.arch.isPPC64() or
        target_cpu.arch.isMIPS())
    {
        dynasm_run.addArgs(&.{ "-D", "DUALNUM" });
    }

    // Check for floating point emulation
    if ((target_cpu.arch.isARM() and isFeatureEnabled(target_cpu, std.Target.arm, "soft_float")) or // ARM
        ((target_cpu.arch.isPPC() or target_cpu.arch.isPPC64()) and !isFeatureEnabled(target_cpu, std.Target.powerpc, "hard_float")) or // PPC
        (target_cpu.arch.isMIPS() and isFeatureEnabled(target_cpu, std.Target.mips, "soft_float"))) // MIPS
    {
        buildvm.root_module.addCMacro("LJ_ARCH_HASFPU", "0");
        buildvm.root_module.addCMacro("LJ_ABI_SOFTFP", "1");
    } else {
        dynasm_run.addArgs(&.{ "-D", "FPU" });
        dynasm_run.addArgs(&.{ "-D", "HFABI" });

        buildvm.root_module.addCMacro("LJ_ARCH_HASFPU", "1");
        buildvm.root_module.addCMacro("LJ_ABI_SOFTFP", "0");
    }

    if (target_os.tag == .ios or // LJ_TARGET_IOS
        target_os.tag == .lv2 or // LJ_TARGET_CONSOLE
        target_os.tag == .ps4 or // LJ_TARGET_CONSOLE
        target_os.tag == .ps5) // LJ_TARGET_CONSOLE
    {
        dynasm_run.addArgs(&.{ "-D", "NO_UNWIND" });
        buildvm.root_module.addCMacro("LUAJIT_NO_UNWIND", "1");
    }

    if (target_cpu.arch.isAARCH64() and isFeatureEnabled(target_cpu, std.Target.aarch64, "pauth")) {
        dynasm_run.addArgs(&.{ "-D", "PAUTH" });
        buildvm.root_module.addCMacro("LJ_ABI_PAUTH", "1");
    }

    if (target_cpu.arch.isARM()) {
        if (isFeatureEnabled(target_cpu, std.Target.arm, "has_v8")) {
            dynasm_run.addArgs(&.{ "-D", "VER=80" });
        } else if (isFeatureEnabled(target_cpu, std.Target.arm, "has_v7")) {
            dynasm_run.addArgs(&.{ "-D", "VER=70" });
        } else if (isFeatureEnabled(target_cpu, std.Target.arm, "has_v6t2")) {
            dynasm_run.addArgs(&.{ "-D", "VER=61" });
        } else if (isFeatureEnabled(target_cpu, std.Target.arm, "has_v6")) {
            dynasm_run.addArgs(&.{ "-D", "VER=60" });
        } else {
            dynasm_run.addArgs(&.{ "-D", "VER=50" });
        }
    } else if (target_cpu.arch.isAARCH64()) {
        dynasm_run.addArgs(&.{ "-D", "VER=80" });
    } else if (target_cpu.arch.isPPC() or target_cpu.arch.isPPC64()) {
        if (target_cpu.features.isSuperSetOf(std.Target.powerpc.cpu.pwr7.features)) {
            dynasm_run.addArgs(&.{ "-D", "VER=70" });
        } else if (target_cpu.features.isSuperSetOf(std.Target.powerpc.cpu.pwr6.features)) {
            dynasm_run.addArgs(&.{ "-D", "VER=60" });
        } else if (target_cpu.features.isSuperSetOf(std.Target.powerpc.cpu.pwr5x.features)) {
            dynasm_run.addArgs(&.{ "-D", "VER=51" });
            dynasm_run.addArgs(&.{ "-D", "ROUND" });
        } else if (target_cpu.features.isSuperSetOf(std.Target.powerpc.cpu.pwr5.features)) {
            dynasm_run.addArgs(&.{ "-D", "VER=50" });
        } else if (target_cpu.features.isSuperSetOf(std.Target.powerpc.cpu.pwr4.features)) {
            dynasm_run.addArgs(&.{ "-D", "VER=40" });
        } else {
            dynasm_run.addArgs(&.{ "-D", "VER=0" });
        }
    }

    if (target_os.tag == .windows) {
        dynasm_run.addArgs(&.{ "-D", "WIN" });
    } else if (target_os.tag == .ios) {
        dynasm_run.addArgs(&.{ "-D", "IOS" });
    }

    if (target_cpu.features.isSuperSetOf(std.Target.mips.cpu.mips32r6.features) or
        target_cpu.features.isSuperSetOf(std.Target.mips.cpu.mips64r6.features))
    {
        dynasm_run.addArgs(&.{ "-D", "MIPSR6" });
    }

    if (target_cpu.arch.isPPC() or target_cpu.arch.isPPC64()) {
        if (isFeatureEnabled(target_cpu, std.Target.powerpc, "fsqrt"))
            dynasm_run.addArgs(&.{ "-D", "SQRT" });

        if (target_os.tag == .lv2) {
            dynasm_run.addArgs(&.{ "-D", "PPE", "-D", "TOC" });
            buildvm.root_module.addCMacro("__CELLOS_LV2__", "1");
        }
    }

    if (target_cpu.arch.isPPC() and (target_os.tag == .lv2 or target_os.tag == .ps4 or target_os.tag == .ps5))
        dynasm_run.addArgs(&.{ "-D", "GPR64" });

    dynasm_run.addArg("-o");
    const buildvm_arch_h = dynasm_run.addOutputFileArg("buildvm_arch.h");
    dynasm_run.addArg("-L"); // dynasm produces bad output with windows file paths for line numbers, so disable them

    switch (target_cpu.arch) {
        .x86 => dynasm_run.addFileArg(upstream.path("src/vm_x86.dasc")),
        .x86_64 => dynasm_run.addFileArg(upstream.path("src/vm_x64.dasc")),
        .arm, .armeb, .aarch64_32 => dynasm_run.addFileArg(upstream.path("src/vm_arm.dasc")),
        .aarch64, .aarch64_be => dynasm_run.addFileArg(upstream.path("src/vm_arm64.dasc")),
        .powerpc, .powerpcle, .powerpc64, .powerpc64le => dynasm_run.addFileArg(upstream.path("src/vm_ppc.dasc")),
        .mips, .mipsel => dynasm_run.addFileArg(upstream.path("src/vm_mips.dasc")),
        .mips64, .mips64el => dynasm_run.addFileArg(upstream.path("src/vm_mips64.dasc")),
        else => std.debug.panic("unsupported target architecture: {s}", .{@tagName(target_cpu.arch)}),
    }

    switch (target_cpu.arch) {
        .x86 => buildvm.root_module.addCMacro("LUAJIT_TARGET", "LUAJIT_ARCH_x86"),
        .x86_64 => buildvm.root_module.addCMacro("LUAJIT_TARGET", "LUAJIT_ARCH_x64"),
        .arm, .armeb, .aarch64_32 => buildvm.root_module.addCMacro("LUAJIT_TARGET", "LUAJIT_ARCH_arm"),
        .aarch64, .aarch64_be => buildvm.root_module.addCMacro("LUAJIT_TARGET", "LUAJIT_ARCH_arm64"),
        .powerpc, .powerpcle, .powerpc64, .powerpc64le => buildvm.root_module.addCMacro("LUAJIT_TARGET", "LUAJIT_ARCH_ppc"),
        .mips, .mipsel => buildvm.root_module.addCMacro("LUAJIT_TARGET", "LUAJIT_ARCH_mips"),
        .mips64, .mips64el => buildvm.root_module.addCMacro("LUAJIT_TARGET", "LUAJIT_ARCH_mips64"),
        else => unreachable,
    }

    // Prepare to run buildvm generations
    if (!disable_compat)
        buildvm.root_module.addCMacro("LUAJIT_ENABLE_LUA52COMPAT", "1");

    if (disable_jit)
        buildvm.root_module.addCMacro("LUAJIT_DISABLE_JIT", "1");

    if (disable_ffi)
        buildvm.root_module.addCMacro("LUAJIT_DISABLE_FFI", "1");

    if (disable_gc64)
        buildvm.root_module.addCMacro("LUAJIT_DISABLE_GC64", "1");

    if (target_cpu.arch == .aarch64_be) {
        buildvm.root_module.addCMacro("__AARCH64EB__", "1");
    } else if (target_cpu.arch.isPPC() or target_cpu.arch.isPPC64()) {
        if (target_cpu.arch.endian() == .little) {
            buildvm.root_module.addCMacro("LJ_ARCH_ENDIAN", "LUAJIT_LE");
        } else {
            buildvm.root_module.addCMacro("LJ_ARCH_ENDIAN", "LUAJIT_BE");
        }
    } else if (target_cpu.arch.isMIPS() and target_cpu.arch.endian() == .little) {
        buildvm.root_module.addCMacro("__MIPSEL__", "1");
    }

    if (target_os.tag != b.graph.host.result.os.tag) {
        if (target_os.tag == .windows) {
            buildvm.root_module.addCMacro("LUAJIT_OS", "LUAJIT_OS_WINDOWS");
        } else if (target_os.tag == .linux) {
            buildvm.root_module.addCMacro("LUAJIT_OS", "LUAJIT_OS_LINUX");
        } else if (target_os.tag.isDarwin()) {
            buildvm.root_module.addCMacro("LUAJIT_OS", "LUAJIT_OS_OSX");

            if (target_os.tag == .ios)
                buildvm.root_module.addCMacro("TARGET_OS_IPHONE", "1");
        } else {
            buildvm.root_module.addCMacro("LUAJIT_OS", "LUAJIT_OS_OTHER");
        }
    }

    buildvm.addIncludePath(luajit_h.dirname());
    buildvm.addIncludePath(buildvm_arch_h.dirname());
    buildvm.addIncludePath(upstream.path("src"));

    const buildvm_bcdef = b.addRunArtifact(buildvm);
    buildvm_bcdef.addArgs(&.{ "-m", "bcdef", "-o" });
    const lj_bcdef_h = buildvm_bcdef.addOutputFileArg("lj_bcdef.h");
    for (lib_sources) |source| {
        buildvm_bcdef.addFileArg(upstream.path("src").path(b, source));
    }

    const buildvm_ffdef = b.addRunArtifact(buildvm);
    buildvm_ffdef.addArgs(&.{ "-m", "ffdef", "-o" });
    const lj_ffdef_h = buildvm_ffdef.addOutputFileArg("lj_ffdef.h");
    for (lib_sources) |source| {
        buildvm_ffdef.addFileArg(upstream.path("src").path(b, source));
    }

    const buildvm_libdef = b.addRunArtifact(buildvm);
    buildvm_libdef.addArgs(&.{ "-m", "libdef", "-o" });
    const lj_libdef_h = buildvm_libdef.addOutputFileArg("lj_libdef.h");
    for (lib_sources) |source| {
        buildvm_libdef.addFileArg(upstream.path("src").path(b, source));
    }

    const buildvm_recdef = b.addRunArtifact(buildvm);
    buildvm_recdef.addArgs(&.{ "-m", "recdef", "-o" });
    const lj_recdef_h = buildvm_recdef.addOutputFileArg("lj_recdef.h");
    for (lib_sources) |source| {
        buildvm_recdef.addFileArg(upstream.path("src").path(b, source));
    }

    const buildvm_vmdef = b.addRunArtifact(buildvm);
    buildvm_vmdef.addArgs(&.{ "-m", "vmdef", "-o" });
    const vmdef_lua = buildvm_vmdef.addOutputFileArg("vmdef.lua");
    for (lib_sources) |source| {
        buildvm_vmdef.addFileArg(upstream.path("src").path(b, source));
    }

    const buildvm_folddef = b.addRunArtifact(buildvm);
    buildvm_folddef.addArgs(&.{ "-m", "folddef", "-o" });
    const lj_folddef_h = buildvm_folddef.addOutputFileArg("lj_folddef.h");
    buildvm_folddef.addFileArg(upstream.path("src").path(b, "lj_opt_fold.c"));

    const buildvm_ljvm = b.addRunArtifact(buildvm);
    if (target_os.tag == .windows) {
        buildvm_ljvm.addArgs(&.{ "-m", "peobj", "-o" });
    } else if (target_os.tag.isDarwin()) {
        buildvm_ljvm.addArgs(&.{ "-m", "machasm", "-o" });
    } else {
        buildvm_ljvm.addArgs(&.{ "-m", "elfasm", "-o" });
    }
    const lj_vm_s = if (target_os.tag == .windows)
        buildvm_ljvm.addOutputFileArg("lj_vm.obj")
    else
        buildvm_ljvm.addOutputFileArg("lj_vm.S");

    // Build LuaJIT

    const install_jit = b.addInstallDirectory(.{
        .source_dir = upstream.path("src/jit"),
        .install_dir = .prefix,
        .install_subdir = "jit",
        .exclude_extensions = &.{".gitignore"},
    });

    const install_vmdef = b.addInstallFileWithDir(vmdef_lua, .{ .custom = "jit" }, "vmdef.lua");

    liblua.root_module.stack_protector = false;
    liblua.root_module.addCMacro("LUAJIT_UNWIND_EXTERNAL", "1");
    liblua.root_module.linkSystemLibrary("unwind", .{ .needed = true });

    liblua.addIncludePath(upstream.path("src"));
    liblua.addIncludePath(luajit_h.dirname());
    liblua.addIncludePath(lj_bcdef_h.dirname());
    liblua.addIncludePath(lj_ffdef_h.dirname());
    liblua.addIncludePath(lj_libdef_h.dirname());
    liblua.addIncludePath(lj_recdef_h.dirname());
    liblua.addIncludePath(lj_folddef_h.dirname());

    liblua.installHeader(upstream.path("src/lua.h"), "lua.h");
    liblua.installHeader(upstream.path("src/luaconf.h"), "luaconf.h");
    liblua.installHeader(upstream.path("src/lualib.h"), "lualib.h");
    liblua.installHeader(upstream.path("src/lauxlib.h"), "lauxlib.h");
    liblua.installHeader(luajit_h, "luajit.h");

    if (target_os.tag == .windows) {
        liblua.addObjectFile(lj_vm_s);
    } else {
        liblua.addAssemblyFile(lj_vm_s);
    }

    liblua.root_module.sanitize_c = false;
    liblua.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = base_sources,
    });

    liblua.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = lib_sources,
    });

    if (target_os.tag == .windows) {
        liblua.addCSourceFile(.{ .file = upstream.path("src/lj_err.c") });
    } else {
        // This is a hack that needs to be verified to work every time lj_err changes. Zig's libunwind matches the Apple libunwind
        liblua.addCSourceFile(.{ .file = upstream.path("src/lj_err.c"), .flags = &.{"-DLUAJIT_OS=LUAJIT_OS_OSX"} });
    }

    if (!disable_compat)
        liblua.root_module.addCMacro("LUAJIT_ENABLE_LUA52COMPAT", "1");

    if (disable_jit)
        liblua.root_module.addCMacro("LUAJIT_DISABLE_JIT", "1");

    if (disable_ffi)
        liblua.root_module.addCMacro("LUAJIT_DISABLE_FFI", "1");

    if (disable_gc64)
        liblua.root_module.addCMacro("LUAJIT_DISABLE_GC64", "1");

    if (optimize == .Debug)
        liblua.root_module.addCMacro("LUA_USE_APICHECK", "1");

    liblua.step.dependOn(&install_vmdef.step);
    liblua.step.dependOn(&install_jit.step);

    luajit.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = exe_sources,
    });

    luajit.rdynamic = true;
    luajit.linkLibrary(liblua);
}

/// Helper function to check if a feature is enabled for a given CPU.
fn isFeatureEnabled(cpu: std.Target.Cpu, comptime arch: type, comptime feature: []const u8) bool {
    return cpu.features.isEnabled(@intFromEnum(@field(arch.Feature, feature)));
}

const lua_version = std.SemanticVersion{ .major = 5, .minor = 1, .patch = 0 };

const minilua_sources: []const []const u8 = &.{"minilua.c"};

const buildvm_sources: []const []const u8 = &.{
    "buildvm_asm.c", "buildvm_fold.c", "buildvm_lib.c", "buildvm_peobj.c", "buildvm.c",
};

const lib_sources: []const []const u8 = &.{
    "lib_base.c",    "lib_math.c",  "lib_bit.c", "lib_string.c", "lib_table.c",  "lib_io.c", "lib_os.c",
    "lib_package.c", "lib_debug.c", "lib_jit.c", "lib_ffi.c",    "lib_buffer.c",
};

const base_sources: []const []const u8 = &.{
    "lj_assert.c",    "lj_gc.c",         "lj_char.c",      "lj_bc.c",       "lj_obj.c",       "lj_buf.c",
    "lj_str.c",       "lj_tab.c",        "lj_func.c",      "lj_udata.c",    "lj_meta.c",      "lj_debug.c",
    "lj_prng.c",      "lj_state.c",      "lj_dispatch.c",  "lj_vmevent.c",  "lj_vmmath.c",    "lj_strscan.c",
    "lj_strfmt.c",    "lj_strfmt_num.c", "lj_serialize.c", "lj_api.c",      "lj_profile.c",   "lj_lex.c",
    "lj_parse.c",     "lj_bcread.c",     "lj_bcwrite.c",   "lj_load.c",     "lj_ir.c",        "lj_opt_mem.c",
    "lj_opt_fold.c",  "lj_opt_narrow.c", "lj_opt_dce.c",   "lj_opt_loop.c", "lj_opt_split.c", "lj_opt_sink.c",
    "lj_mcode.c",     "lj_snap.c",       "lj_record.c",    "lj_crecord.c",  "lj_ffrecord.c",  "lj_asm.c",
    "lj_trace.c",     "lj_gdbjit.c",     "lj_ctype.c",     "lj_cdata.c",    "lj_cconv.c",     "lj_ccall.c",
    "lj_ccallback.c", "lj_carith.c",     "lj_clib.c",      "lj_cparse.c",   "lj_lib.c",       "lj_alloc.c",
    "lib_aux.c",      "lib_init.c",
};

const exe_sources: []const []const u8 = &.{"luajit.c"};

const std = @import("std");
