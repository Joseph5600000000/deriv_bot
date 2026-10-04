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
  t.feed({0, 7, 8}); CHECK(t.r.barrier == 8); win(t); CHECK(t.st().recovery_level == 0);      // win_behavior 0: reset
  T u; c.win_behavior = 1; engine_configure(u.h, &c); u.ready(); engine_command(u.h, TC_CMD_START);
  u.feed({0,7,8}); lose(u); u.feed({0,7,8}); lose(u); u.feed({0,7,8}); win(u); CHECK(u.st().recovery_level == 1);   // step-down mode
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
static void test_abi() { int64_t s[4]; engine_abi_sizes(s); CHECK(s[0] == 18 * 8 && s[1] == (35 + 16 + 7) * 8 && s[2] == 10 * 8 && s[3] == 25 * 8); }
int main() {
  test_math(); test_sequences(); test_trigger(); test_recovery(); test_risk_martingale();
  test_duplicates_and_safety(); test_fsm_and_reject(); test_snapshot_and_reconcile(); test_abi();
  printf("%d checks, %d failed\n", checks, fails); return fails ? 1 : 0;
}
