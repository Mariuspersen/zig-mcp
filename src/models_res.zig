const Model = struct {
    id: []const u8,
    status: Status,
};

const Status = struct {
    value: []const u8
};

data: []Model