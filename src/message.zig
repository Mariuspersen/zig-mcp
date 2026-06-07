const ToolCall = @import("tool_call_v1.zig");

role: []const u8,
content: []const u8,
tool_calls: ?[]const ToolCall = null,
tool_call_id: ?[]const u8 = null,