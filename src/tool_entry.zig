name: []const u8,
title: []const u8,
description: []const u8,
inputSchema: struct {
    type: []const u8 = "object",
    required: []const []const u8,
    properties: struct {
        operation: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "Math operation. Must be exactly one of: add, subtract, multiply, divide, sqrt",
        } = null,
        a: ?struct {
            type: []const u8 = "number",
            description: []const u8 = "First number for the math operation",
        } = null,
        b: ?struct {
            type: []const u8 = "number",
            description: []const u8 = "Second number for the math operation (not needed for sqrt)",
        } = null,
        start: ?struct {
            type: []const u8 = "number",
            description: []const u8 = "Starting position in the file (0 = beginning). Use this or length to read part of a file",
        } = null,
        end: ?struct {
            type: []const u8 = "number",
            description: []const u8 = "Ending position in the file (0-based). Leave empty to read until the end",
        } = null,
        length: ?struct {
            type: []const u8 = "number",
            description: []const u8 = "How many characters to read starting from 'start'. Alternative to 'end'",
        } = null,
        filename: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "Exact name of the file (with extension if it has one)",
        } = null,
        content: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "Full text to write into the file. This replaces everything in the file",
        } = null,
        keyword: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "Word or short phrase to save or look up in memory",
        } = null,
        substring: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "Exact text to search for inside the file",
        } = null,
        url: ?struct {
            type: []const u8 = "string",
            description: []const u8 = "Full web address starting with http:// or https://",
        } = null,
        arguments: ?struct {
            type: []const u8 = "array",
            items: struct {
                type: []const u8 = "string",
            } = .{},
            description: []const u8 = "List of string values to pass as command arguments",
        } = null,
    },
},
