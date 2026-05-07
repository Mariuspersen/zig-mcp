const Config = @import("config");
const JSONRPC = Config.JSONRPC;

const ToolEntry = @import("tool_entry.zig");

jsonrpc: []const u8 = JSONRPC,
id: usize,
result: struct {
    tools: []const ToolEntry,
},
