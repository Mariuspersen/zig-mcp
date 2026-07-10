const Config = @import("config");
const JSONRPC = Config.JSONRPC;

jsonrpc: []const u8 = JSONRPC,
id: usize,
@"error": struct {
    code: i32,
    message: []const u8,
},