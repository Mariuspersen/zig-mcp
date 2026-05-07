const Config = @import("config");
const JSONRPC = Config.JSONRPC;

method: []const u8,
jsonrpc: []const u8 = JSONRPC,
id: usize,
