const Message = @import("message.zig");

model: []const u8 = "default",
messages: []const Message,
temperature: f64 = 0.7,
max_tokens: usize = 512*512,