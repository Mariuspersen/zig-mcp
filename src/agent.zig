const std = @import("std");
const json = std.json;
const Io = std.Io;

const Config = @import("config");

const Message = @import("message.zig");
const Server = @import("server.zig");
const ToolRequest = @import("tool_request.zig");

pub const Table = std.StringHashMap(std.ArrayList(u8));


pub fn main(init: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var threaded = Io.Threaded.init(
        gpa,
        .{
            .environ = init.environ,
        },
    );
    defer threaded.deinit();
    const io = threaded.io();

    var map = try threaded.environ.process_environ.createMap(gpa);
    _ = &map;

    var table = Table.init(gpa);
    defer {
        var it = table.iterator();
        while (it.next()) |entry| {
            gpa.free(entry.key_ptr.*);
            entry.value_ptr.deinit(gpa);
        }
        table.deinit();
    }

    var dir = try Io.Dir.cwd().openDir(io, ".", Server.DIR_OPTIONS);
    defer dir.close(io);

    var messages = try std.ArrayList(Message).initCapacity(gpa, 2);
    defer messages.deinit(gpa);

    var text_buf = try std.ArrayList(Io.Writer.Allocating).initCapacity(gpa, 2);
    defer text_buf.deinit(gpa);

    const stdin_buf = try gpa.alloc(u8, 1024);
    defer gpa.free(stdin_buf);

    const stdout_buf = try gpa.alloc(u8, 1024);
    defer gpa.free(stdout_buf);

    var f_stdin = Io.File.stdin();
    var stdin_reader = f_stdin.reader(io, stdin_buf);
    const stdin = &stdin_reader.interface;

    var f_stdout = Io.File.stdout();
    var stdout_reader = f_stdout.writer(io, stdout_buf);
    const stdout = &stdout_reader.interface;

    var id_count: usize = 0;

    while (true) {
        defer id_count += 1;
        try text_buf.append(gpa, .init(gpa));
        var buffer = text_buf.getLast();

        try stdout.writeAll("USER: ");
        try stdout.flush();
        _ = try stdin.streamDelimiter(&buffer.writer, '\n');
        stdin.toss(1);

        try text_buf.append(gpa, .init(gpa));
        var promp_response = text_buf.getLast();

        const tool_request = ToolRequest{
            .id = id_count,
            .method = "",
            .params = .{
                .arguments = .{
                    .prompt = buffer.written(),
                },
                .name = "",
            }
        };

        try text_buf.append(gpa, .init(gpa));
        var tool_request_allocating = text_buf.getLast();

        var tool_request_formatter = json.fmt(tool_request, Server.STRINGIFY_OPTIONS);
        try tool_request_formatter.format(&tool_request_allocating.writer);

        try Server.handlePromptOtherImpl(
            &promp_response.writer,
            stdout,
            gpa,
            &dir,
            io,
            tool_request_allocating.written(),
            &table,
            Config.remote_llm,
            &map,
            &messages,
        );

        const response = messages.getLast();
        try stdout.print("{s}: {s}\n", .{"LLM",response.content});
        try stdout.flush();
    }
}
