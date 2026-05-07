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

const PROTOCOL_VERSION = "2025-06-18";
const JSONRPC = "2.0";
const OPTIONS = json.Stringify.Options{
    .emit_nonportable_numbers_as_strings = true,
    .emit_null_optional_fields = false,
    .escape_unicode = true,
    .whitespace = .minified,
    .emit_strings_as_arrays = false,
};

const MethodJson = struct {
    method: []const u8,
};

const ToolNameReq = struct {
    method: []const u8,
    params: struct {
        name: []const u8,
    },
    jsonrpc: []const u8 = JSONRPC,
    id: usize,
};

const InitResStruct = struct {
    jsonrpc: []const u8 = JSONRPC,
    id: usize,
    result: struct {
        protocolVersion: []const u8 = PROTOCOL_VERSION,
        capabilities: struct {
            tools: struct {} = .{},
        },
        serverInfo: struct {
            name: []const u8 = @tagName(Config.name),
            version: []const u8 = Config.version,
        },
    },
};

const InitReqStruct = struct {
    method: []const u8,
    params: struct {
        protocolVersion: []const u8,
        capabilities: struct {
            tools: struct {
                listChanged: bool,
            },
        },
        clientInfo: struct {
            name: []const u8,
            version: []const u8,
        },
    },
    jsonrpc: []const u8 = JSONRPC,
    id: usize,
};

const Tools = struct {
    method: []const u8,
    jsonrpc: []const u8 = JSONRPC,
    id: usize,
};

const ToolEntry = struct {
    name: []const u8,
    title: []const u8,
    description: []const u8,
    inputSchema: struct {
        type: []const u8 = "object",
        required: []const []const u8,
        properties: struct {
            operation: ?struct {
                type: []const u8 = "string",
                description: []const u8 = "add, subtract, multiply, divide, sqrt",
            } = null,
            a: ?struct {
                type: []const u8 = "number",
                description: []const u8 = "First number",
            } = null,
            b: ?struct {
                type: []const u8 = "number",
                description: []const u8 = "Second number",
            } = null,
            start: ?struct {
                type: []const u8 = "number",
                description: []const u8 = "Start index from where to read the file",
            } = null,
            length: ?struct {
                type: []const u8 = "number",
                description: []const u8 = "How many characters from start to read",
            } = null,
            filename: ?struct {
                type: []const u8 = "string",
                description: []const u8 = "Name of the file",
            } = null,
            content: ?struct {
                type: []const u8 = "string",
                description: []const u8 = "Content to be put in file",
            } = null,
            substring: ?struct {
                type: []const u8 = "string",
                description: []const u8 = "Substring to find in file",
            } = null,
            url: ?struct {
                type: []const u8 = "string",
                description: []const u8 = "URL to use",
            } = null,
            arguments: ?struct {
                type: []const u8 = "array",
                items: struct {
                    type: []const u8 = "string",
                } = .{},
                description: []const u8 = "Arguments to use",
            } = null,
        },
    },
};

const ToolsRes = struct {
    jsonrpc: []const u8 = JSONRPC,
    id: usize,
    result: struct {
        tools: []const ToolEntry,
    },
};

const ToolsReqJson = struct {
    method: []const u8,
    params: struct {
        name: []const u8,
        arguments: struct {
            operation: ?[]const u8 = null,
            a: ?f64 = null,
            b: ?f64 = null,
            filename: ?[]const u8 = null,
            content: ?[]const u8 = null,
            start: ?usize = null,
            length: ?usize = null,
            url: ?[]const u8 = null,
            arguments: ?[]const []const u8 = null,
        },
    },
    jsonrpc: []const u8 = JSONRPC,
    id: usize,
};

const ContentType = struct {
    type: []const u8,
    text: []const u8,
};

const ToolReturnResponse = struct {
    jsonrpc: []const u8 = JSONRPC,
    id: usize,
    result: struct {
        content: []const ContentType,
        isError: ?bool = null,
    },
};

const ProtocolError = struct {
    jsonrpc: []const u8 = JSONRPC,
    id: usize,
    @"error": struct {
        code: i32,
        message: []const u8,
    },
};

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;

    const dir = Io.Dir.cwd().openDir(io, "storage", .{ .follow_symlinks = false, .iterate = true }) catch blk: {
        try Io.Dir.cwd().createDir(io, "storage", .default_dir);
        break :blk try Io.Dir.cwd().openDir(io, "storage", .{ .follow_symlinks = false, .iterate = true });
    };

    defer dir.close(io);

    const address = try IpAddress.resolve(io, "0.0.0.0", 8000);
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    while (server.accept(io)) |s| {
        handleConnection(alloc, s, io, dir) catch |e| {
            std.debug.print("ERROR: {s}\n", .{@errorName(e)});
        };
    } else |e| {
        std.debug.print("ERROR: {s}", .{@errorName(e)});
    }
}

fn handleConnection(alloc: Allocator, s: net.Stream, io: Io, dir: Io.Dir) !void {
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

    std.debug.print("REQUEST: {s}\n", .{body});
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
            io,
            body,
            dir,
        ),
        else => {
            try req.respond("{}", .{ .status = .not_found });
            return;
        },
    }
    std.debug.print("RESPONSE: {s}\n", .{res_writer.written()});
    try req.respond(res_writer.written(), .{ .status = .ok });
}

fn handleInitialize(w: *Writer, body: []u8, alloc: Allocator) !void {
    const parsedBody = try json.parseFromSlice(InitReqStruct, alloc, body, .{});
    defer parsedBody.deinit();

    const req_json: InitReqStruct = parsedBody.value;

    const init_res_json = InitResStruct{
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
    const parsedBody = try json.parseFromSlice(Tools, alloc, body, .{});
    defer parsedBody.deinit();

    const res_json_struct = ToolsRes{
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
                    .description = "Write text to a file",
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
                    .description = "Append text to a end of a file",
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
                    .name = "file_insert",
                    .description = "Insert text at a index in a file",
                    .title = "File Insert",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{ "filename", "content" },
                        .properties = .{ .filename = .{}, .content = .{}, .start = .{ .description = "Index of where to insert" } },
                    },
                },
                ToolEntry{
                    .name = "file_read",
                    .description = "Read from a file given a filename",
                    .title = "File Read",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{"filename"},
                        .properties = .{
                            .filename = .{},
                            .start = .{},
                            .length = .{},
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
                    .name = "file_search",
                    .description = "Returns a index into a file",
                    .title = "File Search",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{ "filename", "content" },
                        .properties = .{
                            .filename = .{},
                            .content = .{
                                .description = "content to search for",
                            },
                            .start = .{},
                        },
                    },
                },
                ToolEntry{
                    .name = "date_time",
                    .description = "Returns the date and time",
                    .title = "Unix Epoch Timestamp",
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
            },
        },
    };

    var res_json_struct_fmt = json.fmt(res_json_struct, .{
        .emit_null_optional_fields = false,
    });
    try res_json_struct_fmt.format(w);
}

fn handleCallTools(w: *Writer, alloc: Allocator, io: Io, body: []u8, dir: Io.Dir) !void {
    const methodJson = try json.parseFromSlice(ToolNameReq, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    const hash_method = hash(methodJson.value.params.name);
    methodJson.deinit();

    const id = methodJson.value.id;

    const res = switch (hash_method) {
        hash("arithmetic") => handleArithmetic(w, body, alloc),
        hash("file_write") => handleWrite(w, alloc, io, dir, body),
        hash("file_append") => handleAppend(w, alloc, io, dir, body),
        hash("file_insert") => handleInsert(w, alloc, io, dir, body),
        hash("file_read") => handleRead(w, alloc, io, dir, body),
        hash("file_list") => handleListFiles(w, alloc, io, dir, body),
        hash("file_size") => handleFileSize(w, alloc, io, dir, body),
        hash("file_delete") => handleFileDelete(w, alloc, io, dir, body),
        hash("file_search") => handleFileSearch(w, alloc, io, dir, body),
        hash("date_time") => handleDateTime(w, alloc, io, body),
        hash("web_request") => handleWebRequest(w, alloc, io, body),
        hash("gcc") => handleGCC(w, alloc, io, dir, body),
        else => handleErrorResponse(w, error.NoSuchMethod, id, alloc),
    };
    res catch |e| {
        try handleErrorResponse(w, e, id, alloc);
    };
}

fn handleArithmetic(w: *Writer, body: []u8, alloc: Allocator) !void {
    const parsedBody = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsedBody.deinit();

    const parsed_json: ToolsReqJson = parsedBody.value;
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

    const response_json = ToolReturnResponse{
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

fn handleWrite(w: *Writer, alloc: Allocator, io: Io, dir: Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolsReqJson = parsed_body.value;

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

    const json_res = ToolReturnResponse{
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

fn handleAppend(w: *Writer, alloc: Allocator, io: Io, dir: Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolsReqJson = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;
    const content = parsed_json.params.arguments.content orelse return error.MissingContent;

    const f = try dir.openFile(io, filename, .{});
    defer f.close(io);

    try f.writeStreamingAll(io, content);

    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    try response_text.writer.print("{d} characters appended to {s}", .{ content.len, filename });

    const json_res = ToolReturnResponse{
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
    var res_json_struct_fmt = json.fmt(json_res, .{
        .emit_null_optional_fields = false,
    });
    try res_json_struct_fmt.format(w);
}

fn handleInsert(w: *Writer, alloc: Allocator, io: Io, dir: Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolsReqJson = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;
    const content = parsed_json.params.arguments.content orelse return error.MissingContent;
    const start = parsed_json.params.arguments.start orelse return error.MissingStart;

    const f = try dir.openFile(io, filename, .{});
    defer f.close(io);

    try f.writePositionalAll(io, content, start);

    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    try response_text.writer.print("{d} characters written to {s} at index {d}", .{ content.len, filename, start });

    const json_res = ToolReturnResponse{
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

fn handleFileDelete(w: *Writer, alloc: Allocator, io: Io, dir: Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolsReqJson = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;

    try dir.deleteFile(io, filename);

    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    try response_text.writer.print("{s} deleted", .{filename});

    const json_res = ToolReturnResponse{
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

fn handleFileSize(w: *Writer, alloc: Allocator, io: Io, dir: Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolsReqJson = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;

    const f = try dir.openFile(io, filename, .{});
    defer f.close(io);
    const len = try f.length(io);

    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    try response_text.writer.print("{d}", .{len});

    const json_res = ToolReturnResponse{
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

fn handleRead(w: *Writer, alloc: Allocator, io: Io, dir: Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolsReqJson = parsed_body.value;

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

    const json_res = ToolReturnResponse{
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

fn handleFileSearch(w: *Writer, alloc: Allocator, io: Io, dir: Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    const parsed_json: ToolsReqJson = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;
    const substring = parsed_json.params.arguments.content orelse return error.MissingSubstring;
    const start = parsed_json.params.arguments.start orelse 0;

    const f = try dir.openFile(io, filename, .{});
    defer f.close(io);

    const size = try f.length(io);

    const buf = try alloc.alloc(u8, size);
    defer alloc.free(buf);

    var reader = f.reader(io, buf);
    const content = try reader.interface.readAlloc(alloc, size);
    defer alloc.free(content);

    if (std.mem.findPos(u8, content, start, substring)) |idx| {
        try response.writer.print("{d}", .{idx});
    } else {
        try response.writer.print("Could not find \"{s}\" in \"{s}\"", .{ substring, filename });
    }

    const json_res = ToolReturnResponse{
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
    const parsed_body = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
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

    const json_res = ToolReturnResponse{
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
    const parsed_body = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolsReqJson = parsed_body.value;

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

    const json_res = ToolReturnResponse{
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

fn handleListFiles(w: *Writer, alloc: Allocator, io: Io, dir: Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    var walker = try dir.walk(alloc);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        try response.writer.print("{s}\n", .{entry.basename});
    }

    if (response.written().len == 0) {
        try response.writer.print("{{}}", .{});
    }

    const json_res = ToolReturnResponse{
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

    const response_json = ToolReturnResponse{
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

fn handleGCC(w: *Writer, alloc: Allocator, io: Io, dir: Io.Dir, body: []u8) !void {
    _ = dir;
    const parsed_body = try json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_body.deinit();

    const parsed_json: ToolsReqJson = parsed_body.value;

    const arguments = parsed_json.params.arguments.arguments orelse error.NoArgumentsGiven;

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    const concat_args = try std.mem.concat(alloc, []const u8, &.{
        &.{"gcc"},
        try arguments,
    });
    defer alloc.free(concat_args);

    const result = try std.process.run(alloc, io, .{
        .argv = concat_args,
        .cwd = .{ .path = "storage" },
    });

    try response.writer.writeAll(result.stderr);
    try response.writer.writeAll(result.stdout);

    if (response.written().len == 0) {
        try response.writer.print("Exited: {d}\n", .{result.term.exited});
    }

    const json_res = ToolReturnResponse{
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
