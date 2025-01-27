const std = @import("std");
const rand = std.crypto.random;

pub const SlotMachine = struct {
    rolled: [3]u5,

    pub fn playRound(self: *SlotMachine, bet: u64) u64 {
        var i: usize = 0;
        var mult: u64 = undefined;

        while (i < 3) : (i += 1) {
            self.rolled[i] = rand.intRangeAtMost(u5, 0, 12);
        }

        const roll0: u64 = @intCast(self.rolled[0]);
        const roll1: u64 = @intCast(self.rolled[1]);
        const roll2: u64 = @intCast(self.rolled[2]);

        if (roll0 == roll1 and roll0 == roll2) {
            mult = 500 + roll0 * 3 * 30;
        } else if (roll0 == roll1) {
            mult = 100 + roll0 * 2 * 15 + roll2;
        } else if (roll0 == roll2) {
            mult = 100 + roll0 * 2 * 15 + roll1;
        } else if (roll1 == roll2) {
            mult = 100 + roll1 * 2 * 15 + roll0;
        } else {
            mult = 15 + roll0 + roll1 + roll2;
        }

        return bet * mult / 100;
    }
};
