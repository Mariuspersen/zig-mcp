type: []const u8 = "function",
function: struct {
    name: []const u8,
    description: []const u8,
    parameters: struct {
        type: []const u8 = "object",
        properties: struct {
            query: struct {
                type: []const u8 = "string",
                description: []const u8 = "The search query to look up",
            },
        },
        required: []const []const u8,
    },
},
