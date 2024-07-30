pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.option(bool, "shared", "Build Lua as a shared library.") orelse false;
    const upstream = b.dependency("libuv", .{});

    const libuv = if (shared) b.addSharedLibrary(.{
        .name = "uv",
        .target = target,
        .optimize = optimize,
        .link_libc = true,

        .version = .{ .major = 1, .minor = 48, .patch = 0 },
    }) else b.addStaticLibrary(.{
        .name = "uv",
        .target = target,
        .optimize = optimize,
        .link_libc = true,

        .version = .{ .major = 1, .minor = 48, .patch = 0 },
    });

    libuv.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = base_sources,
    });

    if (shared) {
        libuv.root_module.addCMacro("BUILDING_UV_SHARED", "1");
    }

    if (target.result.os.tag == .windows) {
        libuv.addCSourceFiles(.{
            .root = upstream.path("src"),
            .files = win_sources,
        });

        libuv.root_module.addCMacro("WIN32_LEAN_AND_MEAN", "1");
        libuv.root_module.addCMacro("_WIN32_WINNT", "0x0602");
        libuv.root_module.addCMacro("_CRT_DECLARE_NONSTDC_NAMES", "0");

        libuv.root_module.linkSystemLibrary("psapi", .{});
        libuv.root_module.linkSystemLibrary("user32", .{});
        libuv.root_module.linkSystemLibrary("advapi32", .{});
        libuv.root_module.linkSystemLibrary("iphlpapi", .{});
        libuv.root_module.linkSystemLibrary("userenv", .{});
        libuv.root_module.linkSystemLibrary("ws2_32", .{});
        libuv.root_module.linkSystemLibrary("dbghelp", .{});
        libuv.root_module.linkSystemLibrary("ole32", .{});
        libuv.root_module.linkSystemLibrary("shell32", .{});
    } else {
        libuv.addCSourceFiles(.{
            .root = upstream.path("src"),
            .files = unix_sources,
        });

        libuv.root_module.linkSystemLibrary("pthread", .{});
    }

    switch (target.result.os.tag) {
        .windows => {},
        .aix => {
            libuv.root_module.addCMacro("_ALL_SOURCE", "1");
            libuv.root_module.addCMacro("_LINUX_SOURCE_COMPAT", "1");
            libuv.root_module.addCMacro("_THREAD_SAFE", "1");
            libuv.root_module.addCMacro("_XOPEN_SOURCE", "500");
            libuv.root_module.addCMacro("HAVE_SYS_AHAFS_EVPRODS_H", "1");

            libuv.root_module.linkSystemLibrary("perfstat", .{});

            libuv.root_module.addCSourceFiles(.{
                .root = upstream.path("src"),
                .files = &.{ "unix/aix.c", "unix/aix-common.c" },
            });
        },
        .linux => {
            libuv.root_module.addCSourceFiles(.{
                .root = upstream.path("src"),
                .files = linux_sources,
            });

            libuv.root_module.addCMacro("_GNU_SOURCE", "1");
            libuv.root_module.addCMacro("_POSIX_C_SOURCE", "200112");

            libuv.root_module.linkSystemLibrary("dl", .{});

            if (target.result.abi != .android)
                libuv.root_module.linkSystemLibrary("rt", .{});
        },
        .ios, .macos => {
            libuv.root_module.addCSourceFiles(.{
                .root = upstream.path("src"),
                .files = darwin_sources,
            });

            libuv.root_module.addCMacro("_DARWIN_UNLIMITED_SELECT", "1");
            libuv.root_module.addCMacro("_DARWIN_USE_64_BIT_INODE", "1");
        },
        .dragonfly => {
            libuv.root_module.addCSourceFiles(.{
                .root = upstream.path("src"),
                .files = dragonfly_sources,
            });
        },
        .freebsd, .kfreebsd => {
            libuv.root_module.addCSourceFiles(.{
                .root = upstream.path("src"),
                .files = freebsd_sources,
            });
        },
        .netbsd => {
            libuv.root_module.addCSourceFiles(.{
                .root = upstream.path("src"),
                .files = netbsd_sources,
            });

            libuv.root_module.linkSystemLibrary("kvm", .{});
        },
        .openbsd => {
            libuv.root_module.addCSourceFiles(.{
                .root = upstream.path("src"),
                .files = openbsd_sources,
            });
        },
        .hurd => {
            libuv.root_module.addCSourceFiles(.{
                .root = upstream.path("src"),
                .files = hurd_sources,
            });

            libuv.root_module.linkSystemLibrary("dl", .{});
        },
        .solaris => {
            libuv.root_module.addCSourceFiles(.{
                .root = upstream.path("src"),
                .files = solaris_sources,
            });

            if (target.result.os.getVersionRange().semver.includesVersion(.{ .major = 5, .minor = 10, .patch = 0 })) {
                libuv.root_module.addCMacro("SUNOS_NO_IFADDRS", "1");
                libuv.root_module.linkSystemLibrary("rt", .{});
            }

            libuv.root_module.addCMacro("__EXTENSIONS__", "1");
            libuv.root_module.addCMacro("_XOPEN_SOURCE", "500");
            libuv.root_module.addCMacro("_REENTRANT", "1");

            libuv.root_module.linkSystemLibrary("kstat", .{});
            libuv.root_module.linkSystemLibrary("nsl", .{});
            libuv.root_module.linkSystemLibrary("sendfile", .{});
            libuv.root_module.linkSystemLibrary("socket", .{});
        },
        .haiku => {
            libuv.root_module.addCSourceFiles(.{
                .root = upstream.path("src"),
                .files = haiku_sources,
            });

            libuv.root_module.addCMacro("_BSD_SOURCE", "1");

            libuv.root_module.linkSystemLibrary("bsd", .{});
            libuv.root_module.linkSystemLibrary("network", .{});
        },
        else => std.debug.panic("unsupported target os: {s}", .{@tagName(target.result.os.tag)}),
    }

    libuv.addIncludePath(upstream.path("src"));
    libuv.addIncludePath(upstream.path("include"));
    libuv.installHeadersDirectory(upstream.path("include"), "", .{});

    b.installArtifact(libuv);

    const test_step = b.step("test", "Run libuv tests");

    const test_exe = b.addExecutable(.{
        .name = "uv-test",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    test_exe.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = base_test_sources,
    });

    if (target.result.os.tag == .windows) {
        test_exe.addCSourceFiles(.{
            .root = upstream.path(""),
            .files = win_test_sources,
        });
    } else {
        test_exe.addCSourceFiles(.{
            .root = upstream.path(""),
            .files = unix_test_sources,
        });
    }

    test_exe.addIncludePath(upstream.path("src"));
    test_exe.addIncludePath(upstream.path("include"));

    if (target.result.os.tag == .linux) {
        test_exe.root_module.addCMacro("_GNU_SOURCE", "1");
    }

    if (shared) {
        if (target.result.os.tag == .windows) {
            test_exe.root_module.linkSystemLibrary("ws2_32", .{});
        } else if (target.result.os.tag.isDarwin() or target.result.os.tag.isBSD() or target.result.os.tag == .linux) {
            test_exe.root_module.linkSystemLibrary("util", .{});
        }

        test_exe.root_module.addCMacro("USING_UV_SHARED", "1");

        if (target.result.os.tag != .windows) {
            test_exe.root_module.linkSystemLibrary("pthread", .{});
        }
    }

    test_exe.root_module.linkLibrary(libuv);

    const run_test = b.addRunArtifact(test_exe);

    test_step.dependOn(&b.addInstallArtifact(test_exe, .{}).step);
    test_step.dependOn(&run_test.step);
}

const base_sources: []const []const u8 = &.{
    "fs-poll.c", "idna.c",      "inet.c",                   "random.c",
    "strscpy.c", "strtok.c",    "thread-common.c",          "threadpool.c",
    "timer.c",   "uv-common.c", "uv-data-getter-setters.c", "version.c",
};

const win_sources: []const []const u8 = &.{
    "win/async.c",       "win/core.c",     "win/detect-wakeup.c", "win/dl.c",
    "win/error.c",       "win/fs.c",       "win/fs-event.c",      "win/getaddrinfo.c",
    "win/getnameinfo.c", "win/handle.c",   "win/loop-watcher.c",  "win/pipe.c",
    "win/thread.c",      "win/poll.c",     "win/process.c",       "win/process-stdio.c",
    "win/signal.c",      "win/snprintf.c", "win/stream.c",        "win/tcp.c",
    "win/tty.c",         "win/udp.c",      "win/util.c",          "win/winapi.c",
    "win/winsock.c",
};

const unix_sources: []const []const u8 = &.{
    "unix/async.c",       "unix/core.c",        "unix/dl.c",           "unix/fs.c",
    "unix/getaddrinfo.c", "unix/getnameinfo.c", "unix/loop-watcher.c", "unix/loop.c",
    "unix/pipe.c",        "unix/poll.c",        "unix/process.c",      "unix/random-devurandom.c",
    "unix/signal.c",      "unix/stream.c",      "unix/tcp.c",          "unix/thread.c",
    "unix/tty.c",         "unix/udp.c",
};

const linux_sources: []const []const u8 = &.{
    "unix/proctitle.c",           "unix/linux.c",
    "unix/procfs-exepath.c",      "unix/random-getrandom.c",
    "unix/random-sysctl-linux.c",
};

const darwin_sources: []const []const u8 = &.{
    "unix/proctitle.c",         "unix/bsd-ifaddrs.c", "unix/kqueue.c",
    "unix/random-getentropy.c", "unix/darwin.c",      "unix/darwin-proctitle.c",
    "unix/fsevents.c",
};

const dragonfly_sources: []const []const u8 = &.{
    "unix/freebsd.c",     "unix/posix-hrtime.c", "unix/bsd-proctitle.c",
    "unix/bsd-ifaddrs.c", "unix/kqueue.c",       "unix/random-getrandom.c",
};

const freebsd_sources: []const []const u8 = &.{
    "unix/freebsd.c",     "unix/posix-hrtime.c", "unix/bsd-proctitle.c",
    "unix/bsd-ifaddrs.c", "unix/kqueue.c",
};

const netbsd_sources: []const []const u8 = &.{
    "unix/posix-hrtime.c", "unix/bsd-proctitle.c", "unix/bsd-ifaddrs.c",
    "unix/kqueue.c",       "unix/netbsd.c",
};

const openbsd_sources: []const []const u8 = &.{
    "unix/posix-hrtime.c", "unix/bsd-proctitle.c",     "unix/bsd-ifaddrs.c",
    "unix/kqueue.c",       "unix/random-getentropy.c", "unix/openbsd.c",
};

const hurd_sources: []const []const u8 = &.{
    "unix/bsd-ifaddrs.c",  "unix/no-fsevents.c", "unix/no-proctitle.c",
    "unix/posix-hrtime.c", "unix/posix-poll.c",  "unix/hurd.c",
};

const solaris_sources: []const []const u8 = &.{
    "unix/no-proctitle.c", "unix/sunos.c",
};

const haiku_sources: []const []const u8 = &.{
    "unix/haiku.c",        "unix/bsd-ifaddrs.c",  "unix/no-fsevents.c",
    "unix/no-proctitle.c", "unix/posix-hrtime.c", "unix/posix-poll.c",
};

const base_test_sources: []const []const u8 = &.{
    "test/blackhole-server.c",                     "test/echo-server.c",
    "test/run-tests.c",                            "test/runner.c",
    "test/test-active.c",                          "test/test-async-null-cb.c",
    "test/test-async.c",                           "test/test-barrier.c",
    "test/test-callback-stack.c",                  "test/test-close-fd.c",
    "test/test-close-order.c",                     "test/test-condvar.c",
    "test/test-connect-unspecified.c",             "test/test-connection-fail.c",
    "test/test-cwd-and-chdir.c",                   "test/test-default-loop-close.c",
    "test/test-delayed-accept.c",                  "test/test-dlerror.c",
    "test/test-eintr-handling.c",                  "test/test-embed.c",
    "test/test-emfile.c",                          "test/test-env-vars.c",
    "test/test-error.c",                           "test/test-fail-always.c",
    "test/test-fork.c",                            "test/test-fs-copyfile.c",
    "test/test-fs-event.c",                        "test/test-fs-poll.c",
    "test/test-fs.c",                              "test/test-fs-readdir.c",
    "test/test-fs-fd-hash.c",                      "test/test-fs-open-flags.c",
    "test/test-get-currentexe.c",                  "test/test-get-loadavg.c",
    "test/test-get-memory.c",                      "test/test-get-passwd.c",
    "test/test-getaddrinfo.c",                     "test/test-gethostname.c",
    "test/test-getnameinfo.c",                     "test/test-getsockname.c",
    "test/test-getters-setters.c",                 "test/test-gettimeofday.c",
    "test/test-handle-fileno.c",                   "test/test-homedir.c",
    "test/test-hrtime.c",                          "test/test-idle.c",
    // "test/test-idna.c", forcibly includes idna.c again, forcing duplicate symbols
    "test/test-ip4-addr.c",                        "test/test-ip6-addr.c",
    "test/test-ip-name.c",                         "test/test-ipc-heavy-traffic-deadlock-bug.c",
    "test/test-ipc-send-recv.c",                   "test/test-ipc.c",
    "test/test-loop-alive.c",                      "test/test-loop-close.c",
    "test/test-loop-configure.c",                  "test/test-loop-handles.c",
    "test/test-loop-stop.c",                       "test/test-loop-time.c",
    "test/test-metrics.c",                         "test/test-multiple-listen.c",
    "test/test-mutexes.c",                         "test/test-not-readable-nor-writable-on-read-error.c",
    "test/test-not-writable-after-shutdown.c",     "test/test-osx-select.c",
    "test/test-pass-always.c",                     "test/test-ping-pong.c",
    "test/test-pipe-bind-error.c",                 "test/test-pipe-close-stdout-read-stdin.c",
    "test/test-pipe-connect-error.c",              "test/test-pipe-connect-multiple.c",
    "test/test-pipe-connect-prepare.c",            "test/test-pipe-getsockname.c",
    "test/test-pipe-pending-instances.c",          "test/test-pipe-sendmsg.c",
    "test/test-pipe-server-close.c",               "test/test-pipe-set-fchmod.c",
    "test/test-pipe-set-non-blocking.c",           "test/test-platform-output.c",
    "test/test-poll-close-doesnt-corrupt-stack.c", "test/test-poll-close.c",
    "test/test-poll-closesocket.c",                "test/test-poll-multiple-handles.c",
    "test/test-poll-oob.c",                        "test/test-poll.c",
    "test/test-process-priority.c",                "test/test-process-title-threadsafe.c",
    "test/test-process-title.c",                   "test/test-queue-foreach-delete.c",
    "test/test-random.c",                          "test/test-readable-on-eof.c",
    "test/test-ref.c",                             "test/test-run-nowait.c",
    "test/test-run-once.c",                        "test/test-semaphore.c",
    "test/test-shutdown-close.c",                  "test/test-shutdown-eof.c",
    "test/test-shutdown-simultaneous.c",           "test/test-shutdown-twice.c",
    "test/test-signal-multiple-loops.c",           "test/test-signal-pending-on-close.c",
    "test/test-signal.c",                          "test/test-socket-buffer-size.c",
    "test/test-spawn.c",                           "test/test-stdio-over-pipes.c",
    "test/test-strscpy.c",                         "test/test-strtok.c",
    "test/test-tcp-alloc-cb-fail.c",               "test/test-tcp-bind-error.c",
    "test/test-tcp-bind6-error.c",                 "test/test-tcp-close-accept.c",
    "test/test-tcp-close-after-read-timeout.c",    "test/test-tcp-close-while-connecting.c",
    "test/test-tcp-close.c",                       "test/test-tcp-close-reset.c",
    "test/test-tcp-connect-error-after-write.c",   "test/test-tcp-connect-error.c",
    "test/test-tcp-connect-timeout.c",             "test/test-tcp-connect6-error.c",
    "test/test-tcp-create-socket-early.c",         "test/test-tcp-flags.c",
    "test/test-tcp-oob.c",                         "test/test-tcp-open.c",
    "test/test-tcp-read-stop.c",                   "test/test-tcp-read-stop-start.c",
    "test/test-tcp-rst.c",                         "test/test-tcp-shutdown-after-write.c",
    "test/test-tcp-try-write.c",                   "test/test-tcp-write-in-a-row.c",
    "test/test-tcp-try-write-error.c",             "test/test-tcp-unexpected-read.c",
    "test/test-tcp-write-after-connect.c",         "test/test-tcp-write-fail.c",
    "test/test-tcp-write-queue-order.c",           "test/test-tcp-write-to-half-open-connection.c",
    "test/test-tcp-writealot.c",                   "test/test-test-macros.c",
    "test/test-thread.c",                          "test/test-thread-affinity.c",
    "test/test-thread-equal.c",                    "test/test-thread-priority.c",
    "test/test-threadpool-cancel.c",               "test/test-threadpool.c",
    "test/test-timer-again.c",                     "test/test-timer-from-check.c",
    "test/test-timer.c",                           "test/test-tmpdir.c",
    "test/test-tty-duplicate-key.c",               "test/test-tty-escape-sequence-processing.c",
    "test/test-tty.c",                             "test/test-udp-alloc-cb-fail.c",
    "test/test-udp-bind.c",                        "test/test-udp-connect.c",
    "test/test-udp-connect6.c",                    "test/test-udp-create-socket-early.c",
    "test/test-udp-dgram-too-big.c",               "test/test-udp-ipv6.c",
    "test/test-udp-mmsg.c",                        "test/test-udp-multicast-interface.c",
    "test/test-udp-multicast-interface6.c",        "test/test-udp-multicast-join.c",
    "test/test-udp-multicast-join6.c",             "test/test-udp-multicast-ttl.c",
    "test/test-udp-open.c",                        "test/test-udp-options.c",
    "test/test-udp-send-and-recv.c",               "test/test-udp-send-hang-loop.c",
    "test/test-udp-send-immediate.c",              "test/test-udp-sendmmsg-error.c",
    "test/test-udp-send-unreachable.c",            "test/test-udp-try-send.c",
    "test/test-udp-recv-in-a-row.c",               "test/test-uname.c",
    "test/test-walk-handles.c",                    "test/test-watcher-cross-stop.c",
};

const win_test_sources: []const []const u8 = &.{
    "src/win/snprintf.c", "test/runner-win.c",
};

const unix_test_sources: []const []const u8 = &.{
    "test/runner-unix.c",
};

const std = @import("std");
