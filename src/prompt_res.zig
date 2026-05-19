const Message = @import("message.zig");
const Choice = struct {
    index: ?usize,
    message: ?Message,
    finish_reason: ?[]const u8,
};
const Usage = struct {
    prompt_tokens: ?usize,
    completion_tokens: ?usize,
    total_tokens: ?usize,
};

id: ?[]const u8,
object: ?[]const u8,
created: ?usize,
model: ?[]const u8,
choices: ?[]Choice,
usage: ?Usage,