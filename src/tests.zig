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

    var req = ToolRequest{
        .id = 0,
        .method = "change_directory",
        .params = .{
            .name = "",
            .arguments = .{
                .filename = "..",
            },
        },
    };
    var formatter = json.fmt(
        req,
        main.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
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
    req = ToolRequest{
        .id = 0,
        .method = "change_directory",
        .params = .{
            .name = "",
            .arguments = .{
                .filename = "hello/world",
            },
        },
    };
    formatter = json.fmt(
        req,
        main.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
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
    req = ToolRequest{
        .id = 0,
        .method = "current_directory",
        .params = .{
            .name = "",
            .arguments = .{},
        },
    };
    formatter = json.fmt(
        req,
        main.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
    try main.handleDirectory(
        .CURRENT,
        &w.writer,
        gba,
        io,
        &tmp_dir.dir,
        body.written(),
    );
    try testing.expectStringEndsWith(w.written(), "/hello/world\"}]}}");
    w.clearRetainingCapacity();
    body.clearRetainingCapacity();
    const root_json = ToolRequest{
        .id = 0,
        .method = "root_directory",
        .params = .{
            .name = "",
            .arguments = .{},
        },
    };
    formatter = json.fmt(
        root_json,
        main.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
    try main.handleDirectory(
        .ROOT,
        &w.writer,
        gba,
        io,
        &tmp_dir.dir,
        body.written(),
    );
    w.clearRetainingCapacity();
    body.clearRetainingCapacity();
    req = ToolRequest{
        .id = 0,
        .method = "current_directory",
        .params = .{
            .name = "",
            .arguments = .{},
        },
    };
    formatter = json.fmt(
        req,
        main.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
    try main.handleDirectory(
        .CURRENT,
        &w.writer,
        gba,
        io,
        &tmp_dir.dir,
        body.written(),
    );
    try testing.expectStringEndsWith(w.written(), "/storage\"}]}}");
    req = ToolRequest{
        .id = 0,
        .method = "change_directory",
        .params = .{
            .name = "",
            .arguments = .{
                .filename = "/",
            },
        },
    };
    formatter = json.fmt(
        req,
        main.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
    std.debug.print("{s}\n", .{w.written()});
    w.clearRetainingCapacity();
    body.clearRetainingCapacity();
}

test "Check memory recalling" {
    const keyword = "ai";
    const content =
        \\AI's are very dumb and I am one, double and triple check everything I do, prompt the user if I'm doing it right
        \\Make sure the user knows exactly what I'm doing, so I can be corrected early in the process.
    ;
    const gba = std.testing.allocator;
    var w = Io.Writer.Allocating.init(gba);
    defer w.deinit();

    var table = main.Table.init(gba);
    defer {
        var it = table.iterator();
        while (it.next()) |entry| {
            gba.free(entry.key_ptr.*);
            entry.value_ptr.deinit(gba);
        }
        table.deinit();
    }

    var body = Io.Writer.Allocating.init(gba);
    defer body.deinit();

    var body_json = ToolRequest{
        .id = 0,
        .method = "remember",
        .params = .{
            .name = "",
            .arguments = .{
                .keyword = keyword,
                .content = content,
            },
        },
    };
    var body_formatter = json.fmt(
        body_json,
        main.STRINGIFY_OPTIONS,
    );
    try body_formatter.format(&body.writer);

    try main.handleMemory(
        .REMEMBER,
        &w.writer,
        gba,
        body.written(),
        &table,
    );
    w.clearRetainingCapacity();
    body.clearRetainingCapacity();
    body_json = ToolRequest{
        .id = 0,
        .method = "recall",
        .params = .{
            .name = "",
            .arguments = .{
                .keyword = keyword,
            },
        },
    };
    body_formatter = json.fmt(
        body_json,
        main.STRINGIFY_OPTIONS,
    );
    try body_formatter.format(&body.writer);
    try main.handleMemory(
        .RECALL,
        &w.writer,
        gba,
        body.written(),
        &table,
    );
    try testing.expectStringEndsWith(
        w.written(),
        "are very dumb and I am one, double and triple check everything I do, prompt the user if I'm doing it right\\nMake sure the user knows exactly what I'm doing, so I can be corrected early in the process.\\n\"" ++ "}]}}",
    );
}
