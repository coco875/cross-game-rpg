const std = @import("std");
const fs = @import("std").fs;

// =============================================================================================
// This file exposes two public functions:
//  - addSdl2: builds a configured static SDL2 library (bundled C sources)
//  - addSdl2ToExe: directly injects SDL sources into an executable (simplified variant)
//
// Main goals:
//  * Minimal build by default (optionally re‑enable subsystems)
//  * Vulkan support (per-file flags) without broad global defines
//  * Fine grained platform handling (Linux / Windows / macOS + console scaffolding)
//  * Specific stubs (dynapi, macOS cross stub, EGL when OpenGL absent, disabled GLES paths)
//
// This refactor keeps the previous behavior while structuring code into helpers and grouped options.
// =============================================================================================

// Recursively collect all .c files starting at a root directory.
fn recursive_search_c_files_(allocator: std.mem.Allocator, dir: fs.Dir, path_string: []const u8) !std.ArrayList([]const u8) {
    var it = dir.iterate();
    var files = std.ArrayList([]const u8).init(allocator);
    while (try it.next()) |entry| switch (entry.kind) {
        .file => if (std.mem.endsWith(u8, entry.name, ".c")) {
            const full = std.fs.path.join(allocator, &.{ path_string, entry.name }) catch continue;
            try files.append(full);
        },
        .directory => {
            var sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
            defer sub_dir.close();
            const sub_files = try recursive_search_c_files_(allocator, sub_dir, try std.fs.path.join(allocator, &.{ path_string, entry.name }));
            for (sub_files.items) |f| try files.append(f);
            sub_files.deinit();
        },
        else => {},
    };
    return files;
}

pub fn recursive_search_c_files(allocator: std.mem.Allocator, path: std.Build.Cache.Path, path_string: []const u8) !std.ArrayList([]const u8) {
    var dir = try path.openDir(".", .{ .iterate = true });
    defer dir.close();

    return recursive_search_c_files_(allocator, dir, path_string);
}

// =============================================================================================
// Helper Section (options, skip list, flags, configuration)
// =============================================================================================

const BuildOptions = struct {
    // Subsystems
    audio: bool,
    video: bool,
    opengl: bool,
    x11: bool,
    vulkan: bool,
    macos_full: bool,
    joystick: bool,
    haptic: bool,
    sensor: bool,
    hidapi: bool,
    locale: bool,
    misc: bool,
    threads: bool,
    timer: bool,
    loadso: bool,
    filesystem: bool,
    events: bool,
    atomic: bool,
    sdl_assert: bool,
    // Platform scaffolding flags
    support_android: bool,
    support_xbox: bool,
    support_n3ds: bool,
    support_psp: bool,
    support_ps2: bool,
    support_vita: bool,
};

fn gatherBuildOptions(b: *std.Build, target: std.Build.ResolvedTarget) BuildOptions {
    // Defaults keep behavior of original version.
    const opt_enable_audio = b.option(bool, "enable-audio", "Enable audio subsystem") orelse true;
    const opt_enable_video = b.option(bool, "enable-video", "Enable video subsystem") orelse true;
    const opt_enable_opengl = b.option(bool, "enable-opengl", "Enable OpenGL support") orelse true;
    const opt_enable_x11 = b.option(bool, "enable-x11", "Enable X11 (Linux)") orelse true;
    const opt_enable_vulkan = b.option(bool, "enable-vulkan", "Enable Vulkan support") orelse false;
    const opt_macos_full = b.option(bool, "macos-full", "Enable native macOS backends when cross compiling") orelse false;
    const opt_enable_joystick = b.option(bool, "enable-joystick", "Enable joystick subsystem") orelse true;
    const opt_enable_haptic = b.option(bool, "enable-haptic", "Enable haptic subsystem") orelse false;
    const opt_enable_sensor = b.option(bool, "enable-sensor", "Enable sensor subsystem") orelse false;
    const opt_enable_hidapi = b.option(bool, "enable-hidapi", "Enable HIDAPI support") orelse false;
    const opt_enable_locale = b.option(bool, "enable-locale", "Enable locale subsystem") orelse true;
    const opt_enable_misc = b.option(bool, "enable-misc", "Enable misc subsystem") orelse true;
    const opt_enable_threads = b.option(bool, "enable-threads", "Enable threading subsystem") orelse true;
    const opt_enable_timer = b.option(bool, "enable-timer", "Enable timer subsystem") orelse true;
    const opt_enable_loadso = b.option(bool, "enable-loadso", "Enable dynamic loading (loadso)") orelse true;
    const opt_enable_filesystem = b.option(bool, "enable-filesystem", "Enable filesystem subsystem") orelse true;
    const opt_enable_events = b.option(bool, "enable-events", "Enable events subsystem") orelse true;
    const opt_enable_atomic = b.option(bool, "enable-atomic", "Enable atomic subsystem") orelse true;
    const opt_enable_assert = b.option(bool, "enable-assert", "Enable assertions") orelse true;
    const opt_support_android = b.option(bool, "support-android", "Scaffold Android support") orelse false;
    const opt_support_xbox = b.option(bool, "support-xbox", "Scaffold Xbox support") orelse false;
    const opt_support_n3ds = b.option(bool, "support-n3ds", "Scaffold N3DS support") orelse false;
    const opt_support_psp = b.option(bool, "support-psp", "Scaffold PSP support") orelse false;
    const opt_support_ps2 = b.option(bool, "support-ps2", "Scaffold PS2 support") orelse false;
    const opt_support_vita = b.option(bool, "support-vita", "Scaffold Vita support") orelse false;

    const is_android = target.result.os.tag == .linux and target.result.abi == .android;

    return .{
        .audio = opt_enable_audio,
        .video = opt_enable_video,
        .opengl = opt_enable_opengl,
        .x11 = opt_enable_x11,
        .vulkan = opt_enable_vulkan,
        .macos_full = opt_macos_full,
        .joystick = opt_enable_joystick,
        .haptic = opt_enable_haptic,
        .sensor = opt_enable_sensor,
        .hidapi = opt_enable_hidapi,
        .locale = opt_enable_locale,
        .misc = opt_enable_misc,
        .threads = opt_enable_threads,
        .timer = opt_enable_timer,
        .loadso = opt_enable_loadso,
        .filesystem = opt_enable_filesystem,
        .events = opt_enable_events,
        .atomic = opt_enable_atomic,
        .sdl_assert = opt_enable_assert,
        .support_android = opt_support_android or is_android,
        .support_xbox = opt_support_xbox,
        .support_n3ds = opt_support_n3ds,
        .support_psp = opt_support_psp,
        .support_ps2 = opt_support_ps2,
        .support_vita = opt_support_vita,
    };
}

fn osTraits(target: std.Build.ResolvedTarget) struct {
    is_windows: bool,
    is_linux: bool,
    is_macos: bool,
    host_is_macos: bool,
} {
    const is_windows = target.result.os.tag == .windows;
    const is_linux = target.result.os.tag == .linux;
    const is_macos = target.result.os.tag == .macos;
    const host_is_macos = @import("builtin").os.tag == .macos;
    return .{
        .is_windows = is_windows,
        .is_linux = is_linux,
        .is_macos = is_macos,
        .host_is_macos = host_is_macos,
    };
}

fn buildSkipList(allocator: std.mem.Allocator, opts: BuildOptions, traits: anytype) std.ArrayList([]const u8) {
    var skip = std.ArrayList([]const u8).init(allocator);
    const base_excludes = [_][]const u8{
        "/winrt/",           "/gdk/",               "/wingdk/",            "/emscripten/",     "/riscos/", "/pandora/",         "/raspberry/",        "/haiku/", "/qnx/", "/os2/", "/directfb/", "/vivante/", "/wayland/", "/kmdir/", "/kmsdrm/", "/uikit/", "/iphone/", "/ios/", "/tvos/", "/visionos/", "/watchos/", "/steam/", "/loongarch/", "/bsd/", "/openbsd/", "/netbsd/", "/freebsd/", "/nacl/", "/libusb/", "/test/",
        "/render/direct3d/", "/render/direct3d11/", "/render/direct3d12/", "/render/vitagxm/", "/dynapi/", "/render/opengles/", "/render/opengles2/",
    };
    for (base_excludes) |p| skip.append(p) catch {};

    // Console / alt platform scaffolding
    if (!opts.support_android) skip.append("/android/") catch {};
    if (!opts.support_xbox) skip.append("/xbox/") catch {};
    if (!opts.support_n3ds) skip.append("/n3ds/") catch {};
    if (!opts.support_psp) skip.append("/psp/") catch {};
    if (!opts.support_ps2) skip.append("/ps2/") catch {};
    if (!opts.support_vita) skip.append("/vita/") catch {};

    if (!traits.is_macos) {
        skip.append("/darwin/") catch {};
        skip.append("/macosx/") catch {};
        skip.append("/metal/") catch {};
    }

    // Subsystems skip rules
    if (!opts.joystick) skip.append("/joystick/") catch {};
    if (!opts.haptic) skip.append("/haptic/") catch {};
    if (!opts.sensor) skip.append("/sensor/") catch {};
    if (!opts.hidapi) skip.append("/hidapi/") catch {};
    if (!opts.audio) skip.append("/audio/") catch {};
    if (!opts.video) skip.append("/video/") catch {};
    if (!opts.filesystem) skip.append("/filesystem/") catch {};
    if (!opts.locale) skip.append("/locale/") catch {};
    if (!opts.misc) skip.append("/misc/") catch {};
    if (!opts.threads) skip.append("/thread/") catch {};
    if (!opts.timer) skip.append("/timer/") catch {};
    if (!opts.loadso) skip.append("/loadso/") catch {};
    if (opts.loadso) skip.append("/loadso/dummy/") catch {}; // éviter dummy
    if (!opts.atomic) skip.append("/atomic/") catch {};
    if (!opts.events) skip.append("/events/") catch {};
    skip.append("/video/SDL_egl.c") catch {};

    if (traits.is_linux) {
        const linux_ex = [_][]const u8{
            "/windows/",                    "/xinput",                "/video/windows/",
            "/audio/directsound/",          "/audio/wasapi/",         "/audio/winmm/",
            "/video/x11/SDL_x11opengles.c", "/core/linux/SDL_dbus.c", "/core/linux/SDL_fcitx.c",
            "/core/linux/SDL_ibus.c",       "/core/linux/SDL_ime.c",  "/thread/generic/",
        };
        for (linux_ex) |p| skip.append(p) catch {};
        if (!opts.opengl) {
            skip.append("/render/opengl/") catch {};
            skip.append("/video/x11/SDL_x11opengl.c") catch {};
        }
        if (!opts.vulkan) {
            skip.append("/video/x11/SDL_x11vulkan.c") catch {};
            skip.append("/video/SDL_vulkan_utils.c") catch {};
        }
        if (!opts.x11) {
            skip.append("/video/x11/") catch {};
        }
    } else if (traits.is_windows) {
        const win_ex = [_][]const u8{
            "/core/linux/",      "/core/unix/",      "/video/x11/",                          "/locale/unix/",    "/filesystem/unix/", "/timer/unix/",       "/thread/pthread/", "/loadso/dlopen/",
            "/video/offscreen/", "/video/dummy/",    "/power/linux/",                        "/misc/unix/",      "/misc/dummy/",      "/filesystem/dummy/", "/locale/dummy/",   "/timer/dummy/",
            "/loadso/dummy/",    "/thread/generic/", "/video/windows/SDL_windowsopengles.c", "/video/SDL_egl.c",
        };
        for (win_ex) |p| skip.append(p) catch {};
        if (!opts.opengl) skip.append("/video/windows/SDL_windowsopengl.c") catch {};
        if (!opts.vulkan) skip.append("/video/windows/SDL_windowsvulkan.c") catch {};
        if (!opts.audio) skip.append("/audio/") catch {};
    } else if (traits.is_macos) {
        const mac_ex = [_][]const u8{
            "/windows/", "/winrt/", "/wingdk/", "/xbox/", "/video/windows/", "/video/x11/",
            "/power/macosx/", // retiré si cross stub plus tard
            "/power/windows/",
            "/locale/windows/",
            "/filesystem/windows/",
            "/misc/windows/",
            "/timer/windows/",
            "/thread/windows/",
        };
        for (mac_ex) |p| skip.append(p) catch {};
        if (!traits.host_is_macos) {
            skip.append("/video/cocoa/") catch {};
            skip.append("/power/macosx/") catch {};
            skip.append("/render/opengl/") catch {};
        }
        if (!opts.audio) skip.append("/audio/") catch {};
    }

    if (opts.audio and traits.is_linux) {
        const linux_audio_trim = [_][]const u8{
            "/audio/aaudio/", "/audio/alsa/", "/audio/arts/", "/audio/disk/", "/audio/dsp/", "/audio/esd/", "/audio/fusionsound/", "/audio/jack/", "/audio/nas/", "/audio/openslES/", "/audio/paudio/", "/audio/pipewire/", "/audio/pulseaudio/", "/audio/qsa/", "/audio/sndio/", "/audio/sun/",
        };
        for (linux_audio_trim) |p| skip.append(p) catch {};
    }

    if (!traits.is_linux) {
        const not_linux = [_][]const u8{ "/core/linux/SDL_fcitx", "/core/linux/SDL_ibus", "/core/linux/SDL_dbus.c", "/core/linux/SDL_udev.c" };
        for (not_linux) |p| skip.append(p) catch {};
    }
    return skip;
}

fn filterSources(allocator: std.mem.Allocator, files: *std.ArrayList([]const u8), skip: std.ArrayList([]const u8), cross_macos_stub: bool) void {
    var filtered = std.ArrayList([]const u8).init(allocator);
    file_loop: for (files.items) |f| {
        if (cross_macos_stub) {
            if (std.mem.indexOf(u8, f, "/video/") != null or
                std.mem.indexOf(u8, f, "/events/") != null or
                std.mem.indexOf(u8, f, "/render/") != null or
                std.mem.indexOf(u8, f, "/thread/") != null or
                std.mem.indexOf(u8, f, "/timer/") != null or
                std.mem.indexOf(u8, f, "/loadso/") != null or
                std.mem.indexOf(u8, f, "/filesystem/") != null or
                std.mem.indexOf(u8, f, "/locale/") != null or
                std.mem.endsWith(u8, f, "/SDL.c") or
                std.mem.endsWith(u8, f, "/SDL_assert.c")) continue;
        }
        for (skip.items) |pat| if (std.mem.indexOf(u8, f, pat) != null) continue :file_loop;
        filtered.append(f) catch {};
    }
    files.deinit();
    files.* = filtered;
}

fn appendSubsystemFlags(list: *std.ArrayList([]const u8), enabled: bool, on: []const u8, off: []const u8) void {
    list.append(if (enabled) on else off) catch {};
}

fn buildCommonFlags(allocator: std.mem.Allocator, opts: BuildOptions, traits: anytype, cross_macos_stub: bool) []const []const u8 {
    var flags = std.ArrayList([]const u8).init(allocator);
    if (!cross_macos_stub) {
        const base = [_][]const u8{ "-DSDL_BUILDING_LIBRARY", "-DSDL_DYNAMIC_API=0", "-DSDL_dynapi_h_" };
        for (base) |f| flags.append(f) catch {};
    } else {
        const stub = [_][]const u8{ "-DSDL_BUILDING_LIBRARY", "-DSDL_VIDEO=0", "-DSDL_THREADS=0", "-DSDL_TIMER=0", "-DSDL_LOADSO=0", "-DSDL_ATOMIC=0", "-DSDL_EVENTS=0", "-DSDL_LOCALE=0", "-DSDL_MISC=0", "-DSDL_DYNAMIC_API=0", "-DSDL_dynapi_h_", "-DSDL_VIDEO_OPENGL=0" };
        for (stub) |f| flags.append(f) catch {};
    }
    // Subsystem macro flags
    const subs = [_]struct { e: bool, on: []const u8, off: []const u8 }{
        .{ .e = opts.video, .on = "-DSDL_VIDEO=1", .off = "-DSDL_VIDEO=0" },
        .{ .e = opts.threads, .on = "-DSDL_THREADS=1", .off = "-DSDL_THREADS=0" },
        .{ .e = opts.timer, .on = "-DSDL_TIMER=1", .off = "-DSDL_TIMER=0" },
        .{ .e = opts.loadso, .on = "-DSDL_LOADSO=1", .off = "-DSDL_LOADSO=0" },
        .{ .e = opts.atomic, .on = "-DSDL_ATOMIC=1", .off = "-DSDL_ATOMIC=0" },
        .{ .e = opts.events, .on = "-DSDL_EVENTS=1", .off = "-DSDL_EVENTS=0" },
        .{ .e = opts.locale, .on = "-DSDL_LOCALE=1", .off = "-DSDL_LOCALE=0" },
        .{ .e = opts.misc, .on = "-DSDL_MISC=1", .off = "-DSDL_MISC=0" },
        .{ .e = opts.filesystem, .on = "-DSDL_FILESYSTEM=1", .off = "-DSDL_FILESYSTEM=0" },
        .{ .e = opts.audio, .on = "-DSDL_AUDIO=1", .off = "-DSDL_AUDIO=0" },
        .{ .e = opts.joystick, .on = "-DSDL_JOYSTICK=1", .off = "-DSDL_JOYSTICK=0" },
        .{ .e = opts.haptic, .on = "-DSDL_HAPTIC=1", .off = "-DSDL_HAPTIC=0" },
        .{ .e = opts.sensor, .on = "-DSDL_SENSOR=1", .off = "-DSDL_SENSOR=0" },
        .{ .e = opts.hidapi, .on = "-DSDL_HIDAPI=1", .off = "-DSDL_HIDAPI=0" },
    };
    for (subs) |s| flags.append(if (s.e) s.on else s.off) catch {};
    if (!opts.joystick) flags.append("-DSDL_JOYSTICK_DISABLED=1") catch {};
    if (!opts.haptic) flags.append("-DSDL_HAPTIC_DISABLED=1") catch {};
    if (!opts.sensor) flags.append("-DSDL_SENSOR_DISABLED=1") catch {};
    if (!opts.audio) flags.append("-DSDL_AUDIO_DISABLED=1") catch {};
    flags.append("-USDL_VIDEO_OPENGL_ES2") catch {};
    flags.append("-USDL_VIDEO_OPENGL_EGL") catch {};

    if (traits.is_linux) {
        const linux_base = [_][]const u8{
            "-DHAVE_STDIO_H",        "-DHAVE_STDLIB_H", "-DHAVE_STRING_H",    "-DHAVE_CTYPE_H",         "-DHAVE_MATH_H",      "-DHAVE_SIGNAL_H",
            "-DHAVE_INTTYPES_H",     "-DHAVE_STDINT_H", "-DHAVE_SYS_TYPES_H", "-DHAVE_SYS_STAT_H",      "-DHAVE_UNISTD_H",    "-D_REENTRANT",
            "-USDL_USE_IME",         "-DHAVE_DBUS=0",   "-DHAVE_PTHREAD=1",   "-DSDL_THREAD_PTHREAD=1", "-DSDL_TIMER_UNIX=1", "-DSDL_FILESYSTEM_UNIX=1",
            "-DSDL_LOADSO_DLOPEN=1",
        };
        for (linux_base) |f| flags.append(f) catch {};
        if (opts.x11) {
            flags.append("-DSDL_VIDEO_DRIVER_X11=1") catch {};
            flags.append("-DSDL_VIDEO_DRIVER_X11_SUPPORTS_GENERIC_EVENTS=1") catch {};
        } else {
            flags.append("-DSDL_VIDEO_DRIVER_DUMMY=1") catch {};
            flags.append("-DSDL_VIDEO_RENDER_SW=1") catch {};
        }
        if (opts.opengl) {
            flags.append("-DSDL_VIDEO_OPENGL=1") catch {};
            flags.append("-DSDL_VIDEO_RENDER_OGL=1") catch {};
        } else {
            flags.append("-USDL_VIDEO_OPENGL") catch {};
            flags.append("-DSDL_VIDEO_RENDER_SW=1") catch {};
        }
    } else if (traits.is_windows) {
        const windows_flags = [_][]const u8{
            "-DSDL_USE_IME=0", "-DSDL_VIDEO_OPENGL=1", "-DSDL_VIDEO_OPENGL_WGL=1", "-USDL_VIDEO_DRIVER_DUMMY", "-DSDL_windowsopengles_h_",
        };
        for (windows_flags) |f| flags.append(f) catch {};
        if (!opts.opengl) {
            flags.append("-USDL_VIDEO_OPENGL") catch {};
            flags.append("-DSDL_VIDEO_RENDER_SW=1") catch {};
        } else flags.append("-DSDL_VIDEO_RENDER_OGL=1") catch {};
        if (!opts.audio) {
            flags.append("-DSDL_AUDIO=0") catch {};
            flags.append("-DSDL_AUDIO_DISABLED=1") catch {};
        } else flags.append("-DSDL_AUDIO=1") catch {};
    } else if (traits.is_macos and !cross_macos_stub) {
        const mac_flags = [_][]const u8{
            "-DHAVE_STDIO_H",        "-DHAVE_STDLIB_H",            "-DHAVE_STRING_H",    "-DHAVE_CTYPE_H",         "-DHAVE_MATH_H",      "-DHAVE_SIGNAL_H",
            "-DHAVE_INTTYPES_H",     "-DHAVE_STDINT_H",            "-DHAVE_SYS_TYPES_H", "-DHAVE_SYS_STAT_H",      "-DHAVE_UNISTD_H",    "-D_REENTRANT",
            "-DSDL_USE_IME=0",       "-DSDL_VIDEO_DRIVER_COCOA=1", "-DHAVE_PTHREAD=1",   "-DSDL_THREAD_PTHREAD=1", "-DSDL_TIMER_UNIX=1", "-DSDL_FILESYSTEM_UNIX=1",
            "-DSDL_LOADSO_DLOPEN=1",
        };
        for (mac_flags) |f| flags.append(f) catch {};
        if (@import("builtin").os.tag != .macos) { // cross
            flags.append("-USDL_VIDEO_DRIVER_COCOA") catch {};
            flags.append("-DSDL_VIDEO_OPENGL=0") catch {};
            flags.append("-DSDL_POWER=0") catch {};
        }
        if (opts.opengl) {
            flags.append("-DSDL_VIDEO_OPENGL=1") catch {};
            flags.append("-DSDL_VIDEO_RENDER_OGL=1") catch {};
        } else {
            flags.append("-USDL_VIDEO_OPENGL") catch {};
            flags.append("-DSDL_VIDEO_RENDER_SW=1") catch {};
        }
        if (!opts.audio) {
            flags.append("-DSDL_AUDIO=0") catch {};
            flags.append("-DSDL_AUDIO_DISABLED=1") catch {};
        } else flags.append("-DSDL_AUDIO=1") catch {};
    }
    if (opts.sdl_assert) {
        flags.append("-DSDL_ASSERT_LEVEL=1") catch {};
        flags.append("-DSDL_ENABLE_ASSERTIONS=1") catch {};
    }
    return flags.toOwnedSlice() catch &[_][]const u8{};
}

fn genSDLConfigNonWindows(allocator: std.mem.Allocator, opts: BuildOptions) []const u8 {
    var cfg = std.ArrayList(u8).init(allocator);
    cfg.appendSlice("#pragma once\n#include <SDL_config_minimal.h>\n") catch {};
    cfg.appendSlice("#undef SDL_LOADSO_DISABLED\n") catch {};
    inline for (.{ .{ opts.audio, "SDL_AUDIO" }, .{ opts.video, "SDL_VIDEO" }, .{ opts.opengl, "SDL_VIDEO_OPENGL" }, .{ opts.threads, "SDL_THREADS" }, .{ opts.timer, "SDL_TIMER" }, .{ opts.loadso, "SDL_LOADSO" }, .{ opts.filesystem, "SDL_FILESYSTEM" }, .{ opts.locale, "SDL_LOCALE" }, .{ opts.misc, "SDL_MISC" }, .{ opts.atomic, "SDL_ATOMIC" }, .{ opts.events, "SDL_EVENTS" } }) |entry| {
        const enabled: bool = @field(entry, "0");
        const name: []const u8 = @field(entry, "1");
        cfg.appendSlice("#undef ") catch {};
        cfg.appendSlice(name) catch {};
        if (enabled) {
            cfg.appendSlice("\n#define ") catch {};
            cfg.appendSlice(name) catch {};
            cfg.appendSlice(" 1\n") catch {};
        } else {
            cfg.appendSlice("\n#define ") catch {};
            cfg.appendSlice(name) catch {};
            cfg.appendSlice(" 0\n") catch {};
            if (std.mem.eql(u8, name, "SDL_LOADSO")) cfg.appendSlice("#define SDL_LOADSO_DISABLED 1\n") catch {};
            if (std.mem.eql(u8, name, "SDL_AUDIO")) cfg.appendSlice("#define SDL_AUDIO_DISABLED 1\n") catch {};
            if (std.mem.eql(u8, name, "SDL_VIDEO")) cfg.appendSlice("#define SDL_VIDEO_DISABLED 1\n") catch {};
        }
    }
    cfg.appendSlice("#define SDL_HAVE_LIBC 1\n") catch {};
    if (opts.sdl_assert) cfg.appendSlice("#define SDL_ASSERT_LEVEL 1\n#define SDL_ENABLE_ASSERTIONS 1\n") catch {};
    return cfg.toOwnedSlice() catch "#pragma once\n";
}

// =============================================================================================
// addSdl2 main implementation
// =============================================================================================

pub fn addSdl2(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) struct {
    compile: *std.Build.Step.Compile,
    module: *std.Build.Module,
    local_include: std.Build.LazyPath,
    sdl_include: std.Build.LazyPath,
} {
    const dep_sdl2_c = b.dependency("sdl2_c", .{
        .target = target,
        .optimize = optimize,
    });

    const sdl2_zig = b.addLibrary(.{
        .name = "sdl2_zig",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    const allocator = std.heap.page_allocator;

    std.debug.print("SDL2 C dependency located at: {}\n", .{dep_sdl2_c.path(".").getPath3(b, null)});
    std.debug.print("SDL2 C dependency src located at: {}\n", .{dep_sdl2_c.path("src").getPath3(b, null)});
    std.debug.print("SDL2 C dependency include located at: {}\n", .{dep_sdl2_c.path("include").getPath3(b, null)});

    var files = recursive_search_c_files(allocator, dep_sdl2_c.path("src").getPath3(b, null), "src") catch std.debug.panic("Failed to search for SDL2 C source files.\n", .{});
    var opts = gatherBuildOptions(b, target);
    const traits_full = osTraits(target);
    const cross_macos_stub = target.result.os.tag == .macos and @import("builtin").os.tag != .macos and !opts.macos_full;

    // =============================================================================================
    // SOURCE FILTER SECTION ("skip list" approach mirroring CMake logic)
    // =============================================================================================
    // Build list of exclusion patterns based on disabled subsystems and platform.
    // CMake conditionally adds directories; here we start with everything then subtract.

    // windows-gnu specific adjustment: disable joystick (incomplete drivers / missing WinRT headers)
    if (target.result.os.tag == .windows and target.result.abi == .gnu and opts.joystick) {
        opts.joystick = false; // évite dépendances WGI / RawInput partielles
    }

    // Linux constraints: OpenGL or Vulkan require X11 in this minimal configuration (Wayland/KMS excluded).
    if (traits_full.is_linux and !opts.x11) {
        if (opts.opengl) {
            std.debug.print("[SDL2 build] Conflit: enable-opengl nécessite enable-x11 sur Linux.\n", .{});
            @panic("enable-opengl sans enable-x11 n'est pas supporté");
        }
        if (opts.vulkan) {
            std.debug.print("[SDL2 build] Conflit: enable-vulkan nécessite enable-x11 sur Linux.\n", .{});
            @panic("enable-vulkan sans enable-x11 n'est pas supporté");
        }
    }

    var skip_list = buildSkipList(allocator, opts, .{ .is_windows = traits_full.is_windows, .is_linux = traits_full.is_linux, .is_macos = traits_full.is_macos, .host_is_macos = traits_full.host_is_macos });
    // On MinGW (windows-gnu) toolchains WinRT headers (windows.gaming.input.h) are unavailable.
    // Exclude implementations that depend on them.
    if (traits_full.is_windows and target.result.abi == .gnu) {
        skip_list.append("/joystick/") catch {};
    }
    filterSources(allocator, &files, skip_list, cross_macos_stub);
    std.debug.print("SDL2: using {d} filtered source files\n", .{files.items.len});

    // =============================================================================================
    // MACRO / FLAGS SECTION (mirrors CMake option blocks conceptually)
    // =============================================================================================
    const common_flags = buildCommonFlags(allocator, opts, .{ .is_windows = traits_full.is_windows, .is_linux = traits_full.is_linux, .is_macos = traits_full.is_macos }, cross_macos_stub);

    sdl2_zig.linkLibC();
    sdl2_zig.addCSourceFiles(.{
        .root = dep_sdl2_c.path(""),
        .files = files.items,
        .flags = common_flags,
    });
    if (opts.vulkan and !cross_macos_stub and opts.video) {
        var vulkan_files = std.ArrayList([]const u8).init(allocator);
        if (traits_full.is_linux and opts.x11) {
            // X11 Vulkan shim
            vulkan_files.append("src/video/x11/SDL_x11vulkan.c") catch {};
        } else if (traits_full.is_windows) {
            vulkan_files.append("src/video/windows/SDL_windowsvulkan.c") catch {};
        } else if (traits_full.is_macos) {
            // macOS: SDL 2.0.x has no official native Vulkan backend (MoltenVK via Cocoa) — leave empty.
        }
        // Utils communs
        vulkan_files.append("src/video/SDL_vulkan_utils.c") catch {};
        if (vulkan_files.items.len > 0) {
            const vulkan_flags = [_][]const u8{ "-DSDL_VIDEO_VULKAN=1", "-USDL_LOADSO_DISABLED", "-USDL_LOADSO_DUMMY" };
            sdl2_zig.addCSourceFiles(.{ .root = dep_sdl2_c.path(""), .files = vulkan_files.items, .flags = &vulkan_flags });
        }
    }
    if (traits_full.is_linux and !opts.opengl) {
        const egl_stub_code =
            "#include <stdint.h>\n" ++
            "int SDL_EGL_SetSwapInterval(int i){(void)i;return -1;}\n" ++
            "int SDL_EGL_GetSwapInterval(void){return 0;}\n" ++
            "void SDL_EGL_UnloadLibrary(void){}\n" ++
            "void* SDL_EGL_GetProcAddress(const char* n){(void)n;return 0;}\n" ++
            "int SDL_EGL_DeleteContext(void* c){(void)c;return 0;}\n" ++
            "int X11_GLES_LoadLibrary(void* a,const char* b){(void)a;(void)b;return -1;}\n" ++
            "void* X11_GLES_CreateContext(void* a,void* b){(void)a;(void)b;return 0;}\n" ++
            "int X11_GLES_MakeCurrent(void* a,void* b){(void)a;(void)b;return -1;}\n" ++
            "void X11_GLES_SwapWindow(void* a){(void)a;}\n" ++
            "void SDL_IME_PumpEvents(void){}\n";
        const egl_stub_file = b.addWriteFiles();
        const egl_stub_entry = egl_stub_file.add("sdl_egl_stub.c", egl_stub_code);
        sdl2_zig.addCSourceFile(.{ .file = egl_stub_entry, .flags = &.{} });
        sdl2_zig.root_module.addIncludePath(egl_stub_file.getDirectory());
    }
    if (cross_macos_stub) {
        // Add a minimal stub to satisfy the linker (SDL_Init/SDL_Quit/...)
        const stub_code =
            "#include <stdint.h>\n" ++
            "typedef struct SDL_Window SDL_Window;\n" ++
            "typedef struct SDL_Renderer SDL_Renderer;\n" ++
            "typedef void SDL_mutex;\n" ++
            "int SDL_Init(uint32_t flags){(void)flags;return 0;}\n" ++
            "void SDL_Quit(void){}\n" ++
            "int SDL_CreateWindowAndRenderer(int w,int h,unsigned f,SDL_Window** win,SDL_Renderer** ren){(void)w;(void)h;(void)f;if(win)*win=0;if(ren)*ren=0;return 0;}\n" ++
            "void SDL_DestroyWindow(SDL_Window* w){(void)w;}\n" ++
            "void SDL_DestroyRenderer(SDL_Renderer* r){(void)r;}\n" ++
            "int SDL_PollEvent(void* e){(void)e;return 0;}\n" ++
            "void* X11_GLES_GetVisual(void* a){(void)a;return 0;}\n" ++
            "int SDL_EGL_CreateSurface(void* a, void* b){(void)a;(void)b;return 0;}\n" ++
            "int SDL_EGL_LoadLibrary(void* a,const char* b){(void)a;(void)b;return -1;}\n" ++
            "int SDL_SetRenderDrawColor(SDL_Renderer* r,unsigned char R,unsigned char G,unsigned char B,unsigned char A){(void)r;(void)R;(void)G;(void)B;(void)A;return 0;}\n" ++
            "int SDL_IME_ProcessKeyEvent(void* a, void* b){(void)a;(void)b;return 0;}\n" ++
            "void SDL_IME_UpdateTextRect(void){}\n" ++
            "void SDL_IME_SetFocus(int f){(void)f;}\n" ++
            "int SDL_IME_Init(void){return 0;}\n" ++
            "void SDL_IME_Quit(void){}\n" ++
            "void SDL_IME_Reset(void){}\n" ++
            "int SDL_RenderClear(SDL_Renderer* r){(void)r;return 0;}\n" ++
            "void SDL_RenderPresent(SDL_Renderer* r){(void)r;}\n" ++
            "SDL_mutex* SDL_CreateMutex(void){return (SDL_mutex*)1;}\n" ++
            "void SDL_DestroyMutex(SDL_mutex* m){(void)m;}\n" ++
            "int SDL_LockMutex(SDL_mutex* m){(void)m;return 0;}\n" ++
            "int SDL_UnlockMutex(SDL_mutex* m){(void)m;return 0;}\n" ++
            "void SDL_NSLog(const char* fmt,...){(void)fmt;}\n" ++
            "char* SDL_GetErrBuf(void){static char b[1]={0};return b;}\n";
        const stub_file = b.addWriteFiles();
        const stub_entry = stub_file.add("sdl_stub_min.c", stub_code);
        sdl2_zig.addCSourceFile(.{ .file = stub_entry, .flags = &.{} });
    }

    // Note: we do not link system libraries (pthread, X11, etc.) into the static archive
    // to avoid embedding objects from shared libs. The consuming executable links them explicitly.

    sdl2_zig.installHeadersDirectory(dep_sdl2_c.path("include"), "", .{});

    // Dynapi stub: neutralize dynamic API to avoid *_REAL symbols.
    const local_include = b.addWriteFiles();
    // Also create the dynapi subdirectory expected by internal includes ("dynapi/SDL_dynapi.h")
    _ = local_include.add("dynapi/SDL_dynapi.h", "#ifndef SDL_dynapi_h_\n" ++ "#define SDL_dynapi_h_\n" ++ "#define SDL_DYNAMIC_API 0\n" ++ "/* Minimal dynapi stub: prevents #error from original header and avoids *_REAL macro indirection. */\n" ++ "#endif /* SDL_dynapi_h_ */\n");
    // Note: no global SDL_config.h override for Vulkan on Linux: leave SDL_VIDEO_VULKAN undefined globally
    // to avoid including SDL_vulkan_internal.h in every translation unit. Activation is per-file above.
    if (!traits_full.is_windows and !cross_macos_stub) {
        _ = local_include.add("SDL_config.h", genSDLConfigNonWindows(allocator, opts));
    }
    if (traits_full.is_windows) {
        // Provide a custom SDL_config.h before official includes to override selected options.
        var win_cfg = std.ArrayList(u8).init(std.heap.page_allocator);
        win_cfg.appendSlice("#pragma once\n#include <SDL_config_windows.h>\n") catch {};
        if (!opts.joystick) win_cfg.appendSlice("#undef SDL_JOYSTICK\n#define SDL_JOYSTICK 0\n#define SDL_JOYSTICK_DISABLED 1\n") catch {};
        if (!opts.haptic) win_cfg.appendSlice("#undef SDL_HAPTIC\n#define SDL_HAPTIC 0\n#define SDL_HAPTIC_DISABLED 1\n") catch {};
        if (!opts.sensor) win_cfg.appendSlice("#undef SDL_SENSOR\n#define SDL_SENSOR 0\n#define SDL_SENSOR_DISABLED 1\n") catch {};
        if (!opts.hidapi) win_cfg.appendSlice("#undef SDL_HIDAPI\n#define SDL_HIDAPI 0\n") catch {};
        if (!opts.audio) win_cfg.appendSlice("#undef SDL_AUDIO\n#define SDL_AUDIO 0\n#define SDL_AUDIO_DISABLED 1\n") catch {};
        if (opts.audio) win_cfg.appendSlice("#undef SDL_AUDIO\n#define SDL_AUDIO 1\n") catch {};
        win_cfg.appendSlice("#undef SDL_VIDEO_OPENGL\n#define SDL_VIDEO_OPENGL 1\n#define SDL_VIDEO_OPENGL_WGL 1\n") catch {};
        win_cfg.appendSlice("#undef SDL_VIDEO_OPENGL_ES2\n#undef SDL_VIDEO_OPENGL_EGL\n") catch {};
        if (opts.vulkan) {
            win_cfg.appendSlice("#undef SDL_VIDEO_VULKAN\n#define SDL_VIDEO_VULKAN 1\n") catch {};
        } else {
            win_cfg.appendSlice("#undef SDL_VIDEO_VULKAN\n") catch {};
        }
        win_cfg.appendSlice("#undef SDL_VIDEO_DRIVER_DUMMY\n#undef SDL_VIDEO_RENDER_D3D\n#undef SDL_VIDEO_RENDER_D3D11\n#undef SDL_VIDEO_RENDER_D3D12\n#undef SDL_VIDEO_RENDER_OGL_ES2\n#undef SDL_VIDEO_RENDER_VULKAN\n#undef SDL_VIDEO_RENDER_METAL\n#define SDL_VIDEO_RENDER_SW 1\n") catch {};
        if (opts.sdl_assert) win_cfg.appendSlice("#define SDL_ASSERT_LEVEL 1\n#define SDL_ENABLE_ASSERTIONS 1\n") catch {};
        _ = local_include.add("SDL_config.h", win_cfg.toOwnedSlice() catch "#pragma once\n");
        // Minimal stub to force absence of GLES (empty) if ever included.
        _ = local_include.add("video/windows/SDL_windowsopengles.h", "#ifndef SDL_winopengles_h_\n#define SDL_winopengles_h_\n/* GLES path disabled: using WGL only */\n#endif\n");
        // Minimal EGL stub to satisfy SDL_egl.h if it gets included through Windows GLES header
        _ = local_include.add("EGL/egl.h", "#ifndef __EGL_EGL_H_\n#define __EGL_EGL_H_\n" ++ "#include <stdint.h>\n" ++ "typedef void *EGLDisplay;\n" ++ "typedef void *EGLContext;\n" ++ "typedef void *EGLConfig;\n" ++ "typedef void *EGLSurface;\n" ++ "typedef int EGLint;\n" ++ "typedef int EGLBoolean;\n" ++ "typedef int EGLenum;\n" ++ "#ifndef EGLAPIENTRY\n#define EGLAPIENTRY\n#endif\n" ++ "typedef void* NativeDisplayType;\n" ++ "typedef void* NativeWindowType;\n" ++ "typedef void* EGLSyncKHR;\n" ++ "typedef long long EGLTimeKHR;\n" ++ "#define EGL_NO_DISPLAY ((EGLDisplay)0)\n" ++ "#define EGL_NO_CONTEXT ((EGLContext)0)\n" ++ "#define EGL_NO_SURFACE ((EGLSurface)0)\n" ++ "#define EGL_FALSE 0\n" ++ "#define EGL_TRUE 1\n" ++ "static inline EGLint eglGetError(void){return 0;}\n" ++ "static inline EGLDisplay eglGetDisplay(void* dpy){(void)dpy; return (EGLDisplay)0;}\n" ++ "static inline EGLBoolean eglInitialize(EGLDisplay d,EGLint* maj,EGLint* min){(void)d; if(maj) *maj=1; if(min) *min=4; return EGL_FALSE;}\n" ++ "static inline EGLBoolean eglTerminate(EGLDisplay d){(void)d; return EGL_TRUE;}\n" ++ "#endif /* __EGL_EGL_H_ */\n");
        _ = local_include.add("EGL/eglext.h", "#ifndef __EGL_EGLEXT_H_\n#define __EGL_EGLEXT_H_\n/* Minimal stub */\n#define EGL_EXTENSIONS 1\n#endif\n");
        _ = local_include.add("EGL/eglplatform.h", "#ifndef __EGL_EGLPLATFORM_H_\n#define __EGL_EGLPLATFORM_H_\n#include <stdint.h>\ntypedef intptr_t EGLNativeDisplayType;\ntypedef intptr_t EGLNativePixmapType;\ntypedef intptr_t EGLNativeWindowType;\n#endif\n");
    } else if (traits_full.is_macos and cross_macos_stub) {
        // Configuration stub when cross compiling to macOS without an SDK.
        _ = local_include.add("SDL_config.h", "#pragma once\n" ++ "#include <SDL_config_minimal.h>\n" ++ "#undef SDL_AUDIO\n#define SDL_AUDIO 0\n#define SDL_AUDIO_DISABLED 1\n" ++ "#undef SDL_VIDEO\n#define SDL_VIDEO 0\n#define SDL_VIDEO_DISABLED 1\n" ++ "#undef SDL_VIDEO_DRIVER_COCOA\n#define SDL_VIDEO_DRIVER_COCOA 0\n" ++ "#undef SDL_VIDEO_OPENGL\n#define SDL_VIDEO_OPENGL 0\n" ++ "#undef SDL_VIDEO_VULKAN\n#define SDL_VIDEO_VULKAN 0\n" ++ "#define SDL_ASSERT_LEVEL 1\n#define SDL_ENABLE_ASSERTIONS 1\n");
        // Stubs for internal video headers indirectly referenced by events.
        _ = local_include.add("video/SDL_vulkan_internal.h", "#pragma once\n/* stub vulkan internal to silence inclusion when SDL_VIDEO_VULKAN=0 */\n");
        _ = local_include.add("video/SDL_sysvideo.h", "#pragma once\n/* stub sysvideo for cross macOS stub build */\ntypedef struct SDL_Window { int _unused; } SDL_Window;\ntypedef struct SDL_VideoDevice { int _unused; } SDL_VideoDevice;\n");
    }

    // Assertions
    // (Assertion flags already injected in common_flags via sdl_assert)
    // Add stub include dir first so it shadows real version
    sdl2_zig.root_module.addIncludePath(local_include.getDirectory());
    // Includes officiels SDL
    sdl2_zig.root_module.addIncludePath(dep_sdl2_c.path("include"));

    b.installArtifact(sdl2_zig);

    return .{ .compile = sdl2_zig, .module = sdl2_zig.root_module, .local_include = local_include.getDirectory(), .sdl_include = dep_sdl2_c.path("include") };
}

/// Simplified variant: directly adds SDL2 sources to an executable module
/// to avoid potential static archive link ordering issues.
pub fn addSdl2ToExe(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) struct { local_include: std.Build.LazyPath, sdl_include: std.Build.LazyPath } {
    const dep_sdl2_c = b.dependency("sdl2_c", .{ .target = target, .optimize = optimize });
    const opt_enable_x11 = b.option(bool, "enable-x11", "Enable X11 video driver (Linux) for direct variant") orelse true;
    const opt_enable_vulkan = b.option(bool, "enable-vulkan", "Enable Vulkan (direct variant)") orelse false;

    const allocator = std.heap.page_allocator;

    var files = recursive_search_c_files(allocator, dep_sdl2_c.path("src").getPath3(b, null), "src") catch {
        std.debug.panic("Failed to search for SDL2 C source files.\n", .{});
    };

    const skip_substrings = [_][]const u8{ // NOTE: Kept identical to the original to avoid regressions
        "/android/",         "/windows/",           "/winrt/",             "/gdk/",            "/xbox/",              "/wingdk/",       "/n3ds/",        "/psp/",                  "/ps2/",             "/vita/",        "/emscripten/",   "/riscos/",           "/pandora/",      "/raspberry/",  "/haiku/",       "/qnx/",            "/os2/",      "/directfb/", "/vivante/", "/wayland/",         "/kmdir/",            "/kmsdrm/",         "/metal/",                      "/uikit/",  "/darwin/", "/macosx/", "/iphone/", "/ios/",        "/tvos/",                 "/visionos/",                "/watchos/",                 "/steam/",                    "/gdk/",                      "/loongarch/",               "/bsd/", "/openbsd/", "/netbsd/", "/freebsd/", "/nacl/", "/libusb/", "/hidapi/windows/", "/hidapi/mac/", "/hidapi/linux/hid.c", "/hidapi/SDL_hidapi_", "/xinput", "/core/linux/SDL_fcitx", "/core/linux/SDL_ibus",
        "/render/direct3d/", "/render/direct3d11/", "/render/direct3d12/", "/render/vitagxm/", "/audio/directsound/", "/audio/wasapi/", "/audio/winmm/", "/core/linux/SDL_dbus.c", "/video/offscreen/", "/video/dummy/", "/loadso/dummy/", "/filesystem/dummy/", "/locale/dummy/", "/misc/dummy/", "/timer/dummy/", "/thread/generic/", "/joystick/", "/haptic/",   "/sensor/",  "/render/opengles/", "/render/opengles2/", "/video/SDL_egl.c", "/video/x11/SDL_x11opengles.c", "/dynapi/", "/audio/",  "/test/",   "/hidapi/", "/audio/alsa/", "/core/linux/SDL_udev.c", "/video/x11/SDL_x11mouse.c", "/video/x11/SDL_x11touch.c", "/video/x11/SDL_x11events.c", "/video/x11/SDL_x11window.c", "/video/x11/SDL_x11video.c",
    };

    var filtered = std.ArrayList([]const u8).init(allocator);
    for (files.items) |file| {
        var skip = false;
        inline for (skip_substrings) |pat| {
            if (std.mem.indexOf(u8, file, pat) != null) {
                skip = true;
                break;
            }
        }
        if (!opt_enable_vulkan and std.mem.indexOf(u8, file, "/vulkan") != null) skip = true;
        if (!opt_enable_vulkan and std.mem.indexOf(u8, file, "SDL_vulkan_utils.c") != null) skip = true;
        if (opt_enable_vulkan and (std.mem.indexOf(u8, file, "SDL_x11vulkan.c") != null or std.mem.indexOf(u8, file, "SDL_windowsvulkan.c") != null)) {
            // keep
        }
        if (!skip) filtered.append(file) catch {};
    }
    files.deinit();
    files = filtered;

    const common_flags = [_][]const u8{
        "-DHAVE_STDIO_H",       "-DHAVE_STDLIB_H", "-DHAVE_STRING_H",        "-DHAVE_CTYPE_H",          "-DHAVE_MATH_H",       "-DHAVE_SIGNAL_H",
        "-DHAVE_INTTYPES_H",    "-DHAVE_STDINT_H", "-DHAVE_SYS_TYPES_H",     "-DHAVE_SYS_STAT_H",       "-DHAVE_UNISTD_H",     "-D_REENTRANT",
        "-DSDL_VIDEO=1",        "-DSDL_AUDIO=0",   "-DSDL_AUDIO_DISABLED=1", "-DSDL_THREADS=1",         "-DSDL_TIMER=1",       "-DSDL_LOADSO=1",
        "-DSDL_ATOMIC=1",       "-DSDL_EVENTS=1",  "-DSDL_LOCALE=1",         "-DSDL_MISC=1",            "-DSDL_DYNAMIC_API=0", "-DSDL_JOYSTICK=0",
        "-DSDL_HAPTIC=0",       "-DSDL_SENSOR=0",  "-DSDL_HIDAPI=0",         "-DSDL_JOYSTICK_HIDAPI=0", "-DSDL_USE_IME=0",     "-DHAVE_DBUS=0",
        "-DSDL_VIDEO_OPENGL=0",
    };

    if (target.result.os.tag == .linux) {
        if (opt_enable_x11) {
            exe.addCSourceFiles(.{ .root = dep_sdl2_c.path(""), .files = &.{}, .flags = &.{} }); // no-op placeholder to keep ordering
            exe.addCSourceFiles(.{ .root = dep_sdl2_c.path(""), .files = &.{}, .flags = &.{} });
            exe.addCSourceFiles(.{ .root = dep_sdl2_c.path(""), .files = &.{}, .flags = &.{} });
            exe.addAssemblyFile(.{ .path = "" }) catch {}; // ignored if empty
        }
    }

    exe.addCSourceFiles(.{ .root = dep_sdl2_c.path(""), .files = files.items, .flags = &common_flags });

    if (target.result.os.tag == .linux) {
        exe.linkSystemLibrary("pthread");
        exe.linkSystemLibrary("dl");
        exe.linkSystemLibrary("m");
        exe.linkSystemLibrary("X11");
        exe.linkSystemLibrary("Xext");
        exe.linkSystemLibrary("Xcursor");
        exe.linkSystemLibrary("Xrandr");
        exe.linkSystemLibrary("Xi");
    }

    const local_include = b.addWriteFiles();
    _ = local_include.add("SDL_config.h", "#pragma once\n" ++ "#include <SDL_config_minimal.h>\n" ++ "#undef SDL_LOADSO_DISABLED\n" // explicit LOADSO reactivation
    ++ (if (opt_enable_x11 and target.result.os.tag == .linux) "#undef SDL_VIDEO_DRIVER_X11\n#define SDL_VIDEO_DRIVER_X11 1\n#define SDL_VIDEO_DRIVER_X11_SUPPORTS_GENERIC_EVENTS 1\n" else "#undef SDL_VIDEO_DRIVER_X11\n#define SDL_VIDEO_DRIVER_X11 0\n#define SDL_VIDEO_DRIVER_DUMMY 1\n") ++ "#define SDL_LOADSO_DLOPEN 1\n" ++ "#define SDL_THREAD_PTHREAD 1\n" ++ "#define SDL_TIMER_UNIX 1\n" ++ "#undef SDL_AUDIO\n#define SDL_AUDIO 0\n" ++ "#define SDL_FILESYSTEM_UNIX 1\n" ++ "#define SDL_USE_LIBUDEV 0\n" ++ "#define SDL_VIDEO_RENDER_SW 1\n" ++ "#define SDL_VIDEO_OPENGL 0\n" ++ (if (opt_enable_vulkan) "#define SDL_VIDEO_VULKAN 1\n" else "#undef SDL_VIDEO_VULKAN\n") ++ "#define SDL_JOYSTICK_DISABLED 1\n" ++ "#define SDL_HAPTIC_DISABLED 1\n" ++ "#define SDL_SENSOR_DISABLED 1\n" ++ "#define SDL_ASSERT_LEVEL 1\n" ++ "#define SDL_ENABLE_ASSERTIONS 1\n");
    _ = local_include.add("SDL_vulkan_internal.h", "#ifndef SDL_VULKAN_INTERNAL_H\n#define SDL_VULKAN_INTERNAL_H\n/* Vulkan disabled stub */\n#endif\n");
    exe.addIncludePath(local_include.getDirectory());
    exe.addIncludePath(dep_sdl2_c.path("include"));

    return .{ .local_include = local_include.getDirectory(), .sdl_include = dep_sdl2_c.path("include") };
}
