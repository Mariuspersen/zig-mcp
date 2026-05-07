const Config = @import("config");
const JSONRPC = Config.JSONRPC;

const ContentType = @import("content_type.zig");

jsonrpc: []const u8 = JSONRPC,
id: usize,
result: struct {
    content: []const ContentType,
    isError: ?bool = null,
},
