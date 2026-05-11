const std = @import("std");
const Config = @import("config");
const http = std.http;
const json = std.json;
const Io = std.Io;
const net = Io.net;
const time = std.time;
const epoch = time.epoch;

const Writer = Io.Writer;
const Allocator = std.mem.Allocator;

const IpAddress = net.IpAddress;

const hash = std.hash.Crc32.hash;

const PROTOCOL_VERSION = Config.PROTOCOL_VERSION;
const JSONRPC = Config.JSONRPC;

const OPTIONS = json.Stringify.Options{
    .emit_nonportable_numbers_as_strings = true,
    .emit_null_optional_fields = false,
    .escape_unicode = true,
    .whitespace = .minified,
    .emit_strings_as_arrays = false,
};

const DIR_OPTIONS = Io.Dir.OpenOptions{
    .follow_symlinks = false,
    .iterate = true,
    .access_sub_paths = false,
};

const MethodJson = @import("method_only.zig");
const ToolNameReq = @import("tool_name_req.zig");
const InitResponse = @import("init_response.zig");
const InitRequest = @import("init_request.zig");
const WhichTool = @import("which_tool.zig");
const ToolEntry = @import("tool_entry.zig");
const ToolResponse = @import("tool_response.zig");
const ToolRequest = @import("tool_request.zig");
const ContentType = @import("content_type.zig");
const ToolResult = @import("tool_result.zig");
const ProtocolError = @import("protocol_error.zig");

const address = IpAddress.parse(Config.hostname, Config.port) catch |e| {
    @compileError("Unable to resolve IP Address: " ++ e);
};

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;

    var dir = try rootDir(io);

    defer dir.close(io);

    const stdout_buf = try alloc.alloc(u8, 1024);
    defer alloc.free(stdout_buf);

    var stdout_writer = Io.File.stdout().writer(io, stdout_buf);
    const stdout = &stdout_writer.interface;

    try stdout.print("{s} version {s}\n", .{ @tagName(Config.name), Config.version });
    try stdout.flush();

    var server = try address.listen(io, .{ .reuse_address = true });

    try stdout.print("Listening on {s}:{d}\n", .{ Config.hostname, Config.port });
    try stdout.flush();

    defer server.deinit(io);
    while (server.accept(io)) |s| {
        handleConnection(
            alloc,
            s,
            io,
            &dir,
            init.environ_map,
            stdout,
        ) catch |e| errorWriter(e);
    } else |e| errorWriter(e);
}

fn rootDir(io: Io) !Io.Dir {
    return Io.Dir.cwd().openDir(io, "storage", DIR_OPTIONS) catch blk: {
        try Io.Dir.cwd().createDir(io, "storage", .default_dir);
        break :blk try Io.Dir.cwd().openDir(io, "storage", DIR_OPTIONS);
    };
}

fn changeDir(dir: *Io.Dir, io: Io, new_dir: []const u8) !Io.Dir {
    return dir.openDir(io, new_dir, DIR_OPTIONS) catch blk: {
        try dir.createDir(io, new_dir, .default_dir);
        break :blk try dir.openDir(io, new_dir, DIR_OPTIONS);
    };
}

fn errorWriter(e: anyerror) void {
    const io = std.Options.debug_io;
    var buf: [64]u8 = undefined;
    var locked_stderr = io.lockStderr(&buf, null) catch return;
    locked_stderr.file_writer.interface.print("ERROR: {s}", .{@errorName(e)}) catch return;
}

fn handleConnection(alloc: Allocator, s: net.Stream, io: Io, dir: *Io.Dir, map: *const std.process.Environ.Map, stdout: *Io.Writer) !void {
    defer s.close(io);
    const read_buf = try alloc.alloc(u8, 1024);
    defer alloc.free(read_buf);

    var reader = s.reader(io, read_buf);

    const write_buf = try alloc.alloc(u8, 1024);
    defer alloc.free(write_buf);

    var writer = s.writer(io, write_buf);

    var http_server = http.Server.init(&reader.interface, &writer.interface);

    var req = try http_server.receiveHead();

    var it = req.iterateHeaders();
    var len: usize = 0;
    while (it.next()) |header| if (std.mem.eql(u8, "Content-Length", header.name)) {
        len = try std.fmt.parseInt(usize, header.value, 10);
    };

    const tx_buf = try alloc.alloc(u8, len);
    defer alloc.free(tx_buf);

    var body_reader = req.server.reader.bodyReader(tx_buf, .none, len);
    const body = try body_reader.readAlloc(alloc, len);
    defer alloc.free(body);
    var res_writer = Io.Writer.Allocating.init(alloc);
    defer res_writer.deinit();

    const methodJson = try json.parseFromSlice(MethodJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    const hash_method = hash(methodJson.value.method);
    methodJson.deinit();

    try stdout.print("REQUEST: {s}\n", .{body});
    switch (hash_method) {
        hash("initialize") => try handleInitialize(
            &res_writer.writer,
            body,
            alloc,
        ),
        hash("notifications/initialized"),
        hash("notifications/cancelled"),
        => try res_writer.writer.writeAll("{}"),
        hash("tools/list") => try handleListTools(
            &res_writer.writer,
            body,
            alloc,
        ),
        hash("tools/call") => try handleCallTools(
            &res_writer.writer,
            alloc,
            dir,
            io,
            map,
            body,
        ),
        else => {
            try req.respond("{}", .{ .status = .not_found });
            return;
        },
    }
    try stdout.print("RESPONSE: {s}\n", .{res_writer.written()});
    try stdout.flush();
    try req.respond(res_writer.written(), .{ .status = .ok });
}

fn handleInitialize(w: *Writer, body: []u8, alloc: Allocator) !void {
    const parsedBody = try json.parseFromSlice(InitRequest, alloc, body, .{});
    defer parsedBody.deinit();

    const req_json: InitRequest = parsedBody.value;

    const init_res_json = InitResponse{
        .id = req_json.id,
        .result = .{
            .capabilities = .{},
            .serverInfo = .{},
        },
    };
    var res_json_struct_fmt = json.fmt(init_res_json, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleListTools(w: *Writer, body: []u8, alloc: Allocator) !void {
    const parsedBody = try json.parseFromSlice(WhichTool, alloc, body, .{});
    defer parsedBody.deinit();

    const res_json_struct = ToolResponse{
        .id = parsedBody.value.id,
        .result = .{
            .tools = &[_]ToolEntry{
                ToolEntry{
                    .name = "arithmetic",
                    .description = "Performs arithmetic (add, subtract, multiply, divide, sqrt)",
                    .title = "Arithmetic",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{"operation"},
                        .properties = .{
                            .a = .{},
                            .b = .{},
                            .operation = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "file_write",
                    .description = "Creates a file and writes content to it",
                    .title = "File Write",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{ "filename", "content" },
                        .properties = .{
                            .filename = .{},
                            .content = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "file_append",
                    .description = "Opens a file and appends content to the end",
                    .title = "File Append",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{ "filename", "content" },
                        .properties = .{
                            .filename = .{},
                            .content = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "file_overwrite",
                    .description = "Opens a file and overwrites text at start",
                    .title = "File Insert",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{ "filename", "content", "start" },
                        .properties = .{
                            .filename = .{},
                            .content = .{},
                            .start = .{ .description = "Index of where to insert" },
                        },
                    },
                },
                ToolEntry{
                    .name = "file_read",
                    .description = "Opens the file and reads all of it",
                    .title = "File Read",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{"filename"},
                        .properties = .{
                            .filename = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "file_read_slice",
                    .description = "Opens a file, returns the slice between start and end",
                    .title = "File Read",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{"filename"},
                        .properties = .{
                            .filename = .{},
                            .start = .{},
                            .end = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "file_list",
                    .description = "Returns a list of all available files",
                    .title = "File List",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{},
                        .properties = .{},
                    },
                },
                ToolEntry{
                    .name = "file_size",
                    .description = "Returns the size of a file",
                    .title = "File Size",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{},
                        .properties = .{
                            .filename = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "file_delete",
                    .description = "Delete a file",
                    .title = "File Delete",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{},
                        .properties = .{
                            .filename = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "change_directory",
                    .description = "Change current directory",
                    .title = "Change Directory",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{},
                        .properties = .{
                            .filename = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "current_directory",
                    .description = "See current directory",
                    .title = "Current Directory",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{},
                        .properties = .{
                            .filename = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "root_directory",
                    .description = "Return to the root directory",
                    .title = "Root Directory",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{},
                        .properties = .{
                            .filename = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "date_time",
                    .description = "Returns the date and time",
                    .title = "Date and Time",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{},
                        .properties = .{},
                    },
                },
                ToolEntry{
                    .name = "web_request",
                    .description = "Given a URL, returns the body of the request",
                    .title = "Web Request",
                    .inputSchema = .{
                        .required = &.{"url"},
                        .properties = .{
                            .url = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "gcc",
                    .description = "GNU C Compiler, returns output",
                    .title = "C Compiler",
                    .inputSchema = .{
                        .required = &.{"arguments"},
                        .properties = .{
                            .arguments = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "man",
                    .description = "man command for reading system reference manuals",
                    .title = "Manual Pages",
                    .inputSchema = .{
                        .required = &.{"arguments"},
                        .properties = .{
                            .arguments = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "valgrind",
                    .description = "a programming tool for memory debugging, memory leak detection, and profiling.",
                    .title = "Valgrind",
                    .inputSchema = .{
                        .required = &.{"arguments"},
                        .properties = .{
                            .arguments = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "grep",
                    .description = "greps the file",
                    .title = "File Search",
                    .inputSchema = .{
                        .required = &.{"arguments"},
                        .properties = .{
                            .arguments = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "git",
                    .description = "version control system",
                    .title = "Git",
                    .inputSchema = .{
                        .required = &.{"arguments"},
                        .properties = .{
                            .arguments = .{},
                        },
                    },
                },
            },
        },
    };

    var res_json_struct_fmt = json.fmt(res_json_struct, .{
        .emit_null_optional_fields = false,
    });
    try res_json_struct_fmt.format(w);
}

fn handleCallTools(w: *Writer, alloc: Allocator, dir: *Io.Dir, io: Io, map: *const std.process.Environ.Map, body: []u8) !void {
    _ = map;
    const methodJson = try json.parseFromSlice(ToolNameReq, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    const hash_method = hash(methodJson.value.params.name);
    methodJson.deinit();

    const id = methodJson.value.id;

    const res = switch (hash_method) {
        hash("arithmetic") => handleArithmetic(w, body, alloc),
        hash("file_write") => handleWrite(w, alloc, io, dir, body),
        hash("file_append") => handleInsert(w, alloc, io, true, dir, body),
        hash("file_overwrite") => handleInsert(w, alloc, io, false, dir, body),
        hash("file_read") => handleRead(w, alloc, io, dir, body),
        hash("file_read_slice") => handleReadSlice(w, alloc, io, dir, body),
        hash("file_list") => handleListFiles(w, alloc, io, dir, body),
        hash("file_size") => handleFileSize(w, alloc, io, dir, body),
        hash("file_delete") => handleFileDelete(w, alloc, io, dir, body),
        hash("date_time") => handleDateTime(w, alloc, io, body),
        hash("web_request") => handleWebRequest(w, alloc, io, body),
        hash("gcc") => handleCommand(&.{"gcc"}, w, alloc, io, dir, body),
        hash("man") => handleCommand(&.{"man"}, w, alloc, io, dir, body),
        hash("valgrind") => handleCommand(&.{"valgrind"}, w, alloc, io, dir, body),
        hash("grep") => handleCommand(&.{"grep"}, w, alloc, io, dir, body),
        hash("git") => handleCommand(&.{"git"}, w, alloc, io, dir, body),
        hash("change_directory") => handleDirectory(.CHANGE, w, alloc, io, dir, body),
        hash("current_directory") => handleDirectory(.CURRENT, w, alloc, io, dir, body),
        hash("root_directory") => handleDirectory(.ROOT, w, alloc, io, dir, body),
        else => handleErrorResponse(w, error.NoSuchMethod, id, alloc),
    };
    res catch |e| {
        try handleErrorResponse(w, e, id, alloc);
    };
}

const dir_op = enum {
    CHANGE,
    ROOT,
    CURRENT,
};

fn handleDirectory(op: dir_op, w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    switch (op) {
        .CHANGE => {
            const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;
            if (std.mem.eql(u8, filename, "..")) return error.UseRootDirectoryCommand;
            dir.* = try changeDir(dir, io, filename);
            try response_text.writer.print("Changed directory to: {s}", .{filename});
        },
        .CURRENT => {
            const current = try dir.realPathFileAlloc(io, ".", alloc);
            defer alloc.free(current);

            try response_text.writer.writeAll(current);
        },
        .ROOT => {
            dir.* = try rootDir(io);
            try response_text.writer.print("Changed directory to root", .{});
        },
    }

    const json_res = ToolResult{
        .id = parsed_body.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response_text.written(),
                },
            },
        },
    };
    var res_json_struct_fmt = json.fmt(json_res, OPTIONS);
    try res_json_struct_fmt.format(w);
}

test "Make sure it can't escape it's confines" {
    const gba = std.testing.allocator;
    const io = std.testing.io;
    var tmp_dir = std.testing.tmpDir(DIR_OPTIONS);
    var w = Io.Writer.Allocating.init(gba);
    defer w.deinit();

    var body = Io.Writer.Allocating.init(gba);
    defer body.deinit();

    const body_json = ToolRequest{
        .id = 0,
        .method = "change_directory",
        .params = .{
            .name = "",
            .arguments = .{ .filename = ".." },
        },
    };
    var body_formatter = json.fmt(body_json, OPTIONS);
    try body_formatter.format(&body.writer);

    try std.testing.expectError(
        error.UseRootDirectoryCommand,
        handleDirectory(
            .CHANGE,
            &w.writer,
            gba,
            io,
            &tmp_dir.dir,
            body.written(),
        ),
    );
}

fn handleArithmetic(w: *Writer, body: []u8, alloc: Allocator) !void {
    const parsedBody = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsedBody.deinit();

    const parsed_json: ToolRequest = parsedBody.value;
    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    const op = parsed_json.params.arguments.operation orelse return error.MissingOperator;

    const hashed_op = hash(op);
    switch (hashed_op) {
        hash("add"), hash("addition"), hash("+") => {
            const a = parsed_json.params.arguments.a orelse return error.MissingArgumentA;
            const b = parsed_json.params.arguments.b orelse return error.MissingArgumentB;
            try response_text.writer.print("{d}", .{a + b});
        },
        hash("sub"), hash("subtract"), hash("-") => {
            const a = parsed_json.params.arguments.a orelse return error.MissingArgumentA;
            const b = parsed_json.params.arguments.b orelse return error.MissingArgumentB;
            try response_text.writer.print("{d}", .{a - b});
        },
        hash("div"), hash("divide"), hash("/") => {
            const a = parsed_json.params.arguments.a orelse return error.MissingArgumentA;
            const b = parsed_json.params.arguments.b orelse return error.MissingArgumentB;
            try response_text.writer.print("{d}", .{a / b});
        },
        hash("mul"), hash("multiply"), hash("*") => {
            const a = parsed_json.params.arguments.a orelse return error.MissingArgumentA;
            const b = parsed_json.params.arguments.b orelse return error.MissingArgumentB;
            try response_text.writer.print("{d}", .{a * b});
        },
        hash("sqrt") => {
            const a = parsed_json.params.arguments.a orelse return error.MissingArgumentA;
            try response_text.writer.print("{d}", .{std.math.sqrt(a)});
        },
        else => return error.UnknownOperator,
    }

    const response_json = ToolResult{
        .id = parsed_json.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response_text.written(),
                },
            },
        },
    };
    var res_json_struct_fmt = json.fmt(response_json, .{
        .emit_null_optional_fields = false,
    });
    try res_json_struct_fmt.format(w);
}

fn handleWrite(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;
    const content = parsed_json.params.arguments.content orelse return error.MissingContent;

    const f = try dir.createFile(io, filename, .{
        .resolve_beneath = true,
    });
    defer f.close(io);
    try f.writeStreamingAll(io, content);

    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    try response_text.writer.print("{d} characters written to {s}", .{ content.len, filename });

    const json_res = ToolResult{
        .id = parsed_body.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response_text.written(),
                },
            },
        },
    };
    var res_json_struct_fmt = json.fmt(json_res, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleInsert(w: *Writer, alloc: Allocator, io: Io, append: bool, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;
    const content = parsed_json.params.arguments.content orelse return error.MissingContent;

    const f = try dir.openFile(io, filename, .{
        .mode = .write_only,
    });
    defer f.close(io);

    const start = try blk: {
        if (append) break :blk f.length(io);
        break :blk parsed_json.params.arguments.start orelse error.MissingStart;
    };
    try f.writePositionalAll(io, content, start);

    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    try response_text.writer.print("{d} characters written to {s} at index {d}", .{ content.len, filename, start });

    const json_res = ToolResult{
        .id = parsed_body.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response_text.written(),
                },
            },
        },
    };
    var res_json_struct_fmt = json.fmt(json_res, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleFileDelete(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;

    //Maybe not try to delete the .git folder you dumbass AI????
    if (std.mem.startsWith(u8, filename, ".git")) return error.PermissionDenied;

    try dir.deleteFile(io, filename);

    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    try response_text.writer.print("{s} deleted", .{filename});

    const json_res = ToolResult{
        .id = parsed_body.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response_text.written(),
                },
            },
        },
    };
    var res_json_struct_fmt = json.fmt(json_res, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleFileSize(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;

    const f = try dir.openFile(io, filename, .{});
    defer f.close(io);
    const len = try f.length(io);

    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    try response_text.writer.print("{d}", .{len});

    const json_res = ToolResult{
        .id = parsed_body.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response_text.written(),
                },
            },
        },
    };
    var res_json_struct_fmt = json.fmt(json_res, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleRead(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;

    const f = try dir.openFile(io, filename, .{});
    defer f.close(io);

    const buf = try alloc.alloc(u8, 1024);
    defer alloc.free(buf);

    var reader = f.reader(io, buf);

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    _ = try reader.interface.stream(&response.writer, .unlimited);

    const json_res = ToolResult{
        .id = parsed_body.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response.written(),
                },
            },
        },
    };
    var res_json_struct_fmt = json.fmt(json_res, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleReadSlice(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;

    const start = parsed_json.params.arguments.start;
    const length = parsed_json.params.arguments.length;

    const f = try dir.openFile(io, filename, .{});
    defer f.close(io);

    const buf = try alloc.alloc(u8, 1024);
    defer alloc.free(buf);

    var reader = f.reader(io, buf);
    if (start) |s| try reader.seekTo(s);

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    _ = try reader.interface.stream(&response.writer, if (length) |len| .limited(len) else .unlimited);

    const json_res = ToolResult{
        .id = parsed_body.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response.written(),
                },
            },
        },
    };
    var res_json_struct_fmt = json.fmt(json_res, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleDateTime(w: *Writer, alloc: Allocator, io: Io, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    const now = std.Io.Clock.real.now(io);
    const ts = now.toSeconds();
    const es = epoch.EpochSeconds{ .secs = @intCast(ts) };
    const ed = es.getEpochDay();
    const yd = ed.calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();

    try response.writer.print("{d:02} {s} {d} - {d:02}:{d:02}:{d:02}", .{
        md.day_index,
        @tagName(md.month),
        yd.year,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
    });

    const json_res = ToolResult{
        .id = parsed_body.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response.written(),
                },
            },
        },
    };

    var res_json_struct_fmt = json.fmt(json_res, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleWebRequest(w: *Writer, alloc: Allocator, io: Io, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const url = parsed_json.params.arguments.url orelse return error.MissingUrl;
    var client = std.http.Client{
        .allocator = alloc,
        .io = io,
    };
    defer client.deinit();

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    const res = try client.fetch(.{
        .location = .{
            .url = url,
        },
        .method = .GET,
        .response_writer = &response.writer,
    });

    try response.writer.print("\nSTATUS: {d} {s}", .{ @intFromEnum(res.status), @tagName(res.status) });

    const json_res = ToolResult{
        .id = parsed_body.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response.written(),
                },
            },
        },
    };

    var res_json_struct_fmt = json.fmt(json_res, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleListFiles(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    var walker = try dir.walkSelectively(alloc);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        //Dont even give it a fucking chance
        if (std.mem.eql(u8, entry.basename, ".git")) continue;
        try response.writer.print("{s}\n", .{entry.basename});
    }

    if (response.written().len == 0) {
        try response.writer.print("{{}}", .{});
    }

    const json_res = ToolResult{
        .id = parsed_body.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response.written(),
                },
            },
        },
    };

    var res_json_struct_fmt = json.fmt(json_res, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleErrorResponse(w: *Writer, e: anyerror, id: usize, alloc: Allocator) !void {
    var error_response = Io.Writer.Allocating.init(alloc);
    defer error_response.deinit();

    try error_response.writer.print("ERROR: {s}", .{@errorName(e)});

    const response_json = ToolResult{
        .id = id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = error_response.written(),
                },
            },
            .isError = true,
        },
    };
    var res_json_struct_fmt = json.fmt(response_json, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleCommand(cmd: []const []const u8, w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    _ = dir;
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const arguments = parsed_json.params.arguments.arguments orelse error.NoArgumentsGiven;

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    const concat_args = try std.mem.concat(alloc, []const u8, &.{
        cmd,
        try arguments,
    });
    defer alloc.free(concat_args);

    try runCommand(alloc, io, &response.writer, concat_args);

    const json_res = ToolResult{
        .id = parsed_body.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = response.written(),
                },
            },
        },
    };

    var res_json_struct_fmt = json.fmt(json_res, OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn runCommand(alloc: Allocator, io: Io, w: *Io.Writer, argv: []const []const u8) !void {
    const result = try std.process.run(alloc, io, .{
        .argv = argv,
        .cwd = .{ .path = "storage" },
    });
    defer alloc.free(result.stderr);
    defer alloc.free(result.stdout);

    try w.writeAll(result.stderr);
    try w.writeAll(result.stdout);

    if (result.stderr.len == 0 and result.stdout.len == 0) {
        try w.print("Exited: {d}\n", .{result.term.exited});
    }
}
