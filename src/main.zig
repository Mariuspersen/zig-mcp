const std = @import("std");
const Config = @import("config");
const http = std.http;
const json = std.json;
const Io = std.Io;
const net = Io.net;
const time = std.time;
const epoch = time.epoch;
const Map = std.process.Environ.Map;

const Writer = Io.Writer;
const Allocator = std.mem.Allocator;

pub const Table = std.StringHashMap(std.ArrayList(u8));

const IpAddress = net.IpAddress;

const hash = std.hash.Crc32.hash;

const PROTOCOL_VERSION = Config.PROTOCOL_VERSION;
const JSONRPC = Config.JSONRPC;

pub const STRINGIFY_OPTIONS = json.Stringify.Options{
    .emit_nonportable_numbers_as_strings = true,
    .emit_null_optional_fields = false,
    .escape_unicode = true,
    .whitespace = .minified,
    .emit_strings_as_arrays = false,
};

pub const JSON_PARSE_OPTS = json.ParseOptions{
    .ignore_unknown_fields = true,
    .duplicate_field_behavior = .use_last,
    .parse_numbers = true,
};

pub const DIR_OPTIONS = Io.Dir.OpenOptions{
    .follow_symlinks = false,
    .iterate = true,
    .access_sub_paths = false,
};

pub const EXTRA_HEADERS: []const http.Header = &.{
    .{
        .name = "Access-Control-Allow-Origin",
        .value = "*",
    },
    .{
        .name = "Access-Control-Allow-Methods",
        .value = "GET, POST, PUT, DELETE, OPTIONS",
    },
    .{
        .name = "Access-Control-Allow-Headers",
        .value = "Content-Type, Authorization, X-Requested-With, mcp-protocol-version",
    },
};

pub const JSON_HEADER: []const http.Header = &.{
    .{
        .name = "Content-Type",
        .value = "application/json",
    },
};

pub const TOOL_LIST = &[_]ToolEntry{
    ToolEntry{
        .name = "arithmetic",
        .description = "Performs basic math. Use operation 'add', 'subtract', 'multiply', 'divide', or 'sqrt'. Provide 'a' and 'b' for two-number operations.",
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
        .description = "Creates a new file or completely replaces an existing file with the given content.",
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
        .description = "Opens a file and adds the content to the very end without removing anything.",
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
        .description = "Overwrites text inside a file starting at a specific position.",
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
        .description = "Reads and returns the entire content of a file.",
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
        .description = "Reads only part of a file between two positions (start and end).",
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
        .description = "Returns a list of all files in the current directory.",
        .title = "File List",
        .inputSchema = .{
            .type = "object",
            .required = &.{},
            .properties = .{},
        },
    },
    ToolEntry{
        .name = "file_size",
        .description = "Returns the size of a file in bytes.",
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
        .description = "Deletes a file or a directory.",
        .title = "File Delete",
        .inputSchema = .{
            .type = "object",
            .required = &.{},
            .properties = .{ .filename = .{}, .directory_name = .{} },
        },
    },
    ToolEntry{
        .name = "change_directory",
        .description = "Changes the current working directory to the given folder. Creates the folder if it does not exist.",
        .title = "Change Directory",
        .inputSchema = .{
            .type = "object",
            .required = &.{"directory_name"},
            .properties = .{
                .directory_name = .{},
            },
        },
    },
    ToolEntry{
        .name = "current_directory",
        .description = "Returns the full path of the current working directory.",
        .title = "Current Directory",
        .inputSchema = .{
            .type = "object",
            .required = &.{},
            .properties = .{},
        },
    },
    ToolEntry{
        .name = "home_directory",
        .description = "Changes to and returns the user's home directory.",
        .title = "Root Directory",
        .inputSchema = .{
            .type = "object",
            .required = &.{},
            .properties = .{},
        },
    },
    ToolEntry{
        .name = "remember",
        .description = "Stores content in memory using a keyword so it can be recalled later.",
        .title = "Remember",
        .inputSchema = .{
            .type = "object",
            .required = &.{},
            .properties = .{
                .keyword = .{
                    .description = "Keyword to remember by",
                },
                .content = .{
                    .description = "Content to be put into memory",
                },
            },
        },
    },
    ToolEntry{
        .name = "recall",
        .description = "Retrieves content from memory using a keyword.",
        .title = "Recall",
        .inputSchema = .{
            .type = "object",
            .required = &.{},
            .properties = .{
                .keyword = .{ .description = "Keyword to find in memory" },
            },
        },
    },
    ToolEntry{
        .name = "date_time",
        .description = "Returns the current date and time.",
        .title = "Date and Time",
        .inputSchema = .{
            .type = "object",
            .required = &.{},
            .properties = .{},
        },
    },
    ToolEntry{
        .name = "web_request",
        .description = "Fetches the content from any URL and returns just the text.",
        .title = "Web Request",
        .inputSchema = .{
            .required = &.{"url"},
            .properties = .{
                .url = .{},
            },
        },
    },
    ToolEntry{
        .name = "web_search",
        .description = "Search the internet given a search query",
        .title = "Web Request",
        .inputSchema = .{
            .required = &.{"query"},
            .properties = .{ .query = .{} },
        },
    },
    ToolEntry{
        .name = "gcc",
        .description = "Runs the GNU C Compiler (gcc) with the given command-line arguments.",
        .title = "C Compiler",
        .inputSchema = .{
            .required = &.{"arguments"},
            .properties = .{
                .arguments = .{},
            },
        },
    },
    ToolEntry{
        .name = "make",
        .description = "Runs GNU Make to build projects using the given arguments.",
        .title = "Make",
        .inputSchema = .{
            .required = &.{"arguments"},
            .properties = .{
                .arguments = .{},
            },
        },
    },
    ToolEntry{
        .name = "man",
        .description = "Shows the manual page for a command or topic.",
        .title = "Manual Pages",
        .inputSchema = .{
            .required = &.{"arguments"},
            .properties = .{
                .arguments = .{},
            },
        },
    },
    ToolEntry{
        .name = "openscad",
        .description = "Runs OpenSCAD to create or render 3D models from .scad files.",
        .title = "OpenSCAD",
        .inputSchema = .{
            .required = &.{"arguments"},
            .properties = .{
                .arguments = .{},
            },
        },
    },
    ToolEntry{
        .name = "valgrind",
        .description = "Runs Valgrind for memory debugging, leak detection, or profiling.",
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
        .description = "Searches for text inside files using grep with the given arguments.",
        .title = "File Search (grep)",
        .inputSchema = .{
            .required = &.{"arguments"},
            .properties = .{
                .arguments = .{},
            },
        },
    },
    ToolEntry{
        .name = "git",
        .description = "Runs git version control commands with the given arguments.",
        .title = "Git",
        .inputSchema = .{
            .required = &.{"arguments"},
            .properties = .{
                .arguments = .{},
            },
        },
    },
    ToolEntry{
        .name = "ask_other_llm",
        .description =
        \\This tool sends your prompt to another LLM and returns the answer it gives back.
        \\Use this when you want help from a different AI model.
        \\It does not answer the question itself — it asks another AI and brings the answer to you.
        ,
        .title = "Ask Other LLM",
        .inputSchema = .{
            .required = &.{"prompt"},
            .properties = .{
                .prompt = .{},
                .temperature = .{},
                .max_tokens = .{},
            },
        },
    },
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
const PromptReq = @import("prompt_req.zig");
const PromptRes = @import("prompt_res.zig");
const Message = @import("message.zig");
const Models = @import("models_res.zig");
const HTMLParser = @import("html_parser.zig");
const SearchQuery = @import("search_query.zig");
const ToolEntryV1 = @import("tool_entry_v1.zig");

const address = IpAddress.parse(Config.hostname, Config.port) catch |e| {
    @compileError("Unable to resolve IP Address: " ++ e);
};

pub fn main(init: std.process.Init.Minimal) !void {
    const alloc = std.heap.smp_allocator;
    var threaded = Io.Threaded.init(
        alloc,
        .{
            .environ = init.environ,
        },
    );
    var map = try threaded.environ.process_environ.createMap(alloc);
    defer threaded.deinit();

    const io = threaded.io();

    var dir = try rootDir(io);
    defer dir.close(io);

    var table = Table.init(alloc);
    defer {
        var it = table.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            entry.value_ptr.deinit(alloc);
        }
        table.deinit();
    }

    const stdout_buf = try alloc.alloc(u8, 1024);
    defer alloc.free(stdout_buf);

    var stdout_writer = Io.File.stdout().writer(io, stdout_buf);
    const stdout = &stdout_writer.interface;

    try stdout.print("{s} version {s}\n", .{ @tagName(Config.name), Config.version });
    try stdout.flush();

    try stdout.print("Listening on {s}:{d}\n", .{ Config.hostname, Config.port });
    try stdout.flush();

    var serverListen = try io.concurrent(
        handleListen,
        .{ io, alloc, &dir, stdout, &table, &map },
    );
    var quitListen = try io.concurrent(listenStdin, .{ io, &serverListen });
    quitListen.await(io) catch |e| switch (e) {
        Io.Cancelable.Canceled => {
            try stdout.print("Shutting down\n", .{});
            try stdout.flush();
        },
    };
}

fn listenStdin(io: Io, future: *Io.Future(error{Canceled}!void)) Io.Cancelable!void {
    listenStdinImpl(io, future) catch |e| switch (e) {
        Io.Cancelable.Canceled => return Io.Cancelable.Canceled,
        else => {
            errorWriter(io, e);
            return Io.Cancelable.Canceled;
        },
    };
}

fn listenStdinImpl(io: Io, future: *Io.Future(error{Canceled}!void)) !void {
    var f = Io.File.stdin();
    var term = try std.posix.tcgetattr(f.handle);
    term.lflag.ICANON = false;
    term.lflag.ECHO = false;
    try std.posix.tcsetattr(f.handle, .NOW, term);

    defer {
        term.lflag.ICANON = true;
        term.lflag.ECHO = true;
        std.posix.tcsetattr(f.handle, .NOW, term) catch {};
    }

    var buf: [1]u8 = undefined;
    var f_reader = f.reader(io, &buf);
    const stdin = &f_reader.interface;
    while (Io.checkCancel(io)) {
        const input = try stdin.takeByte();
        if (input == 27 or input == 'q') {
            try future.cancel(io);
            return;
        }
    } else |e| return e;
}

fn rootDir(io: Io) !Io.Dir {
    return try Io.Dir.cwd().createDirPathOpen(
        io,
        Config.storage_directory,
        .{ .open_options = DIR_OPTIONS },
    );
}

fn changeDir(dir: *Io.Dir, io: Io, new_dir: []const u8) !Io.Dir {
    return try dir.createDirPathOpen(
        io,
        new_dir,
        .{ .open_options = DIR_OPTIONS },
    );
}

fn errorWriter(io: Io, e: anyerror) void {
    var buf: [64]u8 = undefined;
    var locked_stderr = io.lockStderr(&buf, null) catch return;
    locked_stderr.file_writer.interface.print("ERROR: {s}\n", .{@errorName(e)}) catch return;
}

fn handleListen(io: Io, alloc: Allocator, dir: *Io.Dir, stdout: *Io.Writer, table: *Table, map: *Map) Io.Cancelable!void {
    handleListenImpl(
        io,
        alloc,
        dir,
        stdout,
        table,
        map,
    ) catch |e| switch (e) {
        Io.Cancelable.Canceled => return Io.Cancelable.Canceled,
        else => {
            errorWriter(io, e);
            if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
            return Io.Cancelable.Canceled;
        },
    };
}

fn handleListenImpl(io: Io, alloc: Allocator, dir: *Io.Dir, stdout: *Io.Writer, table: *Table, map: *Map) !void {
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    while (io.checkCancel()) |_| {
        var accept = try io.concurrent(net.Server.accept, .{
            &server,
            io,
        });
        const s = try accept.await(io);
        _ = try io.concurrent(handleConnection, .{
            alloc,
            s,
            io,
            dir,
            stdout,
            table,
            map,
        });
    } else |e| errorWriter(io, e);
}

fn handleConnection(alloc: Allocator, s: net.Stream, io: Io, dir: *Io.Dir, stdout: *Io.Writer, table: *Table, map: *Map) void {
    handleConnectionImpl(
        alloc,
        s,
        io,
        dir,
        stdout,
        table,
        map,
    ) catch |e| {
        errorWriter(io, e);
        if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
    };
}

fn handleConnectionImpl(alloc: Allocator, s: net.Stream, io: Io, dir: *Io.Dir, stdout: *Io.Writer, table: *Table, map: *Map) !void {
    defer s.close(io);
    const read_buf = try alloc.alloc(u8, 1024);
    defer alloc.free(read_buf);

    var reader = s.reader(io, read_buf);

    const write_buf = try alloc.alloc(u8, 1024);
    defer alloc.free(write_buf);

    var writer = s.writer(io, write_buf);

    var http_server = http.Server.init(&reader.interface, &writer.interface);

    var req = try http_server.receiveHead();

    const origin = blk: {
        var head_it = req.iterateHeaders();
        while (head_it.next()) |header| if (std.mem.eql(u8, "Origin", header.name)) {
            break :blk header.value;
        };
        break :blk null;
    };

    const len = req.head.content_length orelse 0;
    if (len == 0) {
        try req.respond("", .{ .extra_headers = EXTRA_HEADERS, .status = .no_content });
        return;
    }

    const tx_buf = try alloc.alloc(u8, len);
    defer alloc.free(tx_buf);

    var body_reader = req.server.reader.bodyReader(tx_buf, .none, len);
    const body = try body_reader.readAlloc(alloc, len);
    defer alloc.free(body);
    var res_writer = Io.Writer.Allocating.init(alloc);
    defer res_writer.deinit();

    const methodJson = try json.parseFromSlice(MethodJson, alloc, body, JSON_PARSE_OPTS);
    const hash_method = hash(methodJson.value.method);
    methodJson.deinit();

    var req_addr = Io.Writer.Allocating.init(alloc);
    defer req_addr.deinit();

    try s.socket.address.format(&req_addr.writer);
    if (std.mem.find(u8, req_addr.written(), ":")) |idx| {
        req_addr.writer.end = idx;
    }
    const orig = origin orelse unreachable;

    if (std.mem.findLast(u8, orig, ":")) |idx| {
        if (std.fmt.parseInt(u16, orig[idx..], 10)) |_| {
            try req_addr.writer.writeAll(orig[idx..]);
        } else |_| {}
    }

    try s.socket.address.format(stdout);
    try stdout.print(" -> REQUEST: {s}\n", .{body});
    try stdout.flush();
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
            body,
            table,
            req_addr.written(),
            map,
        ),
        else => {
            try req.respond(
                "{}",
                .{
                    .status = .not_found,
                    .extra_headers = JSON_HEADER,
                },
            );
            return;
        },
    }
    try stdout.print("RESPONSE: {s}\n", .{res_writer.written()});
    try stdout.flush();
    try req.respond(
        res_writer.written(),
        .{
            .status = .ok,
            .extra_headers = EXTRA_HEADERS ++ JSON_HEADER,
        },
    );
}

fn handleInitialize(w: *Writer, body: []u8, alloc: Allocator) !void {
    const parsedBody = try json.parseFromSlice(InitRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsedBody.deinit();

    const req_json: InitRequest = parsedBody.value;

    const init_res_json = InitResponse{
        .id = req_json.id,
        .result = .{
            .capabilities = .{},
            .serverInfo = .{},
        },
    };
    var res_json_struct_fmt = json.fmt(init_res_json, STRINGIFY_OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleListTools(w: *Writer, body: []u8, alloc: Allocator) !void {
    const parsedBody = try json.parseFromSlice(WhichTool, alloc, body, JSON_PARSE_OPTS);
    defer parsedBody.deinit();

    const res_json_struct = ToolResponse{
        .id = parsedBody.value.id,
        .result = .{
            .tools = TOOL_LIST,
        },
    };

    var res_json_struct_fmt = json.fmt(res_json_struct, STRINGIFY_OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleCallTools(w: *Writer, alloc: Allocator, dir: *Io.Dir, io: Io, body: []u8, table: *Table, origin: ?[]const u8, map: *Map) !void {
    const methodJson = try json.parseFromSlice(ToolNameReq, alloc, body, JSON_PARSE_OPTS);
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
        hash("web_search") => handleWebSearch(w, alloc, io, body),
        hash("gcc") => handleCommand(&.{"gcc"}, w, alloc, io, dir, body, map),
        hash("make") => handleCommand(&.{"make"}, w, alloc, io, dir, body, map),
        hash("man") => handleCommand(&.{"man"}, w, alloc, io, dir, body, map),
        hash("valgrind") => handleCommand(&.{"valgrind"}, w, alloc, io, dir, body, map),
        hash("grep") => handleCommand(&.{"grep"}, w, alloc, io, dir, body, map),
        hash("git") => handleCommand(&.{"git"}, w, alloc, io, dir, body, map),
        hash("openscad") => handleCommand(&.{"openscad"}, w, alloc, io, dir, body, map),
        hash("change_directory") => handleDirectory(.CHANGE, w, alloc, io, dir, body),
        hash("current_directory") => handleDirectory(.CURRENT, w, alloc, io, dir, body),
        hash("home_directory") => handleDirectory(.ROOT, w, alloc, io, dir, body),
        hash("remember") => handleMemory(.REMEMBER, w, alloc, body, table),
        hash("recall") => handleMemory(.RECALL, w, alloc, body, table),
        hash("ask_other_llm") => handlePromptOther(w, alloc, io, body, origin),
        else => handleErrorResponse(w, error.NoSuchMethod, id, alloc),
    };
    res catch |e| {
        if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
        try handleErrorResponse(w, e, id, alloc);
    };
}

fn requestLoadedModel(w: *Writer, alloc: Allocator, io: Io, origin: []const u8) !void {
    var client = std.http.Client{
        .allocator = alloc,
        .io = io,
    };
    defer client.deinit();

    const url = try std.mem.concat(alloc, u8, &.{
        "http://",
        origin,
        "/v1/models",
    });
    defer alloc.free(url);

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    const res = try client.fetch(
        .{
            .location = .{
                .url = url,
            },
            .method = .GET,
            .response_writer = &response.writer,
        },
    );
    _ = res;

    const parsed = json.parseFromSlice(
        Models,
        alloc,
        response.written(),
        JSON_PARSE_OPTS,
    ) catch |e| {
        std.debug.print("{s}\n", .{response.written()});
        return e;
    };
    defer parsed.deinit();

    const models: Models = parsed.value;
    for (models.data) |model| {
        if (std.mem.eql(u8, model.status.value, "loaded")) {
            try w.writeAll(model.id);
            return;
        }
    }
    return error.NoModelsLoaded;
}

fn handlePromptOther(w: *Writer, alloc: Allocator, io: Io, body: []u8, origin: ?[]const u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const llm_server = origin orelse return error.NoOriginInHeader;
    const prompt = parsed_json.params.arguments.prompt orelse return error.MissingPrompt;
    const temp = parsed_json.params.arguments.temperature orelse 0.7;
    const max_tokens = parsed_json.params.arguments.max_tokens orelse 512 * 4;

    const url = try std.mem.concat(alloc, u8, &.{
        "http://",
        llm_server,
        "/v1/chat/completions",
    });
    defer alloc.free(url);

    var model = Io.Writer.Allocating.init(alloc);
    defer model.deinit();

    try requestLoadedModel(&model.writer, alloc, io, llm_server);

    const req_json = PromptReq{
        .messages = &[_]Message{.{
            .role = "user",
            .content = prompt,
        }},
        .max_tokens = max_tokens,
        .temperature = temp,
        .model = model.written(),
    };

    var req_stringify = Io.Writer.Allocating.init(alloc);
    defer req_stringify.deinit();

    var req_json_formatter = json.fmt(req_json, STRINGIFY_OPTIONS);
    try req_json_formatter.format(&req_stringify.writer);

    var client = std.http.Client{
        .allocator = alloc,
        .io = io,
    };
    defer client.deinit();

    var req = try client.request(.POST, try .parse(url), .{});
    defer req.deinit();

    req.extra_headers = JSON_HEADER;

    try req.sendBodyComplete(req_stringify.written());

    const redir_buf = try alloc.alloc(u8, 1024);
    defer alloc.free(redir_buf);
    var res = try req.receiveHead(redir_buf);

    const tx_buf = try alloc.alloc(u8, 1024);
    defer alloc.free(tx_buf);
    const res_reader = res.reader(tx_buf);

    var prompt_response = Io.Writer.Allocating.init(alloc);
    defer prompt_response.deinit();

    _ = try res_reader.stream(&prompt_response.writer, .unlimited);

    const parsed_llm_response = json.parseFromSlice(
        PromptRes,
        alloc,
        prompt_response.written(),
        JSON_PARSE_OPTS,
    ) catch |e| {
        std.debug.print("{s}\n", .{prompt_response.written()});
        return e;
    };
    defer parsed_llm_response.deinit();

    var client_response = Io.Writer.Allocating.init(alloc);
    defer client_response.deinit();

    const llm_response: PromptRes = parsed_llm_response.value;
    if (llm_response.choices) |choices| for (choices) |choice| {
        if (choice.message) |msg| {
            try client_response.writer.writeAll(msg.content);
        }
    };

    if (client_response.written().len == 0) {
        try client_response.writer.writeAll(prompt_response.written());
    }

    try handleTextResponse(parsed_body.value.id, client_response.written(), alloc, w);
}

const MEM_OP = enum {
    RECALL,
    REMEMBER,
};

pub fn handleMemory(op: MEM_OP, w: *Writer, alloc: Allocator, body: []u8, table: *Table) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;
    const keyword = parsed_json.params.arguments.keyword orelse return error.NoKeywordProvided;

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    switch (op) {
        .REMEMBER => {
            const content = parsed_json.params.arguments.content orelse return error.NoKeywordProvided;
            const entry = table.getPtr(keyword) orelse blk: {
                try table.put(
                    try alloc.dupe(u8, keyword),
                    try .initCapacity(alloc, content.len),
                );
                break :blk table.getPtr(keyword) orelse unreachable;
            };
            try entry.appendSlice(alloc, "- ");
            try entry.appendSlice(alloc, content);
            try entry.append(alloc, '\n');
        },
        .RECALL => {
            const entry = table.getPtr(keyword) orelse return error.NoMemoryFound;
            try response.writer.writeAll(entry.items);
        },
    }
    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

const DIR_OP = enum {
    CHANGE,
    ROOT,
    CURRENT,
};

pub fn handleDirectory(op: DIR_OP, w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    switch (op) {
        .CHANGE => {
            const filename = parsed_json.params.arguments.directory_name orelse
                return error.NoDirectoryNameSupplied;

            if (std.fs.path.isAbsolute(filename)) {
                return error.AbsolutePathsNotAllowed;
            } else if (std.mem.find(u8, filename, "..")) |_| {
                var up_dir = try changeDir(dir, io, filename);
                var root_dir = try rootDir(io);

                const up_dir_path = try up_dir.realPathFileAlloc(io, ".", alloc);
                defer alloc.free(up_dir_path);

                const root_dir_path = try root_dir.realPathFileAlloc(io, ".", alloc);
                defer alloc.free(root_dir_path);

                std.debug.print("{s}\n{s}\n", .{
                    up_dir_path,
                    root_dir_path,
                });

                if (root_dir_path.len > up_dir_path.len) {
                    try response.writer.print("Unable to move up any further", .{});
                    up_dir.close(io);
                    root_dir.close(io);
                } else {
                    try response.writer.print("Moved up a directory", .{});
                    dir.* = try changeDir(dir, io, filename);
                }
            } else if (std.mem.find(u8, filename, "~")) |_| {
                dir.* = try rootDir(io);
                try response.writer.print("Changed directory to ~", .{});
            } else {
                dir.* = try changeDir(dir, io, filename);
                try response.writer.print("Changed directory to: {s}", .{filename});
            }
        },
        .CURRENT => {
            const root_dir = try rootDir(io);
            defer root_dir.close(io);

            const root_path = try root_dir.realPathFileAlloc(io, ".", alloc);
            defer alloc.free(root_path);

            const current = try dir.realPathFileAlloc(io, ".", alloc);
            defer alloc.free(current);

            if (std.mem.indexOfDiff(u8, root_path, current)) |idx| {
                try response.writer.writeAll(current[idx..]);
            } else if (std.mem.eql(u8, root_path, current)) {
                try response.writer.writeAll("~");
            } else {
                try response.writer.writeAll(current);
            }
        },
        .ROOT => {
            dir.* = try rootDir(io);
            try response.writer.print("Changed directory to ~", .{});
        },
    }

    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

fn handleArithmetic(w: *Writer, body: []u8, alloc: Allocator) !void {
    const parsedBody = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsedBody.deinit();

    const parsed_json: ToolRequest = parsedBody.value;
    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    const op = parsed_json.params.arguments.operation orelse return error.MissingOperator;

    const hashed_op = hash(op);
    switch (hashed_op) {
        hash("add"), hash("addition"), hash("+") => {
            const a = parsed_json.params.arguments.a orelse return error.MissingArgumentA;
            const b = parsed_json.params.arguments.b orelse return error.MissingArgumentB;
            try response.writer.print("{d}", .{a + b});
        },
        hash("sub"), hash("subtract"), hash("-") => {
            const a = parsed_json.params.arguments.a orelse return error.MissingArgumentA;
            const b = parsed_json.params.arguments.b orelse return error.MissingArgumentB;
            try response.writer.print("{d}", .{a - b});
        },
        hash("div"), hash("divide"), hash("/") => {
            const a = parsed_json.params.arguments.a orelse return error.MissingArgumentA;
            const b = parsed_json.params.arguments.b orelse return error.MissingArgumentB;
            try response.writer.print("{d}", .{a / b});
        },
        hash("mul"), hash("multiply"), hash("*") => {
            const a = parsed_json.params.arguments.a orelse return error.MissingArgumentA;
            const b = parsed_json.params.arguments.b orelse return error.MissingArgumentB;
            try response.writer.print("{d}", .{a * b});
        },
        hash("sqrt") => {
            const a = parsed_json.params.arguments.a orelse return error.MissingArgumentA;
            try response.writer.print("{d}", .{std.math.sqrt(a)});
        },
        else => return error.UnknownOperator,
    }
    try handleTextResponse(parsed_json.id, response.written(), alloc, w);
}

fn handleWrite(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;
    const content = parsed_json.params.arguments.content orelse return error.MissingContent;

    if (std.fs.path.isAbsolute(filename)) {
        return error.AbsolutePathsNotAllowed;
    }

    const f = try dir.createFile(io, filename, .{
        .resolve_beneath = true,
    });
    defer f.close(io);
    try f.writeStreamingAll(io, content);

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    try response.writer.print("{d} characters written to {s}", .{ content.len, filename });

    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

fn handleInsert(w: *Writer, alloc: Allocator, io: Io, append: bool, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;
    const content = parsed_json.params.arguments.content orelse return error.MissingContent;

    if (std.fs.path.isAbsolute(filename)) {
        return error.AbsolutePathsNotAllowed;
    }

    const f = try dir.openFile(io, filename, .{
        .mode = .write_only,
    });
    defer f.close(io);

    const start = try blk: {
        if (append) break :blk f.length(io);
        break :blk parsed_json.params.arguments.start orelse error.MissingStart;
    };
    try f.writePositionalAll(io, content, start);

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    try response.writer.print("{d} characters written to {s} at index {d}", .{ content.len, filename, start });

    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

fn handleFileDelete(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse
        parsed_json.params.arguments.directory_name orelse
        return error.MissingFilename;

    //Sigh
    if (std.fs.path.isAbsolute(filename)) {
        return error.AbsolutePathsNotAllowed;
    }

    //Maybe not try to delete the .git folder you dumbass AI????
    if (std.mem.startsWith(u8, filename, ".git")) return error.PermissionDenied;

    dir.deleteFile(io, filename) catch |e| switch (e) {
        error.IsDir => try dir.deleteTree(io, filename),
        else => return e,
    };

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    try response.writer.print("{s} deleted", .{filename});

    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

fn handleFileSize(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;

    if (std.fs.path.isAbsolute(filename)) {
        return error.AbsolutePathsNotAllowed;
    }

    const f = try dir.openFile(io, filename, .{});
    defer f.close(io);
    const len = try f.length(io);

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    try response.writer.print("{d}", .{len});

    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

fn handleRead(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;

    if (std.fs.path.isAbsolute(filename)) {
        return error.AbsolutePathsNotAllowed;
    }

    const f = try dir.openFile(io, filename, .{});
    defer f.close(io);

    const buf = try alloc.alloc(u8, 1024);
    defer alloc.free(buf);

    var reader = f.reader(io, buf);

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    _ = try reader.interface.stream(&response.writer, .unlimited);

    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

fn handleReadSlice(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const filename = parsed_json.params.arguments.filename orelse return error.MissingFilename;

    if (std.fs.path.isAbsolute(filename)) {
        return error.AbsolutePathsNotAllowed;
    }

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

    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

fn handleDateTime(w: *Writer, alloc: Allocator, io: Io, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
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
    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

fn handleWebRequest(w: *Writer, alloc: Allocator, io: Io, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    const url = parsed_json.params.arguments.url orelse return error.MissingUrl;
    var client = std.http.Client{
        .allocator = alloc,
        .io = io,
    };
    defer client.deinit();

    var website = Io.Writer.Allocating.init(alloc);
    defer website.deinit();

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    const res = try client.fetch(.{
        .location = .{
            .url = url,
        },
        .method = .GET,
        .response_writer = &website.writer,
    });

    var website_reader = Io.Reader.fixed(website.written());
    try HTMLParser.getText(&website_reader, &response.writer);

    if (response.written().len == 0) {
        website_reader.seek = 0;
        _ = try website_reader.stream(&response.writer, .unlimited);
    }

    try response.writer.print("\nSTATUS: {d} {s}", .{ @intFromEnum(res.status), @tagName(res.status) });
    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

const SEARXNG_ENABLED = blk: {
    const T = @TypeOf(Config.searxng_hostname);
    const info = @typeInfo(T);

    switch (info) {
        .pointer => |p| {
            const child_info = @typeInfo(p.child);
            switch (child_info) {
                .array => |arr| {
                    if (arr.child == u8) break :blk true;
                },
                else => {},
            }
        },
        else => {},
    }
    break :blk false;
};

fn handleWebSearch(w: *Writer, alloc: Allocator, io: Io, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    const parsed_json: ToolRequest = parsed_body.value;

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    if (!SEARXNG_ENABLED) {
        try response.writer.writeAll("Searching is not enabled on the MCP Server, tell the user he must enable it first");
        try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
        return;
    }

    const query_raw = parsed_json.params.arguments.query orelse return error.NoQueryProvided;

    var query = Io.Writer.Allocating.init(alloc);
    defer query.deinit();

    for (query_raw) |char| {
        try switch (char) {
            ' ' => query.writer.writeAll("%20"),
            '"' => query.writer.writeAll("%34"),
            '/' => query.writer.writeAll("%47"),
            else => query.writer.writeByte(char),
        };
    }

    const url = try std.mem.concat(alloc, u8, &.{
        Config.searxng_hostname,
        "/search?q=",
        query.written(),
        "&format=json",
    });
    defer alloc.free(url);

    var client = std.http.Client{
        .allocator = alloc,
        .io = io,
    };
    defer client.deinit();

    var query_response = Io.Writer.Allocating.init(alloc);
    defer query_response.deinit();

    const res = try client.fetch(.{
        .location = .{
            .url = url,
        },
        .method = .GET,
        .response_writer = &query_response.writer,
    });

    const query_result = json.parseFromSlice(
        SearchQuery,
        alloc,
        query_response.written(),
        JSON_PARSE_OPTS,
    ) catch |e| {
        std.debug.print("{s}\n", .{query_response.written()});
        return e;
    };
    defer query_result.deinit();

    const parsed_query: SearchQuery = query_result.value;

    if (parsed_query.results.len > 0) {
        try response.writer.writeAll("Results:\n");
    }
    for (parsed_query.results, 1..) |result, i| {
        try response.writer.print(
            "[{d}] - {s}\n{s}\n{s}\n",
            .{ i, result.title, result.url, result.content },
        );
    }
    if (parsed_query.answers.len > 0) {
        try response.writer.writeAll("Answers:\n");
    }
    for (parsed_query.answers, 1..) |answer, i| {
        try response.writer.print(
            "[{d}] - {s}\nURL: {s}\n",
            .{ i, answer.answer, answer.url },
        );
    }
    if (parsed_query.infoboxes.len > 0) {
        try response.writer.writeAll("Info Boxes:\n");
    }
    for (parsed_query.infoboxes, 1..) |infobox, i| {
        try response.writer.print(
            "[{d}] - {s}\n{s}\n{s}\n",
            .{ i, infobox.infobox, infobox.id, infobox.content },
        );
        if (infobox.attributes.len > 0) {
            try response.writer.writeAll("Attributes:\n");
        }
        for (infobox.attributes) |attribute| {
            try response.writer.print("{s}\n{s}\n", .{ attribute.label, attribute.value });
        }
        if (infobox.urls.len > 0) {
            try response.writer.writeAll("URL's:\n");
        }
        for (infobox.urls) |info_url| {
            try response.writer.print("{s}\n{s}\n", .{ info_url.title, info_url.url });
            if (info_url.official) |is_official| {
                try response.writer.print("Official: {any}\n", .{is_official});
            }
        }
    }

    try response.writer.print("\nSTATUS: {d} {s}", .{ @intFromEnum(res.status), @tagName(res.status) });
    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

fn handleListFiles(w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
    defer parsed_body.deinit();

    var response = Io.Writer.Allocating.init(alloc);
    defer response.deinit();

    var walker = try dir.walkSelectively(alloc);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        //Dont even give it a fucking chance
        if (std.mem.eql(u8, entry.basename, ".git")) continue;
        try response.writer.print("{s} -> {s}\n", .{ @tagName(entry.kind), entry.basename });
    }

    if (response.written().len == 0) {
        try response.writer.print("{{}}", .{});
    }
    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
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
    var res_json_struct_fmt = json.fmt(response_json, STRINGIFY_OPTIONS);
    try res_json_struct_fmt.format(w);
}

fn handleCommand(cmd: []const []const u8, w: *Writer, alloc: Allocator, io: Io, dir: *Io.Dir, body: []u8, map: *Map) !void {
    const parsed_body = try json.parseFromSlice(ToolRequest, alloc, body, JSON_PARSE_OPTS);
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

    try runCommand(alloc, io, dir, &response.writer, concat_args, map);
    try handleTextResponse(parsed_body.value.id, response.written(), alloc, w);
}

fn runCommand(alloc: Allocator, io: Io, dir: *Io.Dir, w: *Io.Writer, argv: []const []const u8, map: *Map) !void {
    const path = try dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(path);

    const result = try std.process.run(alloc, io, .{
        .argv = argv,
        .cwd = .{ .path = path },
        .environ_map = map,
    });
    defer alloc.free(result.stderr);
    defer alloc.free(result.stdout);

    try w.writeAll(result.stderr);
    try w.writeAll(result.stdout);

    if (result.stderr.len == 0 and result.stdout.len == 0) {
        try w.print("Exited: {d}\n", .{result.term.exited});
    }
}

fn handleTextResponse(id: usize, text: []u8, alloc: Allocator, w: *Io.Writer) !void {
    const valid = std.unicode.utf8ValidateSlice(text);
    var fixed = Io.Writer.Allocating.init(alloc);
    defer fixed.deinit();

    if (!valid) {
        var alt = std.unicode.fmtUtf8(text);
        try alt.format(&fixed.writer);
    }

    const json_res = ToolResult{
        .id = id,
        .result = .{
            .content = &[_]ContentType{
                .{
                    .type = "text",
                    .text = if (valid) text else fixed.written(),
                },
            },
        },
    };

    var res_json_struct_fmt = json.fmt(json_res, STRINGIFY_OPTIONS);
    try res_json_struct_fmt.format(w);
}
