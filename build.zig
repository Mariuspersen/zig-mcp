const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const server_name = @tagName(zon.name);
    const agent_name = "zig_agent";
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const config = b.addModule("config", .{
        .root_source_file = b.path("build.zig.zon"),
    });

    const server = b.addModule(server_name, .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/server.zig"),
    });

    const agent = b.addModule(agent_name, .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/agent.zig"),
    });

    const tests = b.addModule(server_name, .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/tests.zig"),
    });

    agent.addImport("config", config);
    server.addImport("config", config);
    tests.addImport("config", config);

    const server_exe = b.addExecutable(.{
        .name = server_name,
        .root_module = server,
    });

    const agent_exe = b.addExecutable(.{
        .name = agent_name,
        .root_module = agent,
    });

    b.installArtifact(server_exe);
    b.installArtifact(agent_exe);

    const server_step = b.step("server", "Run the server");
    const agent_step = b.step("agent", "Run the agent");
    const test_step = b.step("test", "Run the tests");

    const main_test = b.addTest(.{
        .root_module = tests,
        
    });

    const test_cmd = b.addRunArtifact(main_test);
    test_step.dependOn(&test_cmd.step);

    const run_server = b.addRunArtifact(server_exe);
    server_step.dependOn(&run_server.step);

    const run_agent = b.addRunArtifact(agent_exe);
    agent_step.dependOn(&run_agent.step);

    run_server.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_server.addArgs(args);
    }

    run_agent.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_agent.addArgs(args);
    }
}
