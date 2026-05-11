const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const name = @tagName(zon.name);
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const config = b.addModule("config", .{
        .root_source_file = b.path("build.zig.zon"),
    });

    const main = b.addModule(name, .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });

    main.addImport("config", config);

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = main,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const test_step = b.step("test", "Run the tests");

    const main_test = b.addTest(.{
        .root_module = main,
        
    });

    const test_cmd = b.addRunArtifact(main_test);
    test_step.dependOn(&test_cmd.step);

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
