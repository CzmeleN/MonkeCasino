const std = @import("std");
const zap = @import("zap");

// -----------------------------------------------------------------------------
// 1) Table logic
// -----------------------------------------------------------------------------
const table_module = @import("poker/src/game/table.zig");
const player_module = @import("poker/src/game/player.zig");
const Thread = std.Thread;

const rand = std.crypto.random;
const Table = table_module.Table;
const GameInfo = table_module.GameInfo;
const WinInfo = table_module.WinInfo;
const Choice = player_module.Choice;
const ChoiceStruct = player_module.ChoiceStruct;
const PSEnum = player_module.PlayerStatus;

const Args = struct {
    table_ptr: *Table,
    table_id: usize,
};

pub const TableManager = struct {
    tables: [4]Table,
    threads: [4]Thread,

    pub fn init(self: *TableManager) !void {
        const join_cashes = [_]u64{ 100, 1000, 10000, 25000 };
        const small_blinds = [_]u64{ 5, 50, 500, 1000 };
        const bot_names = [_][]const u8{ "bot Michael", "bot Rafael", "bot Monke", "bot Eva" };

        for (&self.tables, 0..) |*table, i| {
            try table.init(join_cashes[i], small_blinds[i]);

            var j: usize = 0;

            while (j < 4) : (j += 1) {
                _ = table.join(bot_names[j], bot_names[j], true);
            }
        }
    }

    pub fn runAllTables(self: *TableManager) !void {
        for (&self.tables, 0..) |*table, i| {
            const args = Args{ .table_ptr = table, .table_id = i };
            const handle = try Thread.spawn(.{}, tableLoop, .{args});

            self.threads[i] = handle;
        }
    }

    pub fn shutAllTables(self: *TableManager) !void {
        for (&self.threads) |*thread| {
            thread.join();
        }
    }

    fn tableLoop(args: Args) !void {
        const table_ptr: *Table = args.table_ptr;
        const table_id: usize = args.table_id;
        _ = table_id;

        while (true) {
            _ = try singleRound(table_ptr);

            // TODO additional logic to add balances to kicked players' cashes;
            table_ptr.kick_left();
            table_ptr.refill_bots();

            // std.debug.print("Table {d} ended round, waiting 5 seconds\n", .{table_id});
            std.time.sleep(2_000_000_000);
        }
    }
};

fn only_check_bot(avail: ChoiceStruct) Choice {
    if (avail.can_check) return Choice.Check;
    return Choice.Fold;
}

fn full_random_bot(avail: ChoiceStruct) Choice {
    const choices = [_]Choice{ Choice.Fold, Choice.AllIn, Choice.Check, Choice.Fold };
    const at_most: usize = if (avail.can_raise) 3 else if (avail.can_check) 2 else 1;

    return choices[rand.intRangeAtMost(usize, 0, at_most)];
}

fn broadcastToAllPlayers(info: GameInfo) void {
    // TODO broadcast to all non-bot playing players
    std.debug.print("Broadcast game state: {any}\n", .{info});
}

fn awaitUserMove(t: *Table, in_board_id: usize, timeout_ns: u64) bool {
    // TODO wait for call withing timeout_ns time;
    _ = t;
    _ = in_board_id;
    _ = timeout_ns;
    return false;
}

fn bettingRound(t: *Table) !void {
    const TIMEOUT_NS = 20_000_000_000;

    while (!t.stakes_matched()) {
        if (t.one_remaining()) {
            return;
        }

        const curr_id = t.curr_player;
        const avail = t.available_moves();

        if (t.players[curr_id].is_bot) {
            const bot_choice = full_random_bot(avail);
            t.play(bot_choice);
        } else {
            const got_user_move = awaitUserMove(t, curr_id, TIMEOUT_NS);

            if (!got_user_move) {
                t.timeout_current();
            }
        }
    }
}

fn singleRound(t: *Table) !WinInfo {
    try t.start_round();

    try bettingRound(t);
    if (t.one_remaining()) {
        return t.end_round();
    }

    try t.draw_three();

    try bettingRound(t);
    if (t.one_remaining()) {
        return t.end_round();
    }

    try t.draw_fourth();

    try bettingRound(t);
    if (t.one_remaining()) {
        return t.end_round();
    }

    try t.draw_fifth();
    try bettingRound(t);

    return t.end_round();
}

// -----------------------------------------------------------------------------
// 2) "Database" calls -> Node server for user data
// -----------------------------------------------------------------------------
const Client = std.http.Client;

pub const BASE_URL = "http://localhost:3000";
pub const USERS_ENDPOINT = "/api/users";
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpa_allocator = gpa.allocator();
const http = std.http;
const Header = std.http.Header;
const FetchOptions = std.http.Client.FetchOptions;
const json = std.json;

pub const UserData = struct {
    name: []const u8,
    balance: u64,
};

const FullResponse = struct {
    success: bool,
    data: UserData,
};

fn addCorsHeaders(req: zap.Request) void {
    _ = req.setHeader("Access-Control-Allow-Origin", "*") catch {};
    _ = req.setHeader("Access-Control-Allow-Methods", "GET, POST, PATCH, OPTIONS") catch {};
    _ = req.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization") catch {};
}

fn charVal(c: u8) u64 {
    switch (c) {
        '1' => return 1,
        '2' => return 2,
        '3' => return 3,
        '4' => return 4,
        '5' => return 5,
        '6' => return 6,
        '7' => return 7,
        '8' => return 8,
        '9' => return 9,
        else => {
            return 0;
        },
    }
}

fn packUserInfo(str: []const u8) UserData {
    const nick: []const u8 = "nick";
    const balance: []const u8 = "accoutBalance";
    var curr: usize = 0;
    var key_start: usize = undefined;
    var name_buf: [64]u8 = undefined;
    var bal_buf: [64]u8 = undefined;
    var nick_len: usize = 0;
    var bal_len: usize = 0;
    var bal: u64 = 0;
    var pow: u64 = 1;

    for (str, 0..) |c, i| {
        if (c == nick[curr]) {
            curr += 1;
            if (curr == 4) {
                key_start = i + 4;
                break;
            }
        } else {
            curr = 0;
        }

        if (i == 64) return UserData{ .balance = 0, .name = "" };
    }

    while (str[key_start] != '"') : (key_start += 1) {
        name_buf[nick_len] = str[key_start];
        nick_len += 1;
    }

    const name: []const u8 = name_buf[0..nick_len];

    curr = 0;

    for (str, 0..) |c, i| {
        if (c == balance[curr]) {
            curr += 1;
            if (curr == 13) {
                key_start = i + 3;
                break;
            }
        } else {
            curr = 0;
        }

        if (i == 64) return UserData{ .balance = 0, .name = "" };
    }

    while (str[key_start] != ',') : (key_start += 1) {
        bal_buf[bal_len] = str[key_start];
        bal_len += 1;
    }

    while (bal_len > 0) : (bal_len -= 1) {
        bal += charVal(bal_buf[bal_len - 1]) * pow;
        pow *= 10;
    }

    return UserData{ .balance = bal, .name = name };
}

fn getUser(user_id: []const u8) !FullResponse {
    var url_buffer: [128]u8 = undefined;
    const url_str = try std.fmt.bufPrint(&url_buffer, "{s}{s}/{s}", .{ BASE_URL, USERS_ENDPOINT, user_id });
    const url = try std.Uri.parse(url_str);

    var client = Client{ .allocator = gpa_allocator };
    defer client.deinit();

    // var auth_header: Header = undefined;
    // if (secret_token.len > 0) {
    //     const auth_value = try std.fmt.allocPrint(gpa_allocator, "Bearer {s}", .{secret_token});
    //     defer gpa_allocator.free(auth_value);
    //     auth_header = Header{ .name = "Authorization", .value = auth_value };
    // }

    // const headers = [_]http.Header{auth_header};
    // _ = headers;

    const buf = try gpa_allocator.alloc(u8, 1024 * 1024 * 4);
    defer gpa_allocator.free(buf);

    var req = try client.open(.GET, url, .{ .server_header_buffer = buf });
    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();

    if (req.response.status != .ok) {
        return FullResponse{ .success = false, .data = undefined };
    }

    var rdr = req.reader();
    const body = try rdr.readAllAlloc(gpa_allocator, 1024 * 1024 * 4);
    defer gpa_allocator.free(body);

    // std.debug.print("body: {s}", .{body});

    if (body[11] == 't') {
        // std.debug.print("EQUAL\n", .{});
        return FullResponse{ .success = true, .data = packUserInfo(body) };
    }

    const full = FullResponse{ .success = false, .data = undefined };
    return full;
}

fn checkHasMoney(user_id: []const u8, required: u64) bool {
    const res = getUser(user_id) catch return false;
    if (!res.success) {
        return false;
    }
    return res.data.balance >= required;
}

fn getNickname(user_id: []const u8) bool {
    const res = getUser(user_id) catch return "unnamed";
    if (res == null) {
        return "unnamed";
    }
    return res.?.data.name;
}

// -----------------------------------------------------------------------------
// 3) Globals
// -----------------------------------------------------------------------------
var gTableManager = TableManager{
    .tables = undefined,
    .threads = undefined,
};

// -----------------------------------------------------------------------------
// 4) HTTP Routing with zap
// -----------------------------------------------------------------------------
const Slots = @import("slots/slots.zig").SlotMachine;

const UpdateBalanceRequest = struct {
    user_id: []const u8,
    amount: i64,
};

fn parseQueryParam(query_str: []const u8, key: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeScalar(u8, query_str, '&');
    while (it.next()) |tok| {
        const maybe_eq_index = std.mem.indexOfScalar(u8, tok, '=');
        if (maybe_eq_index) |eq_i| {
            const found_key = tok[0..eq_i];
            if (std.mem.eql(u8, found_key, key)) {
                return tok[(eq_i + 1)..]; // return substring after '='
            }
        }
    }
    return null;
}

fn handleCheckHasMoney(req: zap.Request) void {
    const query_str = req.query orelse {
        req.setStatus(.bad_request);
        return;
    };
    const user_id_str = parseQueryParam(query_str, "user_id") orelse {
        req.setStatus(.bad_request);
        return;
    };
    const money_str = parseQueryParam(query_str, "money") orelse {
        req.setStatus(.bad_request);
        return;
    };

    const money_val = std.fmt.parseUnsigned(u64, money_str, 10) catch {
        req.setStatus(.bad_request);
        return;
    };

    if (checkHasMoney(user_id_str, money_val)) {
        req.setStatus(.ok);
        req.setHeader("Content-Type", "application/json") catch {};
        req.sendBody("{\"hasMoney\":true}") catch {};
    } else {
        req.setStatus(.ok);
        req.setHeader("Content-Type", "application/json") catch {};
        req.sendBody("{\"hasMoney\":false}") catch {};
    }
}

fn updateUserBalance(user_id: []const u8, amount: i64) !bool {
    const user_response = try getUser(user_id);

    if (!user_response.success) {
        return false;
    }

    const current_balance: u64 = user_response.data.balance;
    const signed_curr: i64 = @intCast(current_balance);
    const new: i64 = signed_curr + amount;

    if (new < 0) {
        return false;
    }

    const new_balance: u64 = @intCast(new);

    var url_buffer: [128]u8 = undefined;

    const url_str = try std.fmt.bufPrint(&url_buffer, "{s}{s}/{s}", .{ BASE_URL, USERS_ENDPOINT, user_id });

    const url = try std.Uri.parse(url_str);

    var client = Client{ .allocator = gpa_allocator };
    defer client.deinit();

    const header_buf = try gpa_allocator.alloc(u8, 4096);
    defer gpa_allocator.free(header_buf);

    var req = try client.open(.PATCH, url, .{ .server_header_buffer = header_buf });
    defer req.deinit();
    std.debug.print("reposnes", .{});

    const update_body = try std.fmt.allocPrint(gpa_allocator, "{{\"balance\":{d}}}", .{new_balance});
    defer gpa_allocator.free(update_body);

    try req.finish();
    try req.wait();

    if (req.response.status != .ok) {
        return false;
    }

    return true;
}

fn handleBalanceChange(req: zap.Request) void {
    // const auth_header = req.getHeader("Authorization") orelse {
    //     req.setStatus(.unauthorized);
    //     req.sendBody("{\"success\":false, \"message\":\"Missing Authorization header\"}") catch {};
    //     return;
    // };

    // if (!std.mem.eql(u8, auth_header, gAuthKey)) {
    //     req.setStatus(.unauthorized);
    //     req.sendBody("{\"success\":false, \"message\":\"Invalid Authorization key\"}") catch {};
    //     return;
    // }

    const body = req.body orelse {
        req.setStatus(.bad_request);
        req.sendBody("{\"success\":false, \"message\":\"Missing request body\"}") catch {};
        return;
    };

    const parsed = std.json.parseFromSlice(UpdateBalanceRequest, gpa_allocator, body, .{}) catch {
        req.setStatus(.bad_request);
        req.sendBody("{\"success\":false, \"message\":\"Invalid JSON format\"}") catch {};
        return;
    };
    // defer gpa_allocator.free(parsed);

    const update_req = parsed.value;

    const update_success = updateUserBalance(update_req.user_id, update_req.amount) catch {
        // std.debug.print("Error updating balance", .{});
        req.setStatus(.internal_server_error);
        req.sendBody("{\"success\":false, \"message\":\"Internal Server Error\"}") catch {};
        return;
    };

    if (update_success) {
        req.setStatus(.ok);
        req.setHeader("Content-Type", "application/json") catch {};
        req.sendBody("{\"success\":true, \"message\":\"Balance updated successfully\"}") catch {};
    } else {
        req.setStatus(.bad_request);
        req.sendBody("{\"success\":false, \"message\":\"Failed to update balance\"}") catch {};
    }
}

fn handlePlaySlots(req: zap.Request) void {
    const query_str = req.query orelse {
        req.setStatus(.bad_request);
        req.sendBody("{\"success\":false, \"message\":\"Missing query parameters\"}") catch {};
        return;
    };

    const user_id_str = parseQueryParam(query_str, "user_id") orelse {
        req.setStatus(.bad_request);
        req.sendBody("{\"success\":false, \"message\":\"Missing 'user_id' parameter\"}") catch {};
        return;
    };

    std.debug.print("\n{s}\n", .{user_id_str});
    const bet_str = parseQueryParam(query_str, "bet") orelse {
        req.setStatus(.bad_request);
        req.sendBody("{\"success\":false, \"message\":\"Missing 'bet' parameter\"}") catch {};
        return;
    };

    const bet = std.fmt.parseUnsigned(u64, bet_str, 10) catch {
        req.setStatus(.bad_request);
        req.sendBody("{\"success\":false, \"message\":\"Invalid 'bet' format\"}") catch {};
        return;
    };

    if (!checkHasMoney(user_id_str, bet)) {
        req.setStatus(.ok);
        req.setHeader("Content-Type", "application/json") catch {};
        req.sendBody("{\"success\":false, \"message\":\"Insufficient funds\"}") catch {};
        return;
    }

    const i_bet: i64 = @intCast(bet);
    _ = i_bet;

    // const subtract_success = updateUserBalance(user_id_str, -i_bet) catch {
    //     req.setStatus(.internal_server_error);
    //     req.sendBody("{\"success\":false, \"message\":\"Failed to update balance\"}") catch {};
    //     return;
    // };

    // if (!subtract_success) {
    //     req.setStatus(.internal_server_error);
    //     req.sendBody("{\"success\":false, \"message\":\"Failed to subtract bet\"}") catch {};
    //     return;
    // }

    var slot_machine = Slots{
        .rolled = [3]u5{ 0, 0, 0 },
    };
    const payout = slot_machine.playRound(bet);
    const i_payout: i64 = @intCast(payout);
    _ = i_payout;

    // const add_success = updateUserBalance(user_id_str, i_payout) catch {
    //     req.setStatus(.internal_server_error);
    //     req.sendBody("{\"success\":false, \"message\":\"Failed to update balance with payout\"}") catch {};
    //     return;
    // };
    //
    // if (!add_success) {
    //     req.setStatus(.internal_server_error);
    //     req.sendBody("{\"success\":false, \"message\":\"Failed to add payout to balance\"}") catch {};
    //     return;
    // }

    // Prepare rolled numbers for the response
    const rolled0 = slot_machine.rolled[0];
    const rolled1 = slot_machine.rolled[1];
    const rolled2 = slot_machine.rolled[2];

    // Format the JSON response
    var response_buffer: [256]u8 = undefined;
    const format_result = std.fmt.bufPrint(&response_buffer, "{{\"success\":true, \"win\":{d}, \"rolled\":[{d},{d},{d}]}}", .{ payout, rolled0, rolled1, rolled2 });

    var end: usize = undefined;
    for (response_buffer, 0..) |c, i| {
        if (c == '}') {
            end = i + 1;
        }
    }

    const body: []const u8 = response_buffer[0..end];

    std.debug.print("{s}", .{body});

    switch (@TypeOf(format_result)) {
        []u8 => {
            req.setStatus(.ok);
            req.sendBody(body) catch {};
        },
        else => {
            req.setStatus(.ok);
            req.sendBody(body) catch {};
        },
    }
}

fn handleJoinPokerTable(req: zap.Request) void {
    // e.g. GET /api/joinPokerTable?table_id=1&user_id=123
    const query_str = req.query orelse {
        req.setStatus(.bad_request);
        return;
    };

    const table_id_str = parseQueryParam(query_str, "table_id") orelse {
        req.setStatus(.bad_request);
        return;
    };
    const user_id_str = parseQueryParam(query_str, "user_id") orelse {
        req.setStatus(.bad_request);
        return;
    };

    const table_id = std.fmt.parseUnsigned(usize, table_id_str, 10) catch {
        req.setStatus(.bad_request);
        return;
    };

    if (table_id >= gTableManager.tables.len) {
        req.setStatus(.bad_request);
        req.sendBody("{\"error\":\"Invalid table_id\"}") catch {};
        return;
    }

    var table_ref = &gTableManager.tables[table_id];

    if (!table_ref.has_empty()) {
        req.setStatus(.bad_request);
        req.sendBody("{\"error\":\"Table full\"}") catch {};
    }

    var name: []const u8 = undefined;
    name = "unnamed";

    _ = getUser(user_id_str) catch {};

    _ = table_ref.join(user_id_str, name, false);

    req.setStatus(.ok);
    req.setHeader("Content-Type", "application/json") catch {};
    req.sendBody("{\"success\":true, \"message\":\"Joined the table\"}") catch {};
}

fn handlePlayPokerTable(req: zap.Request) void {
    // e.g. GET /api/playPokerTable?table_id=1&user_id=123&action=fold
    // In real usage, you might want a POST or a PATCH, but let's do GET for example.
    const query_str = req.query orelse {
        req.setStatus(.bad_request);
        return;
    };

    const table_id_str = parseQueryParam(query_str, "table_id") orelse {
        req.setStatus(.bad_request);
        return;
    };
    const user_id_str = parseQueryParam(query_str, "user_id") orelse {
        req.setStatus(.bad_request);
        return;
    };
    const action_str = parseQueryParam(query_str, "action") orelse {
        req.setStatus(.bad_request);
        return;
    };

    const table_id = std.fmt.parseUnsigned(usize, table_id_str, 10) catch {
        req.setStatus(.bad_request);
        return;
    };

    if (table_id >= gTableManager.tables.len) {
        req.setStatus(.bad_request);
        req.sendBody("{\"error\":\"Invalid table_id\"}") catch {};
        return;
    }

    var table_ref = &gTableManager.tables[table_id];

    // Now we interpret the action:
    var chosen_action: Choice = .Fold;
    if (std.mem.eql(u8, action_str, "fold")) {
        chosen_action = .Fold;
    } else if (std.mem.eql(u8, action_str, "check")) {
        chosen_action = .Check;
    } else if (std.mem.eql(u8, action_str, "raise")) {
        chosen_action = .Raise;
    } else if (std.mem.eql(u8, action_str, "allin")) {
        chosen_action = .AllIn;
    } else {
        req.setStatus(.bad_request);
        req.sendBody("{\"error\":\"Unknown action\"}") catch {};
        return;
    }

    // The Table code uses something like `t.play(chosen_action)`.
    // But we also need to set `t.curr_player` to user_id’s seat if that’s how it’s designed.
    // This depends on how your table code works. Typically, you’d figure out which seat
    // belongs to user_id, then call `table_ref.play(chosen_action)`.
    // For now we do a naive approach:
    // we find the seat index where player_id = user_id
    // var seat_idx: ?usize = null;
    // for (table_ref.players, 0..) |p, idx| {
    //     if (p.id == user_id and !p..status) {
    //         seat_idx = idx;
    //         break;
    //     }
    // }
    // if (seat_idx == null) {
    //     req.setStatus(.bad_request);
    //     req.sendBody("{\"error\":\"User not seated or already folded\"}") catch {};
    //     return;
    // }

    // Suppose the table enforces t.curr_player = seat_idx
    // If needed, do: table_ref.curr_player = seat_idx.?
    // table_ref.curr_player = seat_idx.?; // if you want to force it

    // Perform the action:
    table_ref.play(chosen_action);
    // if (play_res) |err| {
    //     req.setStatus(.bad_request);
    //     std.debug.print("Error in table.play: {any}\n", .{err});
    //     req.sendBody("{\"error\":\"Invalid move\"}") catch {};
    //     return;
    // }

    _ = user_id_str;

    req.setStatus(.ok);
    req.setHeader("Content-Type", "application/json") catch {};
    req.sendBody("{\"success\":true, \"message\":\"Action processed\"}") catch {};
}

fn handlePlayRoulette(req: zap.Request) void {
    // etc... your existing logic
    req.setStatus(.ok);
    req.setHeader("Content-Type", "application/json") catch {};
    req.sendBody("{\"success\":true}") catch {};
}

// A simple router for GET routes
fn handleGetRoutes(req: zap.Request) void {
    if (req.path == null) {
        req.setStatus(.not_found);
        return;
    }
    const path = req.path.?;

    if (std.mem.eql(u8, path, "/api/checkHasMoney")) {
        return handleCheckHasMoney(req);
    } else if (std.mem.eql(u8, path, "/api/joinPokerTable")) {
        return handleJoinPokerTable(req);
    } else if (std.mem.eql(u8, path, "/api/playPokerTable")) {
        return handlePlayPokerTable(req);
    } else if (std.mem.eql(u8, path, "/api/playSlots")) {
        return handlePlaySlots(req);
    } else if (std.mem.eql(u8, path, "/api/playRoulette")) {
        return handlePlayRoulette(req);
    }

    req.setStatus(.not_found);
}

fn handleRequest(req: zap.Request) void {
    switch (req.methodAsEnum()) {
        .OPTIONS => {
            addCorsHeaders(req);
            req.setStatus(.ok);
            req.sendBody("") catch {};
        },
        .GET => {
            addCorsHeaders(req);
            handleGetRoutes(req);
        },
        .PATCH => {
            addCorsHeaders(req);
            handleBalanceChange(req);
        },
        .POST => {
            addCorsHeaders(req);
            req.setStatus(.bad_request);
        },
        else => {
            addCorsHeaders(req);
            req.setStatus(.method_not_allowed);
        },
    }
}

// -----------------------------------------------------------------------------
// 5) main
// -----------------------------------------------------------------------------
pub fn main() !void {
    try gTableManager.init();
    try gTableManager.runAllTables();

    var listener = zap.HttpListener.init(.{
        .port = 3030,
        .on_request = handleRequest,
        .log = true,
    });
    try listener.listen();

    std.debug.print("Server listening on http://localhost:3030\n", .{});
    zap.start(.{
        .threads = 2,
        .workers = 2,
    });

    // const user_id: []const u8 = "6797751a4807fd9c2eb56596";
    // const maybe_data = try getUser(user_id);
    // if (!maybe_data.success) {
    //     std.debug.print("no worky", .{});
    // } else {
    //     std.debug.print("worky", .{});
    // }
}
