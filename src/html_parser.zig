const std = @import("std");
const Io = std.Io;

pub fn getText(input: *Io.Reader, output: *Io.Writer) !void {
    while (true) {
        _ = input.discardDelimiterInclusive('<') catch break;
        const tag = input.takeDelimiterInclusive('>') catch break;
        if (std.mem.startsWith(u8, tag, "script") or
            std.mem.startsWith(u8, tag, "style"))
        {
            while (true) {
                _ = input.discardDelimiterInclusive('<') catch break;
                const end = input.takeDelimiterInclusive('>') catch break;
                if (std.mem.startsWith(u8, end, "/script") or
                    std.mem.startsWith(u8, tag, "style"))
                {
                    break;
                }
            }
        }
        try output.writeByte('\n');
        _ = input.streamDelimiter(output, '<') catch break;
    }
}
