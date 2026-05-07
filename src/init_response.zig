const Config = @import("config");
const JSONRPC = Config.JSONRPC;
const PROTOCOL_VERSION = Config.PROTOCOL_VERSION;

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
