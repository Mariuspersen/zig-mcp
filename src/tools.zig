const Config = @import("config");

const ItemsType = struct {
    type: []const u8,
};

pub const Property = struct {
    type: []const u8,
    description: []const u8,
    items: ?ItemsType = null,
    minimum: ?i32 = null,
    maximum: ?i32 = null,
};

const Operation = Property{
    .type = "string",
    .description = "Math operation. Must be exactly one of: add, subtract, multiply, divide, sqrt",
};

const A = Property{
    .type = "number",
    .description = "First number for the math operation",
};
const B = Property{
    .type = "number",
    .description = "Second number for the math operation (not needed for sqrt)",
};
const Filename = Property{
    .type = "string",
    .description = "Exact name of the file (with extension if it has one)",
};
const DirectoryName = Property{
    .type = "string",
    .description = "Exact name of the directory",
};
const Content = Property{
    .type = "string",
    .description = "Full text to write into the file. This replaces everything in the file",
};
const Start = Property{
    .type = "number",
    .description = "Starting position in the file (0 = beginning)",
};
const End = Property{
    .type = "number",
    .description = "Ending position in the file (0-based)",
};
const Keyword = Property{
    .type = "string",
    .description = "Word or short phrase to save or look up in memory",
};
const URL = Property{
    .type = "string",
    .description = "Full web address starting with http:// or https://",
};
const Arguments = Property{
    .type = "array",
    .items = .{ .type = "string" },
    .description = "List of string values to pass as command arguments",
};
const Prompt = Property{
    .type = "string",
    .description = "The complete prompt or question to send to the other LLM",
};
const Query = Property{
    .type = "string",
    .description = "What to search for",
};
const Temperature = Property{
    .type = "number",
    .description = "Optional. Controls randomness/creativity. 0.0 = deterministic, 1.0 = balanced, >1.0 = more creative. Usually defaults to ~0.7.",
    .minimum = 0,
    .maximum = 2,
};
const MaxTokens = Property{
    .type = "integer",
    .description = "Optional. Maximum number of tokens the other LLM is allowed to generate.",
};
const Program = Property{
    .type = "string",
    .description = "Exact name of the program to run",
};

const PROGRAM_WHITELIST = blk: {
    var list: []const u8 = "";
    for (Config.cmd_whitelist) |program| {
        list = list ++ " - " ++ program ++ "\n";
    }
    break :blk list;
};

pub const PropertySet = struct {
    operation: ?Property = null,
    a: ?Property = null,
    b: ?Property = null,
    filename: ?Property = null,
    directory_name: ?Property = null,
    content: ?Property = null,
    start: ?Property = null,
    end: ?Property = null,
    keyword: ?Property = null,
    url: ?Property = null,
    arguments: ?Property = null,
    prompt: ?Property = null,
    query: ?Property = null,
    temperature: ?Property = null,
    max_tokens: ?Property = null,
    program: ?Property = null,
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
            .operation = Operation,
            .a = A,
            .b = B,
        },
        .enabled = Config.enable_tool.math,
    },
    .{
        .name = "file_write",
        .description = "Creates a new file or completely replaces an existing file with the given content.",
        .required = &.{ "filename", "content" },
        .properties = .{
            .filename = Filename,
            .content = Content,
        },
        .enabled = Config.enable_tool.file_write,
    },
    .{
        .name = "file_append",
        .description = "Opens a file and adds the content to the very end without removing anything.",
        .required = &.{ "filename", "content" },
        .properties = .{
            .filename = Filename,
            .content = Content,
        },
        .enabled = Config.enable_tool.file_write,
    },
    .{
        .name = "file_overwrite",
        .description = "Overwrites text inside a file starting at a specific position.",
        .required = &.{ "filename", "content", "start" },
        .properties = .{
            .filename = Filename,
            .content = Content,
            .start = Start,
        },
        .enabled = Config.enable_tool.file_write,
    },
    .{
        .name = "file_read",
        .description = "Reads and returns the entire content of a file.",
        .required = &.{"filename"},
        .properties = .{
            .filename = Filename,
        },
        .enabled = Config.enable_tool.file_read,
    },
    .{
        .name = "file_read_slice",
        .description = "Reads only part of a file between two positions (start and end).",
        .required = &.{"filename"},
        .properties = .{
            .filename = Filename,
            .start = Start,
            .end = End,
        },
        .enabled = Config.enable_tool.file_read,
    },
    .{
        .name = "file_list",
        .description = "Returns a list of all files in the current directory.",
        .required = &.{},
        .properties = .{
            .query = Query,
        },
        .enabled = Config.enable_tool.file_read,
    },
    .{
        .name = "file_size",
        .description = "Returns the size of a file in bytes.",
        .required = &.{},
        .properties = .{
            .filename = Filename,
        },
        .enabled = Config.enable_tool.file_read,
    },
    .{
        .name = "file_delete",
        .description = "Deletes a file or a directory.",
        .required = &.{},
        .properties = .{
            .filename = Filename,
            .directory_name = DirectoryName,
        },
        .enabled = Config.enable_tool.file_write,
    },
    .{
        .name = "change_directory",
        .description = "Changes the current working directory to the given folder. Creates the folder if it does not exist.",
        .required = &.{"directory_name"},
        .properties = .{
            .directory_name = DirectoryName,
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
            .keyword = Keyword,
            .content = Content,
        },
        .enabled = Config.enable_tool.memory,
    },
    .{
        .name = "recall",
        .description = "Retrieves content from memory using a keyword.",
        .required = &.{"keyword"},
        .properties = .{
            .keyword = Keyword,
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
            .url = URL,
        },
        .enabled = Config.enable_tool.web,
    },
    .{
        .name = "web_search",
        .description = "Search the internet given a search query",
        .required = &.{"query"},
        .properties = .{
            .query = Query,
        },
        .enabled = Config.enable_tool.web,
    },
    .{
        .name = "cmd",
        .description = "Runs a program with a set of arguments, program must be on this whitelist:\n" ++ PROGRAM_WHITELIST,
        .required = &.{
            "program",
            "arguments",
        },
        .properties = .{
            .program = Program,
            .arguments = Arguments,
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
            .prompt = Prompt,
            .temperature = Temperature,
            .max_tokens = MaxTokens,
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
