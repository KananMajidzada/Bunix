use console;

export def NAME: str = "Bunix";
export def VERSION: str = "0.1";

export def ART: [11]str = [
	"  __     __",
	" /_/|   |\\_\\",
	"  |U|___|U|",
	"  |       |",
	"  | ,   , |",
	" (  = Y =  )",
	"  |   `   |",
	" /|       |\\",
	" \\| |   | |/",
	"(_|_|___|_|_)",
	"  '\"'   '\"'",
];

export fn banner() void = {
	for (let i = 0z; i < len(ART); i += 1) {
		console::println(ART[i]);
	};
};