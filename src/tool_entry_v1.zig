type: []const u8 = "function",
function: struct {
    name: []const u8,
    description: []const u8,
    parameters: struct {
        type: []const u8 = "object",
        properties: V1Properties,
        required: []const []const u8,
    },
},

pub const V1Properties = struct {
    operation: ?Operation = null,
    a: ?A = null,
    b: ?B = null,
    filename: ?Filename = null,
    directory_name: ?DirectoryName = null,
    content: ?Content = null,
    start: ?Start = null,
    end: ?End = null,
    keyword: ?Keyword = null,
    url: ?URL = null,
    arguments: ?Arguments = null,
    prompt: ?Prompt = null,
    query: ?Query = null,
    temperature: ?Temperature = null,
    max_tokens: ?MaxTokens = null,
};

pub const Operation = struct {
    type: []const u8 = "string",
    description: []const u8 = "Math operation. Must be exactly one of: add, subtract, multiply, divide, sqrt",
};
pub const A = struct {
    type: []const u8 = "number",
    description: []const u8 = "First number for the math operation",
};
pub const B = struct {
    type: []const u8 = "number",
    description: []const u8 = "Second number for the math operation (not needed for sqrt)",
};
pub const Filename = struct {
    type: []const u8 = "string",
    description: []const u8 = "Exact name of the file (with extension if it has one)",
};
pub const DirectoryName = struct {
    type: []const u8 = "string",
    description: []const u8 = "Exact name of the directory",
};
pub const Content = struct {
    type: []const u8 = "string",
    description: []const u8 = "Full text to write into the file. This replaces everything in the file",
};
pub const Start = struct {
    type: []const u8 = "number",
    description: []const u8 = "Starting position in the file (0 = beginning)",
};
pub const End = struct {
    type: []const u8 = "number",
    description: []const u8 = "Ending position in the file (0-based)",
};
pub const Keyword = struct {
    type: []const u8 = "string",
    description: []const u8 = "Word or short phrase to save or look up in memory",
};
pub const URL = struct {
    type: []const u8 = "string",
    description: []const u8 = "Full web address starting with http:// or https://",
};
pub const Arguments = struct {
    type: []const u8 = "array",
    items: struct {
        type: []const u8 = "string",
    } = .{},
    description: []const u8 = "List of string values to pass as command arguments",
};
pub const Prompt = struct {
    type: []const u8 = "string",
    description: []const u8 = "The complete prompt or question to send to the other LLM",
};
pub const Query = struct {
    type: []const u8 = "string",
    description: []const u8 = "What to search for",
};
pub const Temperature = struct {
    type: []const u8 = "number",
    description: []const u8 = "Optional. Controls randomness/creativity. 0.0 = deterministic, 1.0 = balanced, >1.0 = more creative. Usually defaults to ~0.7.",
    minimum: i32 = 0,
    maximum: i32 = 2,
};
pub const MaxTokens = struct {
    type: []const u8 = "integer",
    description: []const u8 = "Optional. Maximum number of tokens the other LLM is allowed to generate.",
};
