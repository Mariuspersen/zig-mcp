const Tools = @import("tools.zig");

type: []const u8 = "function",
function: struct {
    name: []const u8,
    description: []const u8,
    parameters: struct {
        type: []const u8 = "object",
        properties: Tools.PropertySet,
        required: []const []const u8,
    },
},
