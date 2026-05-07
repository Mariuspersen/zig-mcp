const Config = @import("config");
const JSONRPC = Config.JSONRPC;
const PROTOCOL_VERSION = Config.PROTOCOL_VERSION;
method: []const u8,
params: struct {
    protocolVersion: []const u8 = PROTOCOL_VERSION,
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
