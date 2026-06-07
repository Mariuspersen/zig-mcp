const Config = @import("config");
const JSONRPC = Config.JSONRPC;

const Args = @import("arguments.zig");

method: []const u8,
params: struct {
    name: []const u8,
    arguments: Args,
},
jsonrpc: []const u8 = JSONRPC,
id: usize,
