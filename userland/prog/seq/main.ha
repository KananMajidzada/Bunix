use lib;
use rt;

// Prints a run of numbers. "seq 5" is 1 to 5, "seq 2 8" is 2 to 8, and
// "seq 2 10 3" steps by three.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	let nums: [3]u64 = [0, 0, 0];
	let count = 0z;
	for (let i = 0z; i < n; i += 1) {
		if (count >= 3) {
			break;
		};
		let v: u64 = 0;
		if (lib::number(words[i], &v) == 0) {
			rt::println("usage: seq [first [last [step]]]");
			return;
		};
		nums[count] = v;
		count += 1;
	};
	if (count == 0) {
		rt::println("usage: seq [first [last [step]]]");
		return;
	};
	let first: u64 = 1;
	let last: u64 = 0;
	let step: u64 = 1;
	if (count == 1) {
		last = nums[0];
	} else {
		first = nums[0];
		last = nums[1];
		if (count == 3) {
			step = nums[2];
		};
	};
	if (step == 0) {
		rt::println("seq: the step cannot be zero");
		return;
	};
	let v = first;
	for (true) {
		if (step == 1) {
			if (v > last) {
				break;
			};
		} else if (v >= last) {
			break;
		};
		rt::printnum(v);
		rt::println("");
		v += step;
	};
};
