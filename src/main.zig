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

const PROTOCOL_VERSION = "2025-06-18";
const JSONRPC = "2.0";

const MethodJson = struct {
    method: []const u8,
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
        type: []const u8,
        properties: struct {},
    },
};

const ToolsRes = struct {
    jsonrpc: []const u8 = JSONRPC,
    id: usize,
    result: struct {
        tools: [1]ToolEntry,
    },
};

const HelloWorldBodyJson = struct {
    method: []const u8,
    params: struct {
        name: []const u8,
        arguments: struct {},
    },
    jsonrpc: []const u8 = JSONRPC,
    id: usize,
};

const ContentType = struct {
    type: []const u8,
    text: []const u8,
};

const HelloWorldBodyJsonResponse = struct {
    jsonrpc: []const u8 = JSONRPC,
    id: usize,
    result: struct {
        content: [1]ContentType,
    },
};

pub fn main(init: std.process.Init) !void {
    const address = try IpAddress.resolve(init.io, "0.0.0.0", 8000);
    var server = try address.listen(init.io, .{ .reuse_address = true });
    defer server.deinit(init.io);
    while (server.accept(init.io)) |s| {
        defer s.close(init.io);

        const read_buf = try init.gpa.alloc(u8, 1024);
        defer init.gpa.free(read_buf);

        var reader = s.reader(init.io, read_buf);

        const write_buf = try init.gpa.alloc(u8, 1024);
        defer init.gpa.free(write_buf);

        var writer = s.writer(init.io, write_buf);

        var http_server = http.Server.init(&reader.interface, &writer.interface);

        var req = try http_server.receiveHead();

        var it = req.iterateHeaders();
        var len: usize = 0;
        while (it.next()) |header| if (std.mem.eql(u8, "Content-Length", header.name)) {
            len = try std.fmt.parseInt(usize, header.value, 10);
        };

        const tx_buf = try init.gpa.alloc(u8, len);
        defer init.gpa.free(tx_buf);

        var body_reader = req.server.reader.bodyReader(tx_buf, .none, len);
        const body = try body_reader.readAlloc(init.gpa, len);
        defer init.gpa.free(body);
        var res_writer = Io.Writer.Allocating.init(init.gpa);
        defer res_writer.deinit();

        const methodJson = try json.parseFromSlice(MethodJson, init.gpa, body, .{
            .ignore_unknown_fields = true,
        });
        const hash_method = hash(methodJson.value.method);
        methodJson.deinit();

        try switch (hash_method) {
            hash("initialize") => handleInitialize(
                &res_writer.writer,
                body,
                init.gpa,
            ),
            hash("notifications/initialized") => try res_writer.writer.writeAll("{}"),
            hash("tools/list") => handleListTools(
                &res_writer.writer,
                body,
                init.gpa,
            ),
            hash("tools/call") => handleCallTools(
                &res_writer.writer,
                body,
                init.gpa,
            ),
            else => {
                try req.respond("{}", .{ .status = .not_found });
                return;
            }
        };
        try req.respond(res_writer.written(), .{ .status = .ok });
    } else |e| {
        std.debug.print("ERROR: {s}", .{@errorName(e)});
    }
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
            .tools = [1]ToolEntry{
                ToolEntry{
                    .name = "hello_world",
                    .description = "Returns the words Hello World",
                    .title = "Hello World!",
                    .inputSchema = .{
                        .type = "object",
                        .properties = .{},
                    },
                },
            },
        },
    };

    var res_json_struct_fmt = json.fmt(res_json_struct, .{});
    try res_json_struct_fmt.format(w);
}

fn handleCallTools(w: *Writer, body: []u8, alloc: Allocator) !void {
    const parsedBody = try json.parseFromSlice(HelloWorldBodyJson, alloc, body, .{});
    defer parsedBody.deinit();

    const hello_world_json_res = HelloWorldBodyJsonResponse{
        .id = parsedBody.value.id,
        .result = .{
            .content = [1]ContentType{
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
