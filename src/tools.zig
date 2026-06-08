const Config = @import("config");

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
    items: struct { type: []const u8 = "string" } = .{},
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

pub const PropertySet = struct {
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

pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    required: []const []const u8,
    properties: PropertySet,
    enabled: bool,
};

pub const all_tools = [_]Tool{
    .{
        .name = "arithmetic",
        .description = "Performs basic math. Use operation 'add', 'subtract', 'multiply', 'divide', or 'sqrt'. Provide 'a' and 'b' for two-number operations.",
        .required = &.{"operation"},
        .properties = .{
            .operation = .{},
            .a = .{},
            .b = .{},
        },
        .enabled = Config.enable_tool.math,
    },
    .{
        .name = "file_write",
        .description = "Creates a new file or completely replaces an existing file with the given content.",
        .required = &.{ "filename", "content" },
        .properties = .{
            .filename = .{},
            .content = .{},
        },
        .enabled = Config.enable_tool.file_write,
    },
    .{
        .name = "file_append",
        .description = "Opens a file and adds the content to the very end without removing anything.",
        .required = &.{ "filename", "content" },
        .properties = .{
            .filename = .{},
            .content = .{},
        },
        .enabled = Config.enable_tool.file_write,
    },
    .{
        .name = "file_overwrite",
        .description = "Overwrites text inside a file starting at a specific position.",
        .required = &.{ "filename", "content", "start" },
        .properties = .{
            .filename = .{},
            .content = .{},
            .start = .{},
        },
        .enabled = Config.enable_tool.file_write,
    },
    .{
        .name = "file_read",
        .description = "Reads and returns the entire content of a file.",
        .required = &.{"filename"},
        .properties = .{
            .filename = .{},
        },
        .enabled = Config.enable_tool.file_read,
    },
    .{
        .name = "file_read_slice",
        .description = "Reads only part of a file between two positions (start and end).",
        .required = &.{"filename"},
        .properties = .{
            .filename = .{},
            .start = .{},
            .end = .{},
        },
        .enabled = Config.enable_tool.file_read,
    },
    .{
        .name = "file_list",
        .description = "Returns a list of all files in the current directory.",
        .required = &.{},
        .properties = .{
            .query = .{}
        },
        .enabled = Config.enable_tool.file_read,
    },
    .{
        .name = "file_size",
        .description = "Returns the size of a file in bytes.",
        .required = &.{},
        .properties = .{
            .filename = .{},
        },
        .enabled = Config.enable_tool.file_read,
    },
    .{
        .name = "file_delete",
        .description = "Deletes a file or a directory.",
        .required = &.{},
        .properties = .{
            .filename = .{},
            .directory_name = .{},
        },
        .enabled = Config.enable_tool.file_write,
    },
    .{
        .name = "change_directory",
        .description = "Changes the current working directory to the given folder. Creates the folder if it does not exist.",
        .required = &.{"directory_name"},
        .properties = .{
            .directory_name = .{},
        },
        .enabled = Config.enable_tool.directory,
    },
    .{
        .name = "current_directory",
        .description = "Returns the full path of the current working directory.",
        .required = &.{},
        .properties = .{},
        .enabled = Config.enable_tool.directory,
    },
    .{
        .name = "home_directory",
        .description = "Changes to and returns the user's home directory.",
        .required = &.{},
        .properties = .{},
        .enabled = Config.enable_tool.directory,
    },
    .{
        .name = "remember",
        .description = "Stores content in memory using a keyword so it can be recalled later.",
        .required = &.{},
        .properties = .{
            .keyword = .{},
            .content = .{},
        },
        .enabled = Config.enable_tool.memory,
    },
    .{
        .name = "recall",
        .description = "Retrieves content from memory using a keyword.",
        .required = &.{},
        .properties = .{
            .keyword = .{},
        },
        .enabled = Config.enable_tool.memory,
    },
    .{
        .name = "date_time",
        .description = "Returns the current date and time.",
        .required = &.{},
        .properties = .{},
        .enabled = Config.enable_tool.system,
    },
    .{
        .name = "web_request",
        .description = "Fetches the content from any URL and returns just the text.",
        .required = &.{"url"},
        .properties = .{
            .url = .{},
        },
        .enabled = Config.enable_tool.web,
    },
    .{
        .name = "web_search",
        .description = "Search the internet given a search query",
        .required = &.{"query"},
        .properties = .{
            .query = .{},
        },
        .enabled = Config.enable_tool.web,
    },
    .{
        .name = "gcc",
        .description = "Runs the GNU C Compiler (gcc) with the given command-line arguments.",
        .required = &.{"arguments"},
        .properties = .{
            .arguments = .{},
        },
        .enabled = Config.enable_tool.cmd,
    },
    .{
        .name = "make",
        .description = "Runs GNU Make to build projects using the given arguments.",
        .required = &.{"arguments"},
        .properties = .{
            .arguments = .{},
        },
        .enabled = Config.enable_tool.cmd,
    },
    .{
        .name = "man",
        .description = "Shows the manual page for a command or topic.",
        .required = &.{"arguments"},
        .properties = .{
            .arguments = .{},
        },
        .enabled = Config.enable_tool.cmd,
    },
    .{
        .name = "openscad",
        .description = "Runs OpenSCAD to create or render 3D models from .scad files.",
        .required = &.{"arguments"},
        .properties = .{
            .arguments = .{},
        },
        .enabled = Config.enable_tool.cmd,
    },
    .{
        .name = "valgrind",
        .description = "Runs Valgrind for memory debugging, leak detection, or profiling.",
        .required = &.{"arguments"},
        .properties = .{
            .arguments = .{},
        },
        .enabled = Config.enable_tool.cmd,
    },
    .{
        .name = "grep",
        .description = "Searches for text inside files using grep with the given arguments.",
        .required = &.{"arguments"},
        .properties = .{
            .arguments = .{},
        },
        .enabled = Config.enable_tool.cmd,
    },
    .{
        .name = "git",
        .description = "Runs git version control commands with the given arguments.",
        .required = &.{"arguments"},
        .properties = .{
            .arguments = .{},
        },
        .enabled = Config.enable_tool.cmd,
    },
    .{
        .name = "task",
        .description =
        \\Launch a subagent to handle complex, multistep tasks autonomously.
        \\Use this for research, exploration, writing, or any work that spans multiple files or steps.
        ,
        .required = &.{"prompt"},
        .properties = .{
            .prompt = .{},
            .temperature = .{},
            .max_tokens = .{},
        },
        .enabled = Config.enable_tool.ai,
    },
};

pub const TOOL_COUNT = blk: {
    var count: usize = 0;
    for (all_tools) |tool| {
        if (tool.enabled) count += 1;
    }
    break :blk count;
};