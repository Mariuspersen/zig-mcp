const Config = @import("config");
const JSONRPC = Config.JSONRPC;

method: []const u8,
params: struct {
    name: []const u8,
    arguments: struct {
        operation: ?[]const u8 = null,
        a: ?f64 = null,
        b: ?f64 = null,
        filename: ?[]const u8 = null,
        directory_name: ?[]const u8 = null,
        keyword: ?[]const u8 = null,
        content: ?[]const u8 = null,
        start: ?usize = null,
        length: ?usize = null,
        url: ?[]const u8 = null,
        arguments: ?[]const []const u8 = null,
        prompt: ?[]const u8 = null,
        temperature: ?f64 = null,
        max_tokens: ?u32 = null,
        query: ?[]const u8 = null,
    },
},
jsonrpc: []const u8 = JSONRPC,
id: usize,
