// Run: bash native/cpp/tests/run_tests.sh   (no framework needed)
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <vector>
#include "../engine/engine_api.h"
#include "../execution/trade_fsm.hpp"
static int fails = 0, checks = 0;
#define CHECK(c) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #c); } } while (0)
#define NEAR(a,b) CHECK(fabs((a)-(b)) < 1e-9)

struct T {
  void* h; int64_t ep = 1000; char pl[1024]; TcTickResult r; TcState s;
  T() { h = engine_create(); }
  ~T() { engine_destroy(h); }
  TcConfig cfg() { TcConfig c{}; c.market=4; c.direction=0; c.initial_barrier=4; c.recovery_barrier1=6; c.recovery_barrier2=8;
    c.trigger_digit=8; c.consecutive_count=2; c.deviation_direction=0; c.stake=1; c.win_behavior=0; return c; }
  void ready(bool real=false) {
    engine_set_account(h, "VRTC100", real, "USD"); engine_set_conn(h, 0, TC_CONN_READY); engine_set_conn(h, 1, TC_CONN_READY);
    engine_on_balance(h, "VRTC100", 1000.0, "USD"); }
  // feed a digit as a 2-pip quote (e.g. digit 7 -> 1234.57)
  TcTickResult tick(int digit) { engine_process_tick(h, ++ep, 1230.0 + digit / 100.0, 2, engine_now_us(), &r, pl, sizeof pl); return r; }
  TcState st() { engine_get_state(h, &s); return s; }
  void feed(std::vector<int> v) { for (int d : v) tick(d); }
};

static void test_math() {
  T t; TcConfig c = t.cfg(); engine_configure(t.h, &c);
  t.feed({7, 4}); TcState s = t.st();
  CHECK(s.prev_digit == 7 && s.cur_digit == 4); NEAR(s.average, 5.5); NEAR(s.deviation, -1.5); CHECK(s.deviation_sign == -1);
  t.tick(8); s = t.st(); NEAR(s.average, 6.0); NEAR(s.deviation, 2.0); CHECK(s.deviation_sign == 1);
  t.tick(8); s = t.st(); NEAR(s.deviation, 0.0); CHECK(s.deviation_sign == 0 && s.consec_pos == 0 && s.consec_neg == 0);
  T u; engine_configure(u.h, &c); engine_process_tick(u.h, 5, 1234.560, 3, 0, &u.r, u.pl, sizeof u.pl); CHECK(u.r.digit == 0);   // pip_size keeps trailing zero
}
static void test_sequences() {
  T t; TcConfig c = t.cfg(); engine_configure(t.h, &c);
  t.feed({0, 7, 8}); TcState s = t.st();          // +3.5, +0.5
  CHECK(s.consec_pos == 2 && s.consec_neg == 0);
  T n; engine_configure(n.h, &c); n.feed({9, 4, 1}); s = n.st();   // -2.5, -1.5
  CHECK(s.consec_neg == 2 && s.consec_pos == 0);
}
static void test_trigger() {
  { T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);
    t.feed({0, 7}); CHECK(t.r.action == TC_ACT_NONE);               // only 1 positive run
    t.tick(8); CHECK(t.r.action == TC_ACT_EXECUTE); CHECK(t.r.barrier == 4 && t.r.direction == 0);
    CHECK(strstr(t.pl, "\"DIGITOVER\"") && strstr(t.pl, "\"R_100\"") && strstr(t.pl, "\"barrier\":\"4\"")); }
  { T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);
    t.feed({0, 6, 7}); CHECK(t.r.action == TC_ACT_NONE); }           // run ok, wrong trigger digit
  { T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);
    t.feed({9, 3, 8}); CHECK(t.r.action == TC_ACT_NONE); }           // digit ok, wrong deviation direction
  { T t; TcConfig c = t.cfg(); c.deviation_direction = 1; c.trigger_digit = 1; engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);
    t.feed({9, 4, 1}); CHECK(t.r.action == TC_ACT_EXECUTE); }       // negative run, trigger digit 1
}
static void win(T& t, double p = 0.95) { engine_on_buy_result(t.h, t.r.trade_id, 1, 777, 1, 0, 0); engine_on_contract_update(t.h, 777, 1, p, engine_now_us()); }
static void lose(T& t, double p = -1) { engine_on_buy_result(t.h, t.r.trade_id, 1, 777, 1, 0, 0); engine_on_contract_update(t.h, 777, 2, p, engine_now_us()); }
static void test_recovery() {
  T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);
  t.feed({0, 7, 8}); CHECK(t.r.barrier == 4); lose(t); CHECK(t.st().recovery_level == 1);
  t.feed({0, 7, 8}); CHECK(t.r.action == TC_ACT_EXECUTE && t.r.barrier == 6); lose(t); CHECK(t.st().recovery_level == 2);
  t.feed({0, 7, 8}); CHECK(t.r.barrier == 8); lose(t); CHECK(t.st().recovery_level == 2);     // holds at RECOVERY_2
  CHECK(t.st().unrecovered > 2.99 && t.st().unrecovered < 3.01);
  t.feed({0, 7, 8}); CHECK(t.r.barrier == 8); win(t); CHECK(t.st().recovery_level == 2);      // +0.95 does not clear $3: stay R2
  t.feed({0, 7, 8}); CHECK(t.r.barrier == 8); win(t, 5); CHECK(t.st().recovery_level == 0 && t.st().unrecovered == 0);   // fully recovered
}
// Cumulative recovery: shared barriers, actual settled P/L, worked example from the spec
static void test_cumulative_recovery() {
  { T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);
    t.feed({0,7,8}); CHECK(t.r.barrier == 4); lose(t, -2);  CHECK(t.st().recovery_level == 1 && t.st().unrecovered == 2.0);
    t.feed({0,7,8}); CHECK(t.r.barrier == 6); win(t, 1);    CHECK(t.st().recovery_level == 2 && t.st().unrecovered == 1.0);   // partial -> R2
    t.feed({0,7,8}); CHECK(t.r.barrier == 8); lose(t, -1);  CHECK(t.st().recovery_level == 2 && t.st().unrecovered == 2.0);
    t.feed({0,7,8}); CHECK(t.r.barrier == 8); win(t, 2.5);  CHECK(t.st().recovery_level == 0 && t.st().unrecovered == 0);     // recovered +0.50 net
    t.feed({0,7,8}); CHECK(t.r.barrier == 4); }
  { T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);       // R1 win that fully recovers returns to Initial
    t.feed({0,7,8}); lose(t, -1); t.feed({0,7,8}); CHECK(t.r.barrier == 6); win(t, 1.0);
    CHECK(t.st().recovery_level == 0 && t.st().unrecovered == 0); t.feed({0,7,8}); CHECK(t.r.barrier == 4); }
  { T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);       // initial win never touches recovery
    t.feed({0,7,8}); win(t, 0.9); CHECK(t.st().recovery_level == 0 && t.st().unrecovered == 0); }
  { T t; TcConfig c = t.cfg(); c.win_behavior = 1; engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);   // legacy setting is ignored
    t.feed({0,7,8}); lose(t, -2); t.feed({0,7,8}); lose(t, -2); t.feed({0,7,8}); win(t, 1); CHECK(t.st().recovery_level == 2); }
  { T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);       // duplicate settlement is not double counted
    t.feed({0,7,8}); lose(t, -2); engine_on_contract_update(t.h, 777, 2, -2, engine_now_us()); CHECK(t.st().unrecovered == 2.0 && t.st().recovery_level == 1);
    std::vector<uint8_t> b(8192); int n = engine_serialize(t.h, b.data(), (int)b.size());                    // persists across restart
    T r; CHECK(engine_restore(r.h, b.data(), n, 1) == 0); CHECK(r.st().unrecovered == 2.0 && r.st().recovery_level == 1); }
  { T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);       // reset-strategy clears it
    t.feed({0,7,8}); lose(t, -2); engine_command(t.h, TC_CMD_RESET_STRATEGY); CHECK(t.st().unrecovered == 0 && t.st().recovery_level == 0); }
}
static void test_risk_martingale() {
  T t; TcConfig c = t.cfg(); c.martingale_enabled = 1; c.martingale_multiplier = 2; c.martingale_max_steps = 2; c.max_stake = 100;
  engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);
  t.feed({0,7,8}); NEAR(t.r.stake, 1.0); lose(t);
  t.feed({0,7,8}); NEAR(t.r.stake, 2.0); lose(t);
  t.feed({0,7,8}); NEAR(t.r.stake, 4.0); lose(t);                      // level 3 > max_steps(2) => halt after this loss
  TcState s = t.st(); CHECK(s.bot_status == TC_BOT_STOPPED && s.last_error == TC_ERR_RISK_LIMIT_REACHED);
  t.feed({0,7,8}); CHECK(t.r.action == TC_ACT_NONE);
  T m; c.martingale_max_steps = 10; c.max_stake = 3; engine_configure(m.h, &c); m.ready(); engine_command(m.h, TC_CMD_START);
  m.feed({0,7,8}); lose(m); m.feed({0,7,8}); lose(m);                  // next stake 4 > max 3 => stop
  CHECK(m.st().bot_status == TC_BOT_STOPPED);
  T d; c = d.cfg(); c.max_daily_loss = 2; engine_configure(d.h, &c); d.ready(); engine_command(d.h, TC_CMD_START);
  d.feed({0,7,8}); lose(d, -1); d.feed({0,7,8}); lose(d, -1); CHECK(d.st().bot_status == TC_BOT_STOPPED);
  T l; c = l.cfg(); c.max_consecutive_losses = 2; engine_configure(l.h, &c); l.ready(); engine_command(l.h, TC_CMD_START);
  l.feed({0,7,8}); lose(l); l.feed({0,7,8}); lose(l); CHECK(l.st().bot_status == TC_BOT_STOPPED);
  T tp; c = tp.cfg(); c.take_profit = 1; engine_configure(tp.h, &c); tp.ready(); engine_command(tp.h, TC_CMD_START);
  tp.feed({0,7,8}); win(tp, 1.5); CHECK(tp.st().bot_status == TC_BOT_STOPPED);
}
static void test_duplicates_and_safety() {
  T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);
  t.feed({0, 7}); t.tick(8); CHECK(t.r.action == TC_ACT_EXECUTE);
  int64_t e = t.ep; engine_process_tick(t.h, e, 1230.08, 2, 0, &t.r, t.pl, sizeof t.pl);        // replayed tick
  CHECK(t.r.action == TC_ACT_NONE && t.r.error_code == TC_ERR_DUPLICATE_TICK);
  t.feed({0, 7, 8}); CHECK(t.r.action == TC_ACT_NONE);                                       // trade in flight: no second execution
  CHECK(t.st().total_trades == 0 && t.st().fsm_state == TC_FSM_EXECUTING);
  // not ready / wrong account / emergency
  T n; engine_configure(n.h, &c); engine_command(n.h, TC_CMD_START); n.feed({0,7,8}); CHECK(n.r.action == TC_ACT_BLOCKED && n.r.error_code == TC_ERR_NOT_READY);
  T a; engine_configure(a.h, &c); a.ready(); engine_on_balance(a.h, "CR999", 5, "USD"); engine_command(a.h, TC_CMD_START);
  a.feed({0,7,8}); CHECK(a.r.action == TC_ACT_BLOCKED && a.r.error_code == TC_ERR_ACCOUNT_MISMATCH);
  T em; engine_configure(em.h, &c); em.ready(); engine_command(em.h, TC_CMD_START); engine_command(em.h, TC_CMD_EMERGENCY_STOP);
  em.feed({0,7,8}); CHECK(em.r.action == TC_ACT_NONE); CHECK(engine_command(em.h, TC_CMD_START) == TC_ERR_EMERGENCY_STOP);
  engine_command(em.h, TC_CMD_CLEAR_EMERGENCY); CHECK(engine_command(em.h, TC_CMD_START) == 0);
  // invalid barrier combos rejected at configure time
  TcConfig bad = t.cfg(); bad.initial_barrier = 9; CHECK(engine_configure(t.h, &bad) == TC_ERR_INVALID_BARRIER);
  bad = t.cfg(); bad.direction = 1; bad.initial_barrier = 0; CHECK(engine_configure(t.h, &bad) == TC_ERR_INVALID_BARRIER);
}
static void test_fsm_and_reject() {
  using namespace tc;
  CHECK(fsm_allowed(TC_FSM_MONITORING, TC_FSM_TRIGGER_DETECTED)); CHECK(!fsm_allowed(TC_FSM_MONITORING, TC_FSM_EXECUTING));
  CHECK(!fsm_allowed(TC_FSM_OPEN, TC_FSM_MONITORING)); CHECK(!fsm_allowed(TC_FSM_IDLE, TC_FSM_OPEN));
  T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);
  t.feed({0,7,8}); int64_t id = t.r.trade_id;
  CHECK(engine_on_buy_result(t.h, id + 5, 1, 9, 1, 0, 0) == 0 && t.st().fsm_state == TC_FSM_EXECUTING);   // wrong id ignored
  CHECK(engine_on_buy_result(t.h, id, 0, 0, 0, TC_ERR_TRADE_REJECTED, 0) == 1);
  TcState s = t.st(); CHECK(s.fsm_state == TC_FSM_IDLE && s.bot_status == TC_BOT_PAUSED && s.last_result == TC_RES_REJECTED && s.losses == 0);
}
static void test_snapshot_and_reconcile() {
  T t; TcConfig c = t.cfg(); c.martingale_enabled = 1; c.martingale_multiplier = 2; c.martingale_max_steps = 5; engine_configure(t.h, &c);
  t.ready(); engine_command(t.h, TC_CMD_START); t.feed({0,7,8}); lose(t); t.feed({3, 5});
  std::vector<uint8_t> b(8192); int n = engine_serialize(t.h, b.data(), (int)b.size()); CHECK(n > 0);
  T r; CHECK(engine_restore(r.h, b.data(), n, 1) == 0); TcState a = t.st(), z = r.st();
  CHECK(z.prev_digit == a.prev_digit && z.cur_digit == a.cur_digit && z.recovery_level == 1 && z.martingale_level == 1);
  NEAR(z.average, a.average); NEAR(z.deviation, a.deviation); CHECK(z.bot_status == TC_BOT_RUNNING && z.last_tick_epoch == a.last_tick_epoch);
  engine_process_tick(r.h, a.last_tick_epoch, 1230.05, 2, 0, &r.r, r.pl, sizeof r.pl); CHECK(r.r.error_code == TC_ERR_DUPLICATE_TICK);  // no replay after restore
  T cold; CHECK(engine_restore(cold.h, b.data(), n, 0) == 0); CHECK(cold.st().bot_status == TC_BOT_PAUSED);
  b[40] ^= 0xFF; T bad; CHECK(engine_restore(bad.h, b.data(), n, 1) == TC_ERR_BAD_SNAPSHOT);                         // corruption detected
  // reconnect during an unconfirmed buy
  T u; engine_configure(u.h, &c); u.ready(); engine_command(u.h, TC_CMD_START); u.feed({0,7,8}); int64_t id = u.r.trade_id;
  CHECK(engine_on_exec_timeout(u.h, id) == 1); CHECK(u.st().needs_reconcile == 1 && u.st().bot_status == TC_BOT_PAUSED);
  engine_command(u.h, TC_CMD_START); u.feed({0,7,8}); CHECK(u.r.action == TC_ACT_NONE && u.st().fsm_state == TC_FSM_EXECUTING);   // no new trade until reconciled
  CHECK(engine_reconcile(u.h, id, 1, 4242, 1, 0.95, engine_now_us()) == 1);
  CHECK(u.st().total_trades == 1 && u.st().wins == 1 && u.st().needs_reconcile == 0 && u.st().fsm_state != TC_FSM_EXECUTING);
  T v; engine_configure(v.h, &c); v.ready(); engine_command(v.h, TC_CMD_START); v.feed({0,7,8}); id = v.r.trade_id;
  engine_on_exec_timeout(v.h, id); CHECK(engine_reconcile(v.h, id, 0, 0, 0, 0, 0) == 1);
  CHECK(v.st().last_result == TC_RES_UNCONFIRMED && v.st().total_trades == 0);                                       // never assumed win/loss
  TcRecord rec; CHECK(engine_get_last_record(v.h, &rec) == 1 && rec.result == TC_RES_UNCONFIRMED);
}

// digits that give deviation d = (cur-prev)/2 ending on trigger digit 2: -2.0 => 6,2 ; -1.0 => 4,2
static void test_loss_dev_filter() {
  auto mk = [](T& t, int filter) { TcConfig c = t.cfg(); c.deviation_direction = 1; c.trigger_digit = 2; c.consecutive_count = 1;
    c.loss_dev_filter = filter; engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START); };
  { T t; mk(t, 1);
    t.feed({6, 2}); CHECK(t.r.action == TC_ACT_EXECUTE); lose(t);                    // -2.0 LOSS
    CHECK(t.st().restricted_dev2 == -4);
    t.feed({4, 2}); CHECK(t.r.action == TC_ACT_EXECUTE); lose(t);                    // -1.0 LOSS (earlier -2.0 discarded)
    CHECK(t.st().restricted_dev2 == -2 && t.st().recovery_level == 2 && t.st().losses == 2);
    TcState b = t.st();
    t.feed({4, 2}); CHECK(t.r.action == TC_ACT_FILTERED);                            // -1.0 REJECT
    TcState a = t.st();
    CHECK(a.total_trades == b.total_trades && a.recovery_level == b.recovery_level && a.martingale_level == b.martingale_level
          && a.fsm_state == TC_FSM_MONITORING && a.consec_neg == 1 && a.filter_rejects == 1 && a.losses == b.losses);
    t.feed({6, 2}); CHECK(t.r.action == TC_ACT_EXECUTE);                             // -2.0 ALLOW (earlier loss deviation no longer restricted)
    win(t); CHECK(t.st().restricted_dev2 == 99);                                     // win consumes the restriction
    t.feed({4, 2}); CHECK(t.r.action == TC_ACT_EXECUTE); }
  { T t; mk(t, 0);                                                                   // OFF: identical to legacy behaviour
    t.feed({6, 2}); lose(t); t.feed({6, 2}); CHECK(t.r.action == TC_ACT_EXECUTE); CHECK(t.st().restricted_dev2 == 99 && t.st().filter_rejects == 0); }
  { T t; mk(t, 1); t.feed({6, 2}); lose(t);                                          // restriction survives snapshot/restore
    std::vector<uint8_t> b(8192); int n = engine_serialize(t.h, b.data(), (int)b.size());
    T r; CHECK(engine_restore(r.h, b.data(), n, 1) == 0); CHECK(r.st().restricted_dev2 == -4);
    r.ready(); r.ep = t.ep; r.feed({6, 2}); CHECK(r.r.action == TC_ACT_FILTERED); }
  { T t; mk(t, 1); t.feed({6, 2}); lose(t); TcConfig c = t.cfg(); c.deviation_direction = 1; c.trigger_digit = 2; c.consecutive_count = 1;
    c.loss_dev_filter = 0; engine_configure(t.h, &c); CHECK(t.st().restricted_dev2 == 99); }                      // turning OFF drops it
}
static void test_clear_history() {
  T t; TcConfig c = t.cfg(); c.martingale_enabled = 1; c.martingale_multiplier = 2; c.martingale_max_steps = 5; c.max_daily_loss = 50;
  engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START);
  t.feed({0,7,8}); lose(t); t.feed({0,7,8}); win(t, 2.0); t.feed({0,7,8}); lose(t);
  TcState b = t.st(); CHECK(b.total_trades == 3 && b.wins == 1 && b.losses == 2);
  CHECK(engine_command(t.h, TC_CMD_CLEAR_HISTORY) == 0);
  TcState a = t.st();
  CHECK(a.total_trades == 0 && a.wins == 0 && a.losses == 0 && a.last_result == 0); NEAR(a.stats_pnl, 0.0);
  CHECK(a.recovery_level == b.recovery_level && a.martingale_level == b.martingale_level && a.consec_losses == b.consec_losses);
  NEAR(a.session_pnl, b.session_pnl); NEAR(a.daily_pnl, b.daily_pnl); CHECK(a.bot_status == b.bot_status && a.fsm_state == b.fsm_state);
}

static void test_recovery_directions() {
  // initial OVER 4, recovery 1 OVER 5, recovery 2 UNDER 7 (the example)
  T t; TcConfig c = t.cfg(); c.direction = 0; c.initial_barrier = 4; c.recovery_direction1 = 0; c.recovery_barrier1 = 5;
  c.recovery_direction2 = 1; c.recovery_barrier2 = 7; CHECK(engine_configure(t.h, &c) == 0); t.ready(); engine_command(t.h, TC_CMD_START);
  t.feed({0,7,8}); CHECK(t.r.direction == 0 && t.r.barrier == 4 && strstr(t.pl, "DIGITOVER") && strstr(t.pl, "\"barrier\":\"4\"")); lose(t);
  CHECK(t.st().signal_direction == 0 && t.st().signal_barrier == 5);                           // signal panel follows the recovery level
  t.feed({0,7,8}); CHECK(t.r.direction == 0 && t.r.barrier == 5 && strstr(t.pl, "DIGITOVER") && strstr(t.pl, "\"barrier\":\"5\"")); lose(t);
  CHECK(t.st().signal_direction == 1 && t.st().signal_barrier == 7);
  t.feed({0,7,8}); CHECK(t.r.direction == 1 && t.r.barrier == 7 && strstr(t.pl, "DIGITUNDER") && strstr(t.pl, "\"barrier\":\"7\"")); lose(t);
  t.feed({0,7,8}); CHECK(t.r.direction == 1 && t.r.barrier == 7);                              // stays on RECOVERY_2 after another loss
  win(t, 10); CHECK(t.st().recovery_level == 0);                                               // fully recovered -> Initial
  t.feed({0,7,8}); CHECK(t.r.direction == 0 && t.r.barrier == 4);                              // back to the initial trade
  // initial direction is independent: initial UNDER 3, R1 OVER 5, R2 UNDER 7
  T u; c = u.cfg(); c.direction = 1; c.initial_barrier = 3; c.recovery_direction1 = 0; c.recovery_barrier1 = 5; c.recovery_direction2 = 1; c.recovery_barrier2 = 7;
  CHECK(engine_configure(u.h, &c) == 0); u.ready(); engine_command(u.h, TC_CMD_START);
  u.feed({0,7,8}); CHECK(u.r.direction == 1 && u.r.barrier == 3 && strstr(u.pl, "DIGITUNDER")); lose(u);
  u.feed({0,7,8}); CHECK(u.r.direction == 0 && u.r.barrier == 5 && strstr(u.pl, "DIGITOVER")); lose(u);
  u.feed({0,7,8}); CHECK(u.r.direction == 1 && u.r.barrier == 7 && strstr(u.pl, "DIGITUNDER"));
  // each barrier is validated against ITS OWN direction
  TcConfig bad = t.cfg(); bad.recovery_direction1 = 0; bad.recovery_barrier1 = 9; CHECK(engine_configure(t.h, &bad) == TC_ERR_INVALID_BARRIER);   // OVER 9
  bad = t.cfg(); bad.recovery_direction2 = 1; bad.recovery_barrier2 = 0; CHECK(engine_configure(t.h, &bad) == TC_ERR_INVALID_BARRIER);               // UNDER 0
  bad = t.cfg(); bad.recovery_direction1 = 2; CHECK(engine_configure(t.h, &bad) == TC_ERR_INVALID_CONFIG);
  // stakes / martingale unchanged by directions
  T m; c = m.cfg(); c.martingale_enabled = 1; c.martingale_multiplier = 2; c.martingale_max_steps = 5; c.recovery_direction2 = 1; c.recovery_barrier2 = 7;
  engine_configure(m.h, &c); m.ready(); engine_command(m.h, TC_CMD_START);
  m.feed({0,7,8}); NEAR(m.r.stake, 1.0); lose(m); m.feed({0,7,8}); NEAR(m.r.stake, 2.0); lose(m); m.feed({0,7,8}); NEAR(m.r.stake, 4.0); CHECK(m.r.direction == 1);
}

static void test_trigger_modes() {
  auto mk = [](T& t, int mode, int dir, int dev2, int digit, int count) { TcConfig c = t.cfg(); c.trigger_mode = mode; c.deviation_direction = dir;
    c.trigger_dev2 = dev2; c.trigger_digit = digit; c.consecutive_count = count; int e = engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START); return e; };
  // spec: count 2, Positive, trigger digit 3  (digits 0,2,3 => +1.0, +0.5, final digit 3)
  { T t; CHECK(mk(t, 0, 0, 0, 3, 2) == 0); t.feed({0, 2, 3}); CHECK(t.r.action == TC_ACT_EXECUTE); }
  { T t; CHECK(mk(t, 0, 0, 0, 3, 2) == 0); t.feed({0, 7, 8}); CHECK(t.r.action == TC_ACT_NONE); }           // wrong final digit, digit mode unchanged
  // spec: count 2, Positive, deviation trigger +0.5 (+3.5 -> +0.5 = digits 0,7,8)
  { T t; CHECK(mk(t, 1, 0, 1, 3, 2) == 0); t.feed({0, 7, 8}); CHECK(t.r.action == TC_ACT_EXECUTE); }       // trigger digit (3) is ignored in deviation mode
  { T t; CHECK(mk(t, 1, 0, 4, 3, 2) == 0); t.feed({0, 7, 8}); CHECK(t.r.action == TC_ACT_NONE); }           // needs +2.0, final was +0.5
  { T t; CHECK(mk(t, 1, 0, 4, 3, 2) == 0); t.feed({0, 3, 7}); CHECK(t.r.action == TC_ACT_EXECUTE); }       // +1.5 then +2.0
  // spec: count 2, Negative, deviation trigger -1.5 (-2.5 -> -1.5 = digits 9,4,1)
  { T t; CHECK(mk(t, 1, 1, -3, 3, 2) == 0); t.feed({9, 4, 1}); CHECK(t.r.action == TC_ACT_EXECUTE); }
  { T t; CHECK(mk(t, 1, 1, -5, 3, 2) == 0); t.feed({9, 4, 1}); CHECK(t.r.action == TC_ACT_NONE); }         // -2.5 required, got -1.5
  // sign matters: +1.5 is not -1.5
  { T t; CHECK(mk(t, 1, 0, 3, 3, 2) == 0); t.feed({0, 2, 5}); CHECK(t.r.action == TC_ACT_EXECUTE); }       // +1.0 then +1.5 matches +1.5
  { T t; CHECK(mk(t, 1, 1, -3, 3, 2) == 0); t.feed({0, 2, 5}); CHECK(t.r.action == TC_ACT_NONE); }         // same digits do not satisfy -1.5
  // consecutive requirement still applies: -3.5 then +0.5 (run of 1 positive) does not qualify
  { T t; CHECK(mk(t, 1, 0, 1, 3, 2) == 0); t.feed({9, 2, 3}); CHECK(t.r.action == TC_ACT_NONE); }
  // exactness: a run longer than required still qualifies on the exact final value
  { T t; CHECK(mk(t, 1, 0, 1, 3, 2) == 0); t.feed({0, 3, 7, 8}); CHECK(t.r.action == TC_ACT_EXECUTE); }
  // switching back to Trigger Digit restores the original behaviour exactly
  { T t; CHECK(mk(t, 1, 0, 1, 3, 2) == 0); TcConfig c = t.cfg(); c.trigger_mode = 0; c.trigger_digit = 8; c.consecutive_count = 2; CHECK(engine_configure(t.h, &c) == 0);
    t.feed({0, 7, 8}); CHECK(t.r.action == TC_ACT_EXECUTE); }
  // validation
  { T t; TcConfig c = t.cfg(); c.trigger_mode = 1; c.deviation_direction = 0; c.trigger_dev2 = -3; CHECK(engine_configure(t.h, &c) == TC_ERR_INVALID_CONFIG);   // negative trigger with a positive run
    c.deviation_direction = 1; c.trigger_dev2 = 3; CHECK(engine_configure(t.h, &c) == TC_ERR_INVALID_CONFIG);
    c.trigger_dev2 = 0; CHECK(engine_configure(t.h, &c) == TC_ERR_INVALID_CONFIG);
    c.deviation_direction = 0; c.trigger_dev2 = 10; CHECK(engine_configure(t.h, &c) == TC_ERR_INVALID_CONFIG);
    c.trigger_mode = 2; c.trigger_dev2 = 1; CHECK(engine_configure(t.h, &c) == TC_ERR_INVALID_CONFIG); }
  // record keeps the actual final digit in deviation mode; loss filter / recovery still operate
  { T t; CHECK(mk(t, 1, 0, 1, 3, 2) == 0); t.feed({0, 7, 8}); lose(t); TcRecord r; CHECK(engine_get_last_record(t.h, &r) == 1 && r.trigger_digit == 8 && t.st().recovery_level == 1); }
}

// ---------- Strategy 2 ----------
// S2 deviations (doubled): D1 = +2.0 (4), D2 = -1.5 (-3), D3 = +0.5 (1).
static void s2setup(T& t, bool s1 = false) {
  TcConfig c = t.cfg(); c.s2_dev1 = 4; c.s2_dev2 = -3; c.s2_dev3 = 1; CHECK(engine_configure(t.h, &c) == 0); t.ready();
  engine_command(t.h, s1 ? TC_CMD_S1_ON : TC_CMD_S1_OFF); engine_command(t.h, TC_CMD_S2_ON); engine_command(t.h, TC_CMD_START); }
static void fire(T& t, int idx) {            // two ticks whose deviation equals the configured one for deviation `idx`
  static const int pre[3] = {2, 5, 8}, post[3] = {6, 2, 9}; t.tick(pre[idx]); t.tick(post[idx]); }
static void test_strategy2() {
  const int kWinTo[3] = {1, 2, 1}, kLossTo[3] = {2, 0, 0};            // the spec's table
  for (int from = 0; from < 3; from++) for (int w = 0; w < 2; w++) {  // all six transitions
    T t; s2setup(t);
    // walk the cycle to `from` using the table itself
    int path[3][3] = {{-1}, {1, -1}, {1, 2}}; (void)path;
    int guard = 0; while (t.st().s2_idx != from && guard++ < 6) { fire(t, t.st().s2_idx); win(t); }
    CHECK(t.st().s2_idx == from);
    fire(t, from); CHECK(t.r.action == TC_ACT_EXECUTE); CHECK(t.st().s2_pending == 1 && t.st().trade_owner == 1);
    CHECK(t.st().s2_idx == from);                                     // nothing moves while the trade is open
    if (w) win(t); else lose(t);
    CHECK(t.st().s2_idx == (w ? kWinTo[from] : kLossTo[from])); CHECK(t.st().s2_pending == 0);
  }
  { T t; s2setup(t); CHECK(t.st().s2_idx == 0);                        // first activation starts at Deviation 1
    t.tick(2); t.tick(6); CHECK(t.r.action == TC_ACT_EXECUTE && t.r.barrier == 4); win(t);
    CHECK(t.st().s2_idx == 1);
    t.tick(2); t.tick(6); CHECK(t.r.action == TC_ACT_NONE);           // D1's deviation no longer fires: D2 (-1.5) is active
    t.tick(5); t.tick(2); CHECK(t.r.action == TC_ACT_EXECUTE); }
  // activation / deactivation
  { T t; s2setup(t); engine_command(t.h, TC_CMD_S2_OFF); fire(t, 0); CHECK(t.r.action == TC_ACT_NONE && t.st().s2_on == 0);
    engine_command(t.h, TC_CMD_S2_ON); fire(t, 0); CHECK(t.r.action == TC_ACT_EXECUTE); win(t); CHECK(t.st().s2_idx == 1);
    engine_command(t.h, TC_CMD_S2_OFF); engine_command(t.h, TC_CMD_S2_ON); CHECK(t.st().s2_idx == 1);   // re-enable RESUMES, never restarts
    engine_command(t.h, TC_CMD_S2_NEW_CYCLE); CHECK(t.st().s2_idx == 0); }                                // explicit fresh cycle
  { T t; s2setup(t); fire(t, 0); engine_command(t.h, TC_CMD_S2_OFF);                                      // OFF while a trade is open
    CHECK(t.st().fsm_state == TC_FSM_EXECUTING && t.st().open_contract_id == 0);
    CHECK(engine_command(t.h, TC_CMD_S2_NEW_CYCLE) == TC_ERR_BUSY);
    win(t); CHECK(t.st().s2_idx == 1 && t.st().total_trades == 1 && t.st().s2_on == 0); }               // still settles + transitions
  // simultaneous strategies keep independent state
  { T t; s2setup(t, true); TcConfig c = t.cfg(); c.s2_dev1 = 4; c.s2_dev2 = -3; c.s2_dev3 = 1; engine_configure(t.h, &c);
    t.feed({0, 7, 8}); CHECK(t.r.action == TC_ACT_EXECUTE && t.st().trade_owner == 0); lose(t);               // Strategy 1 trade
    TcState a = t.st(); CHECK(a.s2_idx == 0 && a.s2_wins == 0 && a.s2_losses == 0 && a.recovery_level == 1);  // S1 result never moves S2
    fire(t, 0); CHECK(t.r.action == TC_ACT_EXECUTE && t.st().trade_owner == 1); win(t);                       // Strategy 2 trade
    CHECK(t.st().s2_idx == 1 && t.st().s1_on == 1 && t.st().s2_wins == 1);
    engine_command(t.h, TC_CMD_S1_OFF); CHECK(t.st().s2_idx == 1 && t.st().s2_on == 1);                        // toggling S1 leaves S2 alone
    t.feed({0, 7, 8}); CHECK(t.r.action == TC_ACT_NONE); }
  { T t; s2setup(t, true); t.tick(1); t.tick(4); t.tick(8);        // both qualify on the same tick: only one trade, Strategy 1 wins the tie
    // digits 1,4,8: +1.5 then +2.0; S1 (2 positive, digit 8) qualifies and S2 D1 (+2.0) also matches
    CHECK(t.r.action == TC_ACT_EXECUTE && t.st().trade_owner == 0); }
  // duplicate / late results change nothing
  { T t; s2setup(t); fire(t, 0); int64_t id = t.r.trade_id;
    CHECK(engine_on_buy_result(t.h, id, 1, 55, 1, 0, 0) == 0); CHECK(engine_on_contract_update(t.h, 55, 0, 0, 1) == 0);
    CHECK(t.st().s2_idx == 0);                                         // OPEN (not settled) does not transition
    CHECK(engine_on_contract_update(t.h, 55, 2, -1.0, 2) == 1); CHECK(t.st().s2_idx == 2);
    CHECK(engine_on_contract_update(t.h, 55, 2, -1.0, 3) == 0); CHECK(engine_on_contract_update(t.h, 55, 1, 1.0, 4) == 0);
    CHECK(t.st().s2_idx == 2 && t.st().s2_losses == 1 && t.st().total_trades == 1);
    CHECK(engine_on_buy_result(t.h, id, 1, 55, 1, 0, 0) == 0); CHECK(t.st().s2_idx == 2); }
  // pending / unconfirmed trade never transitions; reconcile resolves exactly once
  { T t; s2setup(t); fire(t, 0); int64_t id = t.r.trade_id; CHECK(engine_on_exec_timeout(t.h, id) == 1);
    CHECK(t.st().s2_idx == 0 && t.st().needs_reconcile == 1); fire(t, 0); CHECK(t.r.action == TC_ACT_NONE);       // no second trade
    CHECK(engine_reconcile(t.h, id, 0, 0, 0, 0, 0) == 1); CHECK(t.st().s2_idx == 0 && t.st().last_result == TC_RES_UNCONFIRMED); }   // not found => stays put
  { T t; s2setup(t); fire(t, 0); int64_t id = t.r.trade_id; engine_on_exec_timeout(t.h, id);
    CHECK(engine_reconcile(t.h, id, 1, 900, 1, 0.9, 5) == 1); CHECK(t.st().s2_idx == 1);                           // found + won => D2
    CHECK(engine_reconcile(t.h, id, 1, 900, 1, 0.9, 6) == 0); CHECK(t.st().s2_idx == 1 && t.st().s2_wins == 1); }
  { T t; s2setup(t); fire(t, 0); engine_on_buy_result(t.h, t.r.trade_id, 0, 0, 0, TC_ERR_TRADE_REJECTED, 0);     // rejected buy: no transition
    CHECK(t.st().s2_idx == 0 && t.st().s2_wins == 0 && t.st().s2_losses == 0 && t.st().bot_status == TC_BOT_PAUSED); }
  // state restoration: exact deviation + pending trade survive a restart; no replay, no double transition
  { T t; s2setup(t); fire(t, 0); win(t); fire(t, 1); lose(t); CHECK(t.st().s2_idx == 0);
    fire(t, 0); win(t); CHECK(t.st().s2_idx == 1);
    std::vector<uint8_t> b(8192); int n = engine_serialize(t.h, b.data(), (int)b.size());
    T r; CHECK(engine_restore(r.h, b.data(), n, 1) == 0); TcState z = r.st();
    CHECK(z.s2_idx == 1 && z.s2_on == 1 && z.s1_on == 0 && z.s2_wins == t.st().s2_wins && z.s2_losses == t.st().s2_losses);
    r.ready(); r.ep = t.ep; fire(r, 1); CHECK(r.r.action == TC_ACT_EXECUTE); }                                     // resumes at D2, not D1
  { T t; s2setup(t); fire(t, 0); int64_t id = t.r.trade_id; engine_on_buy_result(t.h, id, 1, 77, 1, 0, 0);       // restart while the contract is OPEN
    std::vector<uint8_t> b(8192); int n = engine_serialize(t.h, b.data(), (int)b.size());
    T r; CHECK(engine_restore(r.h, b.data(), n, 1) == 0); CHECK(r.st().s2_pending == 1 && r.st().s2_idx == 0 && r.st().fsm_state == TC_FSM_OPEN);
    r.ready(); CHECK(engine_on_contract_update(r.h, 77, 1, 0.9, 9) == 1); CHECK(r.st().s2_idx == 1);
    CHECK(engine_on_contract_update(r.h, 77, 1, 0.9, 10) == 0); CHECK(r.st().s2_idx == 1); }
  { T t; s2setup(t); fire(t, 0); int64_t id = t.r.trade_id;                                                       // restart while EXECUTING (buy unconfirmed)
    std::vector<uint8_t> b(8192); int n = engine_serialize(t.h, b.data(), (int)b.size());
    T r; CHECK(engine_restore(r.h, b.data(), n, 1) == 0); CHECK(r.st().needs_reconcile == 1 && r.st().s2_idx == 0 && r.st().s2_pending == 1);
    r.ready(); CHECK(engine_reconcile(r.h, id, 1, 5, 2, -1.0, 1) == 1); CHECK(r.st().s2_idx == 2); }
  // reconnect (connection dropped and restored) keeps the cycle
  { T t; s2setup(t); fire(t, 0); win(t); engine_set_conn(t.h, 1, TC_CONN_RECONNECTING); fire(t, 1); CHECK(t.r.action == TC_ACT_BLOCKED);
    CHECK(t.st().s2_idx == 1); engine_set_conn(t.h, 1, TC_CONN_READY); engine_on_balance(t.h, "VRTC100", 1000, "USD"); fire(t, 1); CHECK(t.r.action == TC_ACT_EXECUTE); }
  // validation
  { T t; TcConfig c = t.cfg(); c.s2_dev1 = 10; CHECK(engine_configure(t.h, &c) == TC_ERR_INVALID_CONFIG); c.s2_dev1 = -9; CHECK(engine_configure(t.h, &c) == 0); }
  // Strategy 1 untouched when S2 is OFF (default)
  { T t; TcConfig c = t.cfg(); engine_configure(t.h, &c); t.ready(); engine_command(t.h, TC_CMD_START); CHECK(t.st().s1_on == 1 && t.st().s2_on == 0);
    t.feed({0, 7, 8}); CHECK(t.r.action == TC_ACT_EXECUTE && t.st().trade_owner == 0); win(t); CHECK(t.st().s2_idx == 0 && t.st().s2_wins == 0); }
}
static void test_recovery_switching() {
  T t; s2setup(t, true);                                              // both strategies enabled; barriers are global
  t.feed({0,7,8}); CHECK(t.st().trade_owner == 0 && t.r.barrier == 4); lose(t, -2);            // S1 loses on Initial
  CHECK(t.st().recovery_level == 1 && t.st().unrecovered == 2.0);
  engine_command(t.h, TC_CMD_S1_OFF);                                 // switch to S2 only: nothing resets
  CHECK(t.st().recovery_level == 1 && t.st().unrecovered == 2.0);
  fire(t, 0); CHECK(t.r.action == TC_ACT_EXECUTE && t.st().trade_owner == 1 && t.r.barrier == 6); win(t, 1);   // S2 trades on R1 barrier
  CHECK(t.st().recovery_level == 2 && t.st().unrecovered == 1.0);
  engine_command(t.h, TC_CMD_S1_ON); engine_command(t.h, TC_CMD_S2_OFF);                        // back to S1
  CHECK(t.st().recovery_level == 2 && t.st().unrecovered == 1.0);
  t.feed({0,7,8}); CHECK(t.st().trade_owner == 0 && t.r.barrier == 8); win(t, 1.5);             // S1 trades on R2 and completes recovery
  CHECK(t.st().recovery_level == 0 && t.st().unrecovered == 0);
}
static void test_martingale_persistence() {
  T t; s2setup(t, true); TcConfig c = t.cfg(); c.s2_dev1 = 4; c.s2_dev2 = -3; c.s2_dev3 = 1; c.stake = 5; c.martingale_enabled = 1; c.martingale_multiplier = 2;
  c.martingale_max_steps = 6; c.max_stake = 1000; c.max_daily_loss = 0; CHECK(engine_configure(t.h, &c) == 0);
  t.feed({0,7,8}); CHECK(t.r.stake == 5); lose(t, -5);                                           // Initial loss
  t.feed({0,7,8}); CHECK(t.r.stake == 10 && t.r.barrier == 6); lose(t, -10);                      // R1 loss
  t.feed({0,7,8}); CHECK(t.r.stake == 20 && t.r.barrier == 8); lose(t, -20);                      // R2
  t.feed({0,7,8}); CHECK(t.r.stake == 40); win(t, 10);                                            // partial win: owed 25 left -> stake NOT reset
  CHECK(t.st().recovery_level == 2 && t.st().martingale_level == 3 && t.st().unrecovered == 25.0);
  engine_command(t.h, TC_CMD_S1_OFF); fire(t, 0); CHECK(t.r.action == TC_ACT_EXECUTE && t.r.stake == 40 && t.r.barrier == 8); lose(t, -40);   // switch to S2, stake kept
  CHECK(t.st().martingale_level == 4 && t.st().unrecovered == 65.0);
  engine_command(t.h, TC_CMD_S1_ON); engine_command(t.h, TC_CMD_S2_OFF);
  t.feed({0,7,8}); CHECK(t.r.stake == 80); win(t, 70);                                            // recovered (+5 net) -> reset
  CHECK(t.st().recovery_level == 0 && t.st().martingale_level == 0 && t.st().unrecovered == 0);
  t.feed({0,7,8}); CHECK(t.r.stake == 5 && t.r.barrier == 4);
}
static void test_s2_counts() {
  auto mk = [](T& t, int c1, int c2, int c3) { s2setup(t); TcConfig c = t.cfg(); c.s2_dev1 = 4; c.s2_dev2 = -3; c.s2_dev3 = 1; c.s2_cnt1 = c1; c.s2_cnt2 = c2; c.s2_cnt3 = c3;
    CHECK(engine_configure(t.h, &c) == 0); };
  { T t; mk(t, 3, 2, 4);                                              // D1 +2.0 needs 2 positive deviations before it
    t.feed({5, 1, 2}); t.tick(6); CHECK(t.r.action == TC_ACT_NONE);   // -4,+1,+4: only one positive before -> run 2 < 3
    T u; mk(u, 3, 2, 4); u.feed({0, 1, 2}); u.tick(6); CHECK(u.r.action == TC_ACT_EXECUTE && u.st().trade_owner == 1);   // +1,+1,+4
    T v; mk(v, 3, 2, 4); v.feed({0, 1, 1}); v.tick(5); CHECK(v.r.action == TC_ACT_NONE);                                  // zero deviation breaks the run
    T w; mk(w, 3, 2, 4); w.feed({0, 1, 2, 3}); w.tick(7); CHECK(w.r.action == TC_ACT_EXECUTE);                           // longer run still qualifies
    T x; mk(x, 3, 2, 4); x.feed({0, 1, 2}); x.tick(5); CHECK(x.r.action == TC_ACT_NONE); }                                // run ok, wrong deviation (+3 != +4)
  { T t; mk(t, 3, 2, 4); t.feed({0, 1, 2}); t.tick(6); win(t); CHECK(t.st().s2_idx == 1);   // D2 -1.5 needs ONE negative before it
    t.feed({2, 8}); t.tick(5); CHECK(t.r.action == TC_ACT_NONE);                           // +6 then -3: run 1 < 2
    t.feed({9, 8}); t.tick(5); CHECK(t.r.action == TC_ACT_EXECUTE); lose(t); CHECK(t.st().s2_idx == 0); }   // -1 then -3 -> fires; loss -> D1
  { T t; mk(t, 1, 1, 1); t.feed({5, 1}); t.tick(5); CHECK(t.r.action == TC_ACT_EXECUTE); }  // count 1 = trigger only (previous behaviour)
  { T t; mk(t, 3, 2, 4); t.feed({0, 1, 2}); t.tick(6); win(t); t.feed({9, 8}); t.tick(5); win(t); CHECK(t.st().s2_idx == 2);   // D3 +0.5 count 4 -> 3 positives before it
    t.feed({0, 1, 2}); t.tick(3); CHECK(t.r.action == TC_ACT_NONE);                         // +1 run of 3 < 4
  }
  { T t; TcConfig c = t.cfg(); c.s2_cnt1 = 51; CHECK(engine_configure(t.h, &c) == TC_ERR_INVALID_CONFIG); c.s2_cnt1 = 0; CHECK(engine_configure(t.h, &c) == 0); }
}
static void test_abi() { int64_t s[4]; engine_abi_sizes(s); CHECK(s[0] == 29 * 8 && s[1] == (46 + 16 + 9) * 8 && s[2] == 10 * 8 && s[3] == 25 * 8); }
int main() {
  test_math(); test_sequences(); test_trigger(); test_recovery(); test_cumulative_recovery(); test_risk_martingale();
  test_duplicates_and_safety(); test_fsm_and_reject(); test_snapshot_and_reconcile(); test_loss_dev_filter(); test_clear_history(); test_recovery_directions(); test_trigger_modes(); test_strategy2(); test_recovery_switching(); test_martingale_persistence(); test_s2_counts(); test_abi();
  printf("%d checks, %d failed\n", checks, fails); return fails ? 1 : 0;
}
