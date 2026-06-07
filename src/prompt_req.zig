const Message = @import("message.zig");
const ToolEntryV1 = @import("tool_entry_v1.zig");

model: []const u8 = "default",
messages: []const Message,
temperature: f64 = 0.7,
max_tokens: usize = 512*512,
tools: []const ToolEntryV1,
stream: bool = false,