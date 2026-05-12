name: []const u8,
title: []const u8,
description: []const u8,
inputSchema: struct {
    type: []const u8 = "object",
    required: []const []const u8,
    properties: struct {
        operation: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "add, subtract, multiply, divide, sqrt",
        } = null,
        a: ?struct {
            type: []const u8 = "number",
            description: []const u8 = "First number",
        } = null,
        b: ?struct {
            type: []const u8 = "number",
            description: []const u8 = "Second number",
        } = null,
        start: ?struct {
            type: []const u8 = "number",
            description: []const u8 = "Start index from where to read the file",
        } = null,
        end: ?struct {
            type: []const u8 = "number",
            description: []const u8 = "End index from where to read the file",
        } = null,
        length: ?struct {
            type: []const u8 = "number",
            description: []const u8 = "How many characters from start to read",
        } = null,
        filename: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "Name of the file",
        } = null,
        content: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "Content to be put in file",
        } = null,
        keyword: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "Keyword used in recalling and remembering",
        } = null,
        substring: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "Substring to find in file",
        } = null,
        url: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "URL to use",
        } = null,
        arguments: ?struct {
            type: []const u8 = "array",
            items: struct {
                type: []const u8 = "string",
            } = .{},
            description: []const u8 = "Arguments to use",
        } = null,
    },
},
