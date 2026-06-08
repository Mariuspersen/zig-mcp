const std = @import("std");
const server = @import("server.zig");
const json = std.json;
const testing = std.testing;

const Io = std.Io;
const ToolRequest = @import("tool_request.zig");

test "Test Directory Operations" {
    const gba = std.testing.allocator;
    const io = std.testing.io;
    var tmp_dir = std.testing.tmpDir(server.DIR_OPTIONS);
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
                .directory_name = "..",
            },
        },
    };
    var formatter = json.fmt(
        req,
        server.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
    try server.handleDirectory(
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
        .method = "change_directory",
        .params = .{
            .name = "",
            .arguments = .{
                .directory_name = "hello/world",
            },
        },
    };
    formatter = json.fmt(
        req,
        server.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
    try server.handleDirectory(
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
        server.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
    try server.handleDirectory(
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
        server.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
    try server.handleDirectory(
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
        server.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
    try server.handleDirectory(
        .CURRENT,
        &w.writer,
        gba,
        io,
        &tmp_dir.dir,
        body.written(),
    );
    try testing.expectStringEndsWith(w.written(), "\"~\"}]}}");
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
        server.STRINGIFY_OPTIONS,
    );
    try formatter.format(&body.writer);
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

    var table = server.Table.init(gba);
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
        server.STRINGIFY_OPTIONS,
    );
    try body_formatter.format(&body.writer);

    try server.handleMemory(
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
        server.STRINGIFY_OPTIONS,
    );
    try body_formatter.format(&body.writer);
    try server.handleMemory(
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

test "HTML Text only" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    var client = std.http.Client{
        .allocator = alloc,
        .io = io,
    };
    defer client.deinit();

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    const res = try client.fetch(
        .{
            .location = .{
                .url = "https://www.wikipedia.org/",
            },
            .method = .GET,
            .response_writer = &response.writer,
        },
    );
    _ = res;
    const HTMLParser = @import("html_parser.zig");

    var reader = Io.Reader.fixed(response.written());
    var writer = Io.Writer.Allocating.init(alloc);
    defer writer.deinit();

    try HTMLParser.getText(&reader, &writer.writer);

    const trimmed = std.mem.trim(u8, writer.written(), " ");
    var space_it = std.mem.splitAny(u8, trimmed, " \n");

    var space = Io.Writer.Allocating.init(alloc);
    defer space.deinit();

    while (space_it.next()) |text| {
        if (text.len == 0) continue;
        try space.writer.print("{s} ", .{text});
    }
}
