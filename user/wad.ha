// Generated from build/doom1.wad. Do not edit.

type wadhdr = struct {
	data: uintptr,
	length: size,
	capacity: size,
};

@symbol("user.wadbytes") const wadbytes: u8;

export fn wad() []u8 = {
	const h = wadhdr {
		data = &wadbytes: uintptr,
		length = 4196020,
		capacity = 4196020,
	};
	return *(&h: *[]u8);
};
