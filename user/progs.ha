export type program = struct {
	nam: str,
	off: size,
	bytes: size,
	end: u64,
};

export @symbol("user.blobs") const blobs: u8;

export const programs: [4]program = [
	program { nam = "hello", off = 0, bytes = 8296, end = 0x0000000000403000 },
	program { nam = "wc", off = 8296, bytes = 13280, end = 0x00000000004041a8 },
	program { nam = "grep", off = 21576, bytes = 13248, end = 0x00000000004041d8 },
	program { nam = "cp", off = 34824, bytes = 13280, end = 0x00000000004041a8 },
];
