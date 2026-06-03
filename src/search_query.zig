query: []const u8,
results: []Result,
answers: []Answer,
corrections: []Correction,
infoboxes: []InfoBox,

const Result = struct {
    url: []const u8,
    title: []const u8,
    content: []const u8,
};
const Answer = struct {
    url: []const u8,
    answer: []const u8,
};
const Correction = struct {};
const InfoBox = struct {
    infobox: []const u8,
    id: []const u8,
    content: []const u8,
    urls: []Url,
    attributes: []Attribute,
};

const Attribute = struct {
    label: []const u8,
    value: []const u8,
};

const Url = struct {
    title: []const u8,
    url: []const u8,
    official: ?bool,
};
