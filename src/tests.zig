const std = @import("std");
const main = @import("main.zig");
const json = std.json;
const testing = std.testing;

const Io = std.Io;
const ToolRequest = @import("tool_request.zig");

test "Test Directory Operations" {
    const gba = std.testing.allocator;
    const io = std.testing.io;
    var tmp_dir = std.testing.tmpDir(main.DIR_OPTIONS);
    var w = Io.Writer.Allocating.init(gba);
    defer w.deinit();

    var body = Io.Writer.Allocating.init(gba);
    defer body.deinit();

    const body_json = ToolRequest{
        .id = 0,
        .method = "change_directory",
        .params = .{
            .name = "",
            .arguments = .{
                .filename = "..",
            },
        },
    };
    var body_formatter = json.fmt(
        body_json,
        main.OPTIONS,
    );
    try body_formatter.format(&body.writer);
    try std.testing.expectError(
        error.UseRootDirectoryCommand,
        main.handleDirectory(
            .CHANGE,
            &w.writer,
            gba,
            io,
            &tmp_dir.dir,
            body.written(),
        ),
    );
    w.clearRetainingCapacity();
    body.clearRetainingCapacity();
    const create_json = ToolRequest{
        .id = 0,
        .method = "change_directory",
        .params = .{
            .name = "",
            .arguments = .{
                .filename = "hello/world",
            },
        },
    };
    var create_formatter = json.fmt(
        create_json,
        main.OPTIONS,
    );
    try create_formatter.format(&body.writer);
    try main.handleDirectory(
        .CHANGE,
        &w.writer,
        gba,
        io,
        &tmp_dir.dir,
        body.written(),
    );
    w.clearRetainingCapacity();
    body.clearRetainingCapacity();
    const current_json = ToolRequest{
        .id = 0,
        .method = "current_directory",
        .params = .{
            .name = "",
            .arguments = .{},
        },
    };
    var current_formatter = json.fmt(
        current_json,
        main.OPTIONS,
    );
    try current_formatter.format(&body.writer);
    try main.handleDirectory(
        .CURRENT,
        &w.writer,
        gba,
        io,
        &tmp_dir.dir,
        body.written(),
    );
    try testing.expectStringEndsWith(w.written(), "\\\\hello\\\\world\"}]}}");
    std.debug.print("{s}", .{w.written()});
}