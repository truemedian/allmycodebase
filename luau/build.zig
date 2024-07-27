pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("luau", .{});

    const luau_cli_lib = b.addStaticLibrary(.{ .name = "Luau.CLI.lib", .target = target, .optimize = optimize });
    const luau_ast = b.addStaticLibrary(.{ .name = "Luau.Ast", .target = target, .optimize = optimize });
    const luau_compiler = b.addStaticLibrary(.{ .name = "Luau.Compiler", .target = target, .optimize = optimize });
    const luau_config = b.addStaticLibrary(.{ .name = "Luau.Config", .target = target, .optimize = optimize });
    const luau_analysis = b.addStaticLibrary(.{ .name = "Luau.Analysis", .target = target, .optimize = optimize });
    const luau_eqsat = b.addStaticLibrary(.{ .name = "Luau.EqSat", .target = target, .optimize = optimize });
    const luau_codegen = b.addStaticLibrary(.{ .name = "Luau.CodeGen", .target = target, .optimize = optimize });
    const luau_vm = b.addStaticLibrary(.{ .name = "Luau.VM", .target = target, .optimize = optimize });

    const luau_repl_cli = b.addExecutable(.{ .name = "luau", .target = target, .optimize = optimize });
    const luau_analyze_cli = b.addExecutable(.{ .name = "luau-analyze", .target = target, .optimize = optimize });
    const luau_ast_cli = b.addExecutable(.{ .name = "luau-ast", .target = target, .optimize = optimize });
    const luau_reduce_cli = b.addExecutable(.{ .name = "luau-reduce", .target = target, .optimize = optimize });
    const luau_compile_cli = b.addExecutable(.{ .name = "luau-compile", .target = target, .optimize = optimize });
    const luau_bytecode_cli = b.addExecutable(.{ .name = "luau-bytecode", .target = target, .optimize = optimize });

    inline for (.{ luau_cli_lib, luau_ast, luau_compiler, luau_config, luau_analysis, luau_eqsat, luau_codegen, luau_vm }) |obj| {
        obj.addIncludePath(upstream.path("Common/include"));

        obj.root_module.addCMacro("LUA_USE_LONGJMP", "1");
        obj.root_module.addCMacro("LUA_API", "extern\"C\"");

        obj.linkLibCpp();
    }

    inline for (.{ luau_repl_cli, luau_analyze_cli, luau_ast_cli, luau_reduce_cli, luau_compile_cli, luau_bytecode_cli }) |obj| {
        obj.addIncludePath(upstream.path("Common/include"));

        obj.root_module.addCMacro("LUA_USE_LONGJMP", "1");
        obj.root_module.addCMacro("LUA_API", "extern\"C\"");

        obj.linkLibCpp();
    }

    luau_compiler.root_module.addCMacro("LUACODE_API", "extern\"C\"");
    luau_codegen.root_module.addCMacro("LUACODEGEN_API", "extern\"C\"");

    luau_cli_lib.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "CLI/FileUtils.cpp",
            "CLI/Flags.cpp",
        },
    });

    luau_ast.linkLibrary(luau_cli_lib);
    luau_ast.addIncludePath(upstream.path("Ast/include"));
    luau_ast.installHeadersDirectory(upstream.path("Ast/Include"), "", .{});
    luau_ast.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "Ast/src/Ast.cpp",
            "Ast/src/Confusables.cpp",
            "Ast/src/Lexer.cpp",
            "Ast/src/Location.cpp",
            "Ast/src/Parser.cpp",
            "Ast/src/StringUtils.cpp",
            "Ast/src/TimeTrace.cpp",
        },
    });

    luau_compiler.linkLibrary(luau_ast);
    luau_compiler.addIncludePath(upstream.path("Compiler/include"));
    luau_compiler.installHeadersDirectory(upstream.path("Compiler/Include"), "", .{});
    luau_compiler.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "Compiler/src/BytecodeBuilder.cpp",
            "Compiler/src/Compiler.cpp",
            "Compiler/src/Builtins.cpp",
            "Compiler/src/BuiltinFolding.cpp",
            "Compiler/src/ConstantFolding.cpp",
            "Compiler/src/CostModel.cpp",
            "Compiler/src/TableShape.cpp",
            "Compiler/src/Types.cpp",
            "Compiler/src/ValueTracking.cpp",
            "Compiler/src/lcode.cpp",
        },
    });

    luau_config.linkLibrary(luau_ast);
    luau_config.addIncludePath(upstream.path("Config/include"));
    luau_config.installHeadersDirectory(upstream.path("Config/Include"), "", .{});
    luau_config.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "Config/src/Config.cpp",
            "Config/src/LinterConfig.cpp",
        },
    });

    luau_analysis.linkLibrary(luau_ast);
    luau_analysis.linkLibrary(luau_eqsat);
    luau_analysis.linkLibrary(luau_config);
    luau_analysis.addIncludePath(upstream.path("Analysis/include"));
    luau_analysis.installHeadersDirectory(upstream.path("Analysis/Include"), "", .{});
    luau_analysis.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "Analysis/src/Anyification.cpp",
            "Analysis/src/AnyTypeSummary.cpp",
            "Analysis/src/ApplyTypeFunction.cpp",
            "Analysis/src/AstJsonEncoder.cpp",
            "Analysis/src/AstQuery.cpp",
            "Analysis/src/Autocomplete.cpp",
            "Analysis/src/BuiltinDefinitions.cpp",
            "Analysis/src/Clone.cpp",
            "Analysis/src/Constraint.cpp",
            "Analysis/src/ConstraintGenerator.cpp",
            "Analysis/src/ConstraintSolver.cpp",
            "Analysis/src/DataFlowGraph.cpp",
            "Analysis/src/DcrLogger.cpp",
            "Analysis/src/Def.cpp",
            "Analysis/src/Differ.cpp",
            "Analysis/src/EmbeddedBuiltinDefinitions.cpp",
            "Analysis/src/Error.cpp",
            "Analysis/src/Frontend.cpp",
            "Analysis/src/Generalization.cpp",
            "Analysis/src/GlobalTypes.cpp",
            "Analysis/src/Instantiation.cpp",
            "Analysis/src/Instantiation2.cpp",
            "Analysis/src/IostreamHelpers.cpp",
            "Analysis/src/JsonEmitter.cpp",
            "Analysis/src/Linter.cpp",
            "Analysis/src/LValue.cpp",
            "Analysis/src/Module.cpp",
            "Analysis/src/NonStrictTypeChecker.cpp",
            "Analysis/src/Normalize.cpp",
            "Analysis/src/OverloadResolution.cpp",
            "Analysis/src/Quantify.cpp",
            "Analysis/src/Refinement.cpp",
            "Analysis/src/RequireTracer.cpp",
            "Analysis/src/Scope.cpp",
            "Analysis/src/Simplify.cpp",
            "Analysis/src/Substitution.cpp",
            "Analysis/src/Subtyping.cpp",
            "Analysis/src/Symbol.cpp",
            "Analysis/src/TableLiteralInference.cpp",
            "Analysis/src/ToDot.cpp",
            "Analysis/src/TopoSortStatements.cpp",
            "Analysis/src/ToString.cpp",
            "Analysis/src/Transpiler.cpp",
            "Analysis/src/TxnLog.cpp",
            "Analysis/src/Type.cpp",
            "Analysis/src/TypeArena.cpp",
            "Analysis/src/TypeAttach.cpp",
            "Analysis/src/TypeChecker2.cpp",
            "Analysis/src/TypedAllocator.cpp",
            "Analysis/src/TypeFunction.cpp",
            "Analysis/src/TypeFunctionReductionGuesser.cpp",
            "Analysis/src/TypeInfer.cpp",
            "Analysis/src/TypeOrPack.cpp",
            "Analysis/src/TypePack.cpp",
            "Analysis/src/TypePath.cpp",
            "Analysis/src/TypeUtils.cpp",
            "Analysis/src/Unifiable.cpp",
            "Analysis/src/Unifier.cpp",
            "Analysis/src/Unifier2.cpp",
        },
    });

    luau_eqsat.addIncludePath(upstream.path("EqSat/include"));
    luau_eqsat.installHeadersDirectory(upstream.path("EqSat/Include"), "", .{});
    luau_eqsat.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "EqSat/src/Id.cpp",
            "EqSat/src/UnionFind.cpp",
        },
    });

    luau_codegen.linkLibrary(luau_vm);
    luau_codegen.addIncludePath(upstream.path("VM/src"));
    luau_codegen.addIncludePath(upstream.path("CodeGen/include"));
    luau_codegen.installHeadersDirectory(upstream.path("CodeGen/Include"), "", .{});
    luau_codegen.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "CodeGen/src/AssemblyBuilderA64.cpp",
            "CodeGen/src/AssemblyBuilderX64.cpp",
            "CodeGen/src/CodeAllocator.cpp",
            "CodeGen/src/CodeBlockUnwind.cpp",
            "CodeGen/src/CodeGen.cpp",
            "CodeGen/src/CodeGenAssembly.cpp",
            "CodeGen/src/CodeGenContext.cpp",
            "CodeGen/src/CodeGenUtils.cpp",
            "CodeGen/src/CodeGenA64.cpp",
            "CodeGen/src/CodeGenX64.cpp",
            "CodeGen/src/EmitBuiltinsX64.cpp",
            "CodeGen/src/EmitCommonX64.cpp",
            "CodeGen/src/EmitInstructionX64.cpp",
            "CodeGen/src/IrAnalysis.cpp",
            "CodeGen/src/IrBuilder.cpp",
            "CodeGen/src/IrCallWrapperX64.cpp",
            "CodeGen/src/IrDump.cpp",
            "CodeGen/src/IrLoweringA64.cpp",
            "CodeGen/src/IrLoweringX64.cpp",
            "CodeGen/src/IrRegAllocA64.cpp",
            "CodeGen/src/IrRegAllocX64.cpp",
            "CodeGen/src/IrTranslateBuiltins.cpp",
            "CodeGen/src/IrTranslation.cpp",
            "CodeGen/src/IrUtils.cpp",
            "CodeGen/src/IrValueLocationTracking.cpp",
            "CodeGen/src/lcodegen.cpp",
            "CodeGen/src/NativeProtoExecData.cpp",
            "CodeGen/src/NativeState.cpp",
            "CodeGen/src/OptimizeConstProp.cpp",
            "CodeGen/src/OptimizeDeadStore.cpp",
            "CodeGen/src/OptimizeFinalX64.cpp",
            "CodeGen/src/UnwindBuilderDwarf2.cpp",
            "CodeGen/src/UnwindBuilderWin.cpp",
            "CodeGen/src/BytecodeAnalysis.cpp",
            "CodeGen/src/BytecodeSummary.cpp",
            "CodeGen/src/SharedCodeAllocator.cpp",
        },
    });

    luau_vm.addIncludePath(upstream.path("VM/include"));
    luau_vm.installHeadersDirectory(upstream.path("VM/Include"), "", .{});
    luau_vm.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "VM/src/lapi.cpp",
            "VM/src/laux.cpp",
            "VM/src/lbaselib.cpp",
            "VM/src/lbitlib.cpp",
            "VM/src/lbuffer.cpp",
            "VM/src/lbuflib.cpp",
            "VM/src/lbuiltins.cpp",
            "VM/src/lcorolib.cpp",
            "VM/src/ldblib.cpp",
            "VM/src/ldebug.cpp",
            "VM/src/ldo.cpp",
            "VM/src/lfunc.cpp",
            "VM/src/lgc.cpp",
            "VM/src/lgcdebug.cpp",
            "VM/src/linit.cpp",
            "VM/src/lmathlib.cpp",
            "VM/src/lmem.cpp",
            "VM/src/lnumprint.cpp",
            "VM/src/lobject.cpp",
            "VM/src/loslib.cpp",
            "VM/src/lperf.cpp",
            "VM/src/lstate.cpp",
            "VM/src/lstring.cpp",
            "VM/src/lstrlib.cpp",
            "VM/src/ltable.cpp",
            "VM/src/ltablib.cpp",
            "VM/src/ltm.cpp",
            "VM/src/ludata.cpp",
            "VM/src/lutf8lib.cpp",
            "VM/src/lvmexecute.cpp",
            "VM/src/lvmload.cpp",
            "VM/src/lvmutils.cpp",
        },
    });

    luau_repl_cli.linkLibrary(luau_ast);
    luau_repl_cli.linkLibrary(luau_compiler);
    luau_repl_cli.linkLibrary(luau_config);
    luau_repl_cli.linkLibrary(luau_codegen);
    luau_repl_cli.linkLibrary(luau_vm);
    luau_repl_cli.linkLibrary(luau_cli_lib);
    luau_repl_cli.addIncludePath(upstream.path("extern/isocline/include"));
    luau_repl_cli.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "CLI/Coverage.cpp",
            "CLI/Profiler.cpp",
            "CLI/Repl.cpp",
            "CLI/ReplEntry.cpp",
            "CLI/Require.cpp",
            "extern/isocline/src/isocline.c",
        },
    });

    luau_analyze_cli.linkLibrary(luau_ast);
    luau_analyze_cli.linkLibrary(luau_config);
    luau_analyze_cli.linkLibrary(luau_analysis);
    luau_analyze_cli.linkLibrary(luau_cli_lib);
    luau_analyze_cli.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "CLI/Analyze.cpp",
        },
    });

    luau_ast_cli.linkLibrary(luau_ast);
    luau_ast_cli.linkLibrary(luau_analysis);
    luau_ast_cli.linkLibrary(luau_cli_lib);
    luau_ast_cli.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "CLI/Ast.cpp",
        },
    });

    luau_reduce_cli.linkLibrary(luau_ast);
    luau_reduce_cli.linkLibrary(luau_analysis);
    luau_reduce_cli.linkLibrary(luau_cli_lib);
    luau_reduce_cli.addIncludePath(upstream.path("Reduce/include"));
    luau_reduce_cli.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "CLI/Reduce.cpp",
        },
    });

    luau_compile_cli.linkLibrary(luau_ast);
    luau_compile_cli.linkLibrary(luau_compiler);
    luau_compile_cli.linkLibrary(luau_vm);
    luau_compile_cli.linkLibrary(luau_codegen);
    luau_compile_cli.linkLibrary(luau_cli_lib);
    luau_compile_cli.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "CLI/Compile.cpp",
        },
    });

    luau_bytecode_cli.linkLibrary(luau_ast);
    luau_bytecode_cli.linkLibrary(luau_compiler);
    luau_bytecode_cli.linkLibrary(luau_vm);
    luau_bytecode_cli.linkLibrary(luau_codegen);
    luau_bytecode_cli.linkLibrary(luau_cli_lib);
    luau_bytecode_cli.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "CLI/Bytecode.cpp",
        },
    });

    b.installArtifact(luau_ast);
    b.installArtifact(luau_compiler);
    b.installArtifact(luau_config);
    b.installArtifact(luau_analysis);
    b.installArtifact(luau_eqsat);
    b.installArtifact(luau_codegen);
    b.installArtifact(luau_vm);

    b.installArtifact(luau_repl_cli);
    b.installArtifact(luau_analyze_cli);
    b.installArtifact(luau_ast_cli);
    b.installArtifact(luau_reduce_cli);
    b.installArtifact(luau_compile_cli);
    b.installArtifact(luau_bytecode_cli);
}

const std = @import("std");