const Tools = @import("tools.zig");

name: []const u8,
title: []const u8,
description: []const u8,
inputSchema: struct {
    type: []const u8 = "object",
    required: []const []const u8,
    properties: Tools.PropertySet,
},
