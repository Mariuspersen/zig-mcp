const std = @import("std");
const Config = @import("config");
const http = std.http;
const json = std.json;
const Io = std.Io;
const net = Io.net;

const Writer = Io.Writer;
const Allocator = std.mem.Allocator;

const IpAddress = net.IpAddress;

const hash = std.hash.Crc32.hash;

const DataHashTable = std.StringHashMap(std.ArrayList(u8));

const PROTOCOL_VERSION = "2025-06-18";
const JSONRPC = "2.0";

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
                description: []const u8 = "Name of the file to write to",
            } = null,
            content: ?struct {
                type: []const u8 = "string",
                description: []const u8 = "Content to be put in file",
            } = null,
            substring: ?struct {
                type: []const u8 = "string",
                description: []const u8 = "Substring to find in file",
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
    var dataHashTable = DataHashTable.init(alloc);
    defer {
        var it = dataHashTable.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            entry.value_ptr.deinit(alloc);
        }
        dataHashTable.deinit();
    }

    const address = try IpAddress.resolve(io, "0.0.0.0", 8000);
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    while (server.accept(io)) |s| {
        handleConnection(alloc, s, io, &dataHashTable) catch |e| {
            std.debug.print("ERROR: {s}\n", .{@errorName(e)});
        };
    } else |e| {
        std.debug.print("ERROR: {s}", .{@errorName(e)});
    }
}

fn handleConnection(alloc: Allocator, s: net.Stream, io: Io, table: *DataHashTable) !void {
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
            body,
            table,
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
    var res_json_struct_fmt = json.fmt(init_res_json, .{});
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
                    .name = "hello_world",
                    .description = "Returns the words Hello World",
                    .title = "Hello World!",
                    .inputSchema = .{
                        .required = &.{},
                        .type = "object",
                        .properties = .{},
                    },
                },
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
                    .description =
                    \\Write or append text to a file given a filename.
                    \\Use start to select at which position to start writing.
                    \\If no start present, normal append mode.
                    ,
                    .title = "File Write",
                    .inputSchema = .{
                        .type = "object",
                        .required = &.{ "filename", "content" },
                        .properties = .{ .filename = .{}, .content = .{}, .start = .{ .description = "Start index from where to write" } },
                    },
                },
                ToolEntry{
                    .name = "file_read",
                    .description =
                    \\Read from a file given a filename.
                    \\Use start and end arguments to get a slice.
                    \\Not supplying start will return the entire file.
                    \\Supplying start but no length, will read from start to EOF.
                    ,
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
            },
        },
    };

    var res_json_struct_fmt = json.fmt(res_json_struct, .{
        .emit_null_optional_fields = false,
    });
    try res_json_struct_fmt.format(w);
}

fn handleCallTools(w: *Writer, alloc: Allocator, body: []u8, table: *DataHashTable) !void {
    const methodJson = try json.parseFromSlice(ToolNameReq, alloc, body, .{
        .ignore_unknown_fields = true,
    });
    const hash_method = hash(methodJson.value.params.name);
    methodJson.deinit();

    const id = methodJson.value.id;

    const res = switch (hash_method) {
        hash("hello_world") => handleHelloWorld(w, body, alloc),
        hash("arithmetic") => handleArithmetic(w, body, id, alloc),
        hash("file_write") => handleWrite(w, alloc, body, id, table),
        hash("file_read") => handleRead(w, alloc, body, id, table),
        else => handleErrorResponse(w, error.NoSuchMethod, id, alloc),
    };
    res catch |e| {
        try handleErrorResponse(w, e, id, alloc);
    };
}

fn handleArithmetic(w: *Writer, body: []u8, id: usize, alloc: Allocator) !void {
    const parsedBody = json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    }) catch |e| return try handleErrorResponse(w, e, id, alloc);
    defer parsedBody.deinit();

    const parsed_json: ToolsReqJson = parsedBody.value;

    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    errdefer |e| handleErrorResponse(w, e, id, alloc) catch {};

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

fn handleHelloWorld(w: *Writer, body: []u8, alloc: Allocator) !void {
    const parsedBody = try json.parseFromSlice(ToolsReqJson, alloc, body, .{});
    defer parsedBody.deinit();

    const hello_world_json_res = ToolReturnResponse{
        .id = parsedBody.value.id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = "Hello, world!",
                },
            },
        },
    };
    var res_json_struct_fmt = json.fmt(hello_world_json_res, .{});
    try res_json_struct_fmt.format(w);
}

fn handleWrite(w: *Writer, alloc: Allocator, body: []u8, id: usize, data: *DataHashTable) !void {
    const parsed_body = json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    }) catch |e| return try handleErrorResponse(w, e, id, alloc);
    defer parsed_body.deinit();

    const parsed_json: ToolsReqJson = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;
    const content = parsed_json.params.arguments.content orelse return error.MissingContent;

    try data.put(try alloc.dupe(u8, filename), try .initCapacity(alloc, content.len));
    const arr = data.getPtr(filename) orelse return error.SomethingVeryFuckedUpHappened;
    if (parsed_json.params.arguments.start) |start| {
        if (start > arr.items.len) return error.OutOfBounds;
        try arr.insertSlice(alloc, start, content);
    } else {
        try arr.appendSlice(alloc, content);
    }

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
    var res_json_struct_fmt = json.fmt(json_res, .{
        .emit_null_optional_fields = false,
    });
    try res_json_struct_fmt.format(w);
}

fn handleRead(w: *Writer, alloc: Allocator, body: []u8, id: usize, data: *DataHashTable) !void {
    const parsed_body = json.parseFromSlice(ToolsReqJson, alloc, body, .{
        .ignore_unknown_fields = true,
    }) catch |e| return try handleErrorResponse(w, e, id, alloc);
    defer parsed_body.deinit();

    const parsed_json: ToolsReqJson = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;

    var it = data.iterator();
    while (it.next()) |entry| {
        std.debug.print("\"{s}\" => \"{s}\"\n", .{ entry.key_ptr.*, entry.value_ptr.items });
    }

    const arr = data.get(filename) orelse return error.FileNotFound;

    const start = parsed_json.params.arguments.start;
    const length = parsed_json.params.arguments.length;

    var response_text = Io.Writer.Allocating.init(alloc);
    defer response_text.deinit();

    if (start) |idx| {
        if (idx > arr.items.len) return error.StartOutOfBounds;
        const content = if (length) |len| blk: {
            if (idx + len > arr.items.len) {
                break :blk arr.items[idx..];
            }

            break :blk arr.items[idx..idx + len];
        } else arr.items[idx..];
        try response_text.writer.writeAll(content);
    } else {
        try response_text.writer.writeAll(arr.items);
    }

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

fn handleFind(w: *Writer, body: []u8, alloc: Allocator) !void {
    _ = w;
    _ = body;
    _ = alloc;
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
    var res_json_struct_fmt = json.fmt(response_json, .{});
    try res_json_struct_fmt.format(w);
}
