// Authoritative trading engine. One mutex guards all state; calls are short and allocation-free.
#include <chrono>
#include <mutex>
#include <string.h>
#include <stdio.h>
#include <new>
#include "engine_api.h"
#include "../analysis/rolling_window.hpp"
#include "../strategy/strategy.hpp"
#include "../risk/risk_manager.hpp"
#include "../execution/trade_fsm.hpp"
#include "../state/snapshot.hpp"

namespace tc {
static const char* kSymbols[5] = {"R_10", "R_25", "R_50", "R_75", "R_100"};

struct Persist {                       // everything that must survive a restart (POD)
  TcConfig cfg; RollingWindow w; TcRecord rec; TcRecord last_done;
  int64_t s2_last_applied, s2_wins, s2_losses;      // Strategy 2 independent state
  int32_t s1_on, s2_on, s2_idx, s2_started, trade_owner /*0 S1, 1 S2, -1 none*/, s2_trade_idx;
  int64_t last_epoch, trade_seq, total_trades, open_contract, record_seq, day_index, recent[16], filter_rejects;
  double balance, session_pnl, daily_pnl, last_profit, stats_pnl;
  int32_t has_cfg, bot, fsm, recovery, mlevel, wins, losses, consec_losses, last_result, last_error,
          needs_reconcile, emergency, account_real, sig_dir, sig_barrier, trig_status, recent_count, balance_known, has_restrict, restrict_dev2;
  char account_id[32]; char currency[16];
};

class Engine {
 public:
  Engine() { memset((void*)&p_, 0, sizeof p_); p_.last_epoch = -1; p_.w.reset(); p_.fsm = TC_FSM_IDLE; p_.sig_barrier = -1; p_.s1_on = 1; p_.trade_owner = -1; }

  int configure(const TcConfig* c) {
    std::lock_guard<std::mutex> g(mu_);
    int e = validate(*c); if (e) return e;
    bool busy = p_.fsm == TC_FSM_EXECUTING || p_.fsm == TC_FSM_OPEN;
    if (p_.has_cfg && c->market != p_.cfg.market) {
      if (busy) return TC_ERR_BUSY;
      p_.w.reset(); p_.recent_count = 0; p_.trig_status = 0;      // different market => different digit stream
    }
    p_.cfg = *c; p_.has_cfg = 1;
    if (!p_.cfg.loss_dev_filter) p_.has_restrict = 0;
    return 0;
  }

  int command(int cmd) {
    std::lock_guard<std::mutex> g(mu_);
    switch (cmd) {
      case TC_CMD_START:
        if (!p_.has_cfg) return TC_ERR_INVALID_CONFIG;
        if (p_.emergency) return TC_ERR_EMERGENCY_STOP;
        if (p_.bot == TC_BOT_STOPPED) p_.session_pnl = 0;           // new session
        p_.bot = TC_BOT_RUNNING; p_.last_error = 0; break;
      case TC_CMD_PAUSE: if (p_.bot == TC_BOT_RUNNING) p_.bot = TC_BOT_PAUSED; break;
      case TC_CMD_STOP:  if (!p_.emergency) p_.bot = TC_BOT_STOPPED; break;
      case TC_CMD_EMERGENCY_STOP: p_.bot = TC_BOT_EMERGENCY; p_.emergency = 1; break;
      case TC_CMD_CLEAR_EMERGENCY: p_.emergency = 0; if (p_.bot == TC_BOT_EMERGENCY) p_.bot = TC_BOT_STOPPED; break;
      case TC_CMD_RESET_ANALYSIS: p_.w.reset(); p_.recent_count = 0; p_.trig_status = 0; break;
      case TC_CMD_RESET_STRATEGY:
        if (p_.fsm == TC_FSM_EXECUTING || p_.fsm == TC_FSM_OPEN) return TC_ERR_BUSY;
        p_.recovery = 0; p_.mlevel = 0; p_.consec_losses = 0; p_.session_pnl = 0; p_.has_restrict = 0; break;
      case TC_CMD_S1_ON: p_.s1_on = 1; break;
      case TC_CMD_S1_OFF: p_.s1_on = 0; break;                         // never touches an open trade
      case TC_CMD_S2_ON: if (!p_.s2_started) { p_.s2_idx = 0; p_.s2_started = 1; } p_.s2_on = 1; break;   // first activation starts at Deviation 1; later ones RESUME
      case TC_CMD_S2_OFF: p_.s2_on = 0; break;                         // cycle state kept; open S2 trade still settles normally
      case TC_CMD_S2_NEW_CYCLE:
        if ((p_.fsm == TC_FSM_EXECUTING || p_.fsm == TC_FSM_OPEN) && p_.trade_owner == 1) return TC_ERR_BUSY;
        p_.s2_idx = 0; p_.s2_started = 1; break;
      case TC_CMD_CLEAR_HISTORY:       // statistics only: risk accumulators, recovery, config and live trade are untouched
        p_.wins = 0; p_.losses = 0; p_.total_trades = 0; p_.last_result = 0; p_.last_profit = 0; p_.stats_pnl = 0; break;
      default: return TC_ERR_UNKNOWN;
    }
    sync_idle(); return 0;
  }

  void set_conn(int kind, int st) { std::lock_guard<std::mutex> g(mu_); (kind == 0 ? pub_ : trd_) = st; if (kind == 1 && st != TC_CONN_READY) verified_ = 0; }

  int set_account(const char* id, int real, const char* cur) {
    std::lock_guard<std::mutex> g(mu_);
    if (p_.fsm == TC_FSM_EXECUTING || p_.fsm == TC_FSM_OPEN) return TC_ERR_BUSY;
    snprintf(p_.account_id, sizeof p_.account_id, "%s", id ? id : "");
    snprintf(p_.currency, sizeof p_.currency, "%s", cur ? cur : "");
    p_.account_real = real ? 1 : 0; verified_ = 0; p_.balance_known = 0; return 0;
  }

  int on_balance(const char* loginid, double bal, const char* cur) {
    std::lock_guard<std::mutex> g(mu_);
    if (loginid) {
      if (strcmp(loginid, p_.account_id) != 0) { verified_ = 0; p_.last_error = TC_ERR_ACCOUNT_MISMATCH; return 0; }
      verified_ = 1;
    }
    p_.balance = bal; p_.balance_known = 1;
    if (cur && *cur) snprintf(p_.currency, sizeof p_.currency, "%s", cur);
    return verified_;
  }

  void process_tick(int64_t epoch, double quote, int pip, int64_t rx_us, TcTickResult* out, char* payload, int cap) {
    std::lock_guard<std::mutex> g(mu_);
    memset(out, 0, sizeof *out); out->digit = -1;
    int d = extract_digit(quote, pip); out->t_digit_us = now_us();
    if (d < 0) { out->error_code = TC_ERR_UNKNOWN; return; }
    if (epoch <= p_.last_epoch) { out->error_code = TC_ERR_DUPLICATE_TICK; return; }   // duplicate / replayed tick
    p_.last_epoch = epoch;
    int64_t day = epoch / 86400; if (day != p_.day_index) { p_.day_index = day; p_.daily_pnl = 0; }
    p_.w.push(d); out->digit = d;
    if (p_.recent_count < 16) p_.recent[p_.recent_count++] = d;
    else { memmove(p_.recent, p_.recent + 1, 15 * sizeof(int64_t)); p_.recent[15] = d; }
    bool q1 = p_.has_cfg && p_.s1_on && qualified(p_.cfg, p_.w);
    bool q2 = p_.has_cfg && p_.s2_on && p_.w.has_dev && (int64_t)(p_.w.cur - p_.w.prev) == s2_dev_for(p_.cfg, p_.s2_idx);
    bool q = q1 || q2;
    int owner = q1 ? 0 : 1;                                    // one shared trade slot; Strategy 1 keeps priority on a tie
    p_.trig_status = q ? 1 : 0;
    p_.sig_dir = p_.has_cfg ? (int)direction_for(p_.cfg, p_.recovery) : 0;
    p_.sig_barrier = p_.has_cfg ? (int)barrier_for(p_.cfg, p_.recovery) : -1;
    if (!q || p_.bot != TC_BOT_RUNNING || p_.fsm != TC_FSM_MONITORING) return;

    // Loss-Deviation Filter: same exact (integer, doubled) deviation as the last loss => skip, keep monitoring.
    if (p_.cfg.loss_dev_filter && p_.has_restrict && (p_.w.cur - p_.w.prev) == p_.restrict_dev2) {
      p_.filter_rejects++; out->action = TC_ACT_FILTERED; return;
    }
    go(TC_FSM_TRIGGER_DETECTED); go(TC_FSM_VALIDATING);
    int64_t barrier = barrier_for(p_.cfg, p_.recovery);
    int64_t dir = direction_for(p_.cfg, p_.recovery);          // Over/Under for THIS level only
    double stake = stake_for(p_.cfg, p_.mlevel);
    p_.trade_owner = owner; p_.s2_trade_idx = p_.s2_idx;
    int err = 0;
    if (!barrier_ok((int)dir, barrier)) err = TC_ERR_INVALID_BARRIER;
    else if (pub_ != TC_CONN_READY || trd_ != TC_CONN_READY) err = TC_ERR_NOT_READY;
    else if (!verified_) err = TC_ERR_ACCOUNT_MISMATCH;
    else if (p_.needs_reconcile) err = TC_ERR_STATE_SYNC_FAILED;
    else { RiskView r{p_.session_pnl, p_.daily_pnl, p_.balance, p_.balance_known, p_.consec_losses, p_.mlevel}; err = pre_trade(p_.cfg, r, stake); }
    if (!err && cap < 600) err = TC_ERR_UNKNOWN;
    if (err) {
      p_.trade_owner = -1; p_.last_error = err; out->action = TC_ACT_BLOCKED; out->error_code = err; go(TC_FSM_MONITORING);
      if (is_halting(err)) { p_.bot = TC_BOT_STOPPED; }
      sync_idle(); return;
    }
    TcRecord& r = p_.rec; memset(&r, 0, sizeof r);
    r.trade_id = ++p_.trade_seq; r.tick_epoch = epoch; r.market = p_.cfg.market; r.account_real = p_.account_real;
    r.prev_digit = p_.w.prev; r.cur_digit = p_.w.cur; r.deviation_sign = p_.w.sign;
    r.consecutive_seq = p_.cfg.deviation_direction == 0 ? p_.w.consec_pos : p_.w.consec_neg;
    r.trigger_digit = p_.cfg.trigger_mode == 1 ? p_.w.cur : p_.cfg.trigger_digit; r.direction = dir; r.barrier = barrier;
    r.recovery_level = p_.recovery; r.martingale_level = p_.mlevel; r.average = p_.w.average;
    r.deviation = p_.w.deviation; r.stake = stake; r.t_tick_rx_us = rx_us; r.t_digit_us = out->t_digit_us;
    r.t_trigger_us = now_us();
    int n = snprintf(payload, cap,
      "{\"buy\":\"1\",\"price\":%.2f,\"subscribe\":1,\"req_id\":%lld,\"parameters\":{\"amount\":%.2f,"
      "\"basis\":\"stake\",\"contract_type\":\"%s\",\"currency\":\"%s\",\"duration\":1,\"duration_unit\":\"t\","
      "\"underlying_symbol\":\"%s\",\"barrier\":\"%lld\"}}",
      stake, (long long)r.trade_id, stake, dir == 0 ? "DIGITOVER" : "DIGITUNDER", p_.currency,
      kSymbols[p_.cfg.market], (long long)barrier);
    r.t_request_us = now_us();
    go(TC_FSM_EXECUTING);
    out->action = TC_ACT_EXECUTE; out->trade_id = r.trade_id; out->direction = dir;
    out->barrier = barrier; out->stake = stake; out->payload_len = n; out->t_trigger_us = r.t_trigger_us;
  }

  int on_buy_result(int64_t tid, int ok, int64_t cid, double price, int err, int64_t ack_us) {
    std::lock_guard<std::mutex> g(mu_); (void)price;
    if (p_.fsm != TC_FSM_EXECUTING || tid != p_.rec.trade_id) return 0;   // late/duplicate ack ignored
    p_.rec.t_ack_us = ack_us ? ack_us : now_us();
    if (ok) { p_.open_contract = cid; p_.rec.contract_id = cid; go(TC_FSM_OPEN); return 0; }
    p_.rec.result = TC_RES_REJECTED;
    p_.last_error = err == TC_ERR_INSUFFICIENT_BALANCE ? err : TC_ERR_TRADE_REJECTED;
    p_.last_result = TC_RES_REJECTED; finalize();
    if (p_.bot == TC_BOT_RUNNING) p_.bot = TC_BOT_PAUSED;                  // never loop on a rejected trade
    go(TC_FSM_MONITORING); sync_idle(); return 1;
  }

  int on_contract_update(int64_t cid, int status, double profit, int64_t now) {
    std::lock_guard<std::mutex> g(mu_);
    if (p_.fsm != TC_FSM_OPEN || cid != p_.open_contract) return 0;
    if (status == 0) { if (!p_.rec.t_open_us) p_.rec.t_open_us = now; return 0; }
    if (!p_.rec.t_open_us) p_.rec.t_open_us = now;
    settle(status == 1, profit); return 1;
  }

  int on_exec_timeout(int64_t tid) {
    std::lock_guard<std::mutex> g(mu_);
    if (p_.fsm != TC_FSM_EXECUTING || tid != p_.rec.trade_id) return 0;
    p_.needs_reconcile = 1; p_.last_error = TC_ERR_EXECUTION_TIMEOUT;
    if (p_.bot == TC_BOT_RUNNING) { p_.bot = TC_BOT_PAUSED; }
    return 1;
  }

  // Resolve an unconfirmed buy against authoritative Deriv state (never replays the trade).
  int reconcile(int64_t tid, int found, int64_t cid, int status, double profit, int64_t now) {
    std::lock_guard<std::mutex> g(mu_);
    if (p_.fsm != TC_FSM_EXECUTING || tid != p_.rec.trade_id) return 0;
    p_.needs_reconcile = 0;
    if (!found) {
      p_.rec.result = TC_RES_UNCONFIRMED; p_.last_result = TC_RES_UNCONFIRMED;
      p_.last_error = TC_ERR_STATE_SYNC_FAILED; finalize(); go(TC_FSM_MONITORING);
      if (p_.bot == TC_BOT_RUNNING) { p_.bot = TC_BOT_PAUSED; }
      sync_idle(); return 1;
    }
    p_.open_contract = cid; p_.rec.contract_id = cid; if (!p_.rec.t_ack_us) p_.rec.t_ack_us = now;
    go(TC_FSM_OPEN);
    if (status == 0) return 0;
    settle(status == 1, profit); return 1;
  }

  void report_error(int c) { std::lock_guard<std::mutex> g(mu_); p_.last_error = c; }

  void get_state(TcState* s) {
    std::lock_guard<std::mutex> g(mu_);
    memset(s, 0, sizeof *s);
    s->bot_status = p_.bot; s->fsm_state = p_.fsm; s->public_conn = pub_; s->trade_conn = trd_;
    s->account_verified = verified_; s->account_real = p_.account_real; s->market = p_.has_cfg ? p_.cfg.market : 4;
    s->prev_digit = p_.w.prev; s->cur_digit = p_.w.cur; s->deviation_sign = p_.w.has_dev ? p_.w.sign : 0;
    s->consec_pos = p_.w.consec_pos; s->consec_neg = p_.w.consec_neg; s->trigger_status = p_.trig_status;
    s->signal_direction = p_.has_cfg ? direction_for(p_.cfg, p_.recovery) : p_.sig_dir;   // display follows the live recovery level
    s->signal_barrier = p_.has_cfg ? barrier_for(p_.cfg, p_.recovery) : p_.sig_barrier; s->recovery_level = p_.recovery;
    s->martingale_level = p_.mlevel; s->wins = p_.wins; s->losses = p_.losses; s->total_trades = p_.total_trades;
    s->consec_losses = p_.consec_losses; s->last_result = p_.last_result; s->last_error = p_.last_error;
    s->open_contract_id = p_.open_contract; s->last_trade_id = p_.trade_seq; s->needs_reconcile = p_.needs_reconcile;
    s->emergency_latched = p_.emergency; s->recent_count = p_.recent_count; s->record_seq = p_.record_seq;
    s->last_tick_epoch = p_.last_epoch;
    s->loss_filter_on = p_.has_cfg ? p_.cfg.loss_dev_filter : 0; s->restricted_dev2 = p_.has_restrict ? p_.restrict_dev2 : 99;
    s->s1_on = p_.s1_on; s->s2_on = p_.s2_on; s->s2_idx = p_.s2_idx; s->s2_wins = p_.s2_wins; s->s2_losses = p_.s2_losses;
    s->trade_owner = p_.trade_owner; s->s2_started = p_.s2_started; s->s2_pending = (p_.trade_owner == 1 && (p_.fsm == TC_FSM_EXECUTING || p_.fsm == TC_FSM_OPEN)) ? 1 : 0;
    s->filter_rejects = p_.filter_rejects; s->stats_pnl = p_.stats_pnl;
    for (int i = 0; i < 16; i++) s->recent[i] = p_.recent[i];
    s->average = p_.w.average; s->deviation = p_.w.deviation;
    s->current_stake = p_.has_cfg ? stake_for(p_.cfg, p_.mlevel) : 0;
    s->balance = p_.balance; s->session_pnl = p_.session_pnl; s->daily_pnl = p_.daily_pnl; s->last_profit = p_.last_profit;
    const TcRecord& r = (p_.fsm == TC_FSM_EXECUTING || p_.fsm == TC_FSM_OPEN) ? p_.rec : p_.last_done;
    auto sub = [](int64_t a, int64_t b) { return (a && b && a >= b) ? a - b : (int64_t)0; };
    s->lat_tick_to_trigger_us = sub(r.t_trigger_us, r.t_tick_rx_us);
    s->lat_trigger_to_send_us = sub(r.t_request_us, r.t_trigger_us);
    s->lat_send_to_ack_us = sub(r.t_ack_us, r.t_request_us);
    s->lat_ack_to_open_us = sub(r.t_open_us, r.t_ack_us);
    s->lat_total_us = sub(r.t_open_us ? r.t_open_us : r.t_ack_us, r.t_tick_rx_us);
  }

  int last_record(TcRecord* r) { std::lock_guard<std::mutex> g(mu_); if (!p_.record_seq) return 0; *r = p_.last_done; return 1; }

  int serialize(uint8_t* buf, int cap) {
    std::lock_guard<std::mutex> g(mu_);
    int need = (int)(sizeof(SnapHeader) + sizeof(Persist)); if (cap < need) return -1;
    SnapHeader h{kSnapMagic, kSnapVersion, (uint32_t)sizeof(Persist), fnv1a((const uint8_t*)&p_, sizeof p_)};
    memcpy(buf, &h, sizeof h); memcpy(buf + sizeof h, &p_, sizeof p_); return need;
  }

  int restore(const uint8_t* buf, int size, int resume) {
    std::lock_guard<std::mutex> g(mu_);
    if (size < (int)sizeof(SnapHeader)) return TC_ERR_BAD_SNAPSHOT;
    SnapHeader h; memcpy(&h, buf, sizeof h);
    if (h.magic != kSnapMagic || h.version != kSnapVersion || h.size != sizeof(Persist) ||
        size != (int)(sizeof h + sizeof(Persist))) return TC_ERR_BAD_SNAPSHOT;
    if (fnv1a(buf + sizeof h, sizeof(Persist)) != h.checksum) return TC_ERR_BAD_SNAPSHOT;
    memcpy(&p_, buf + sizeof h, sizeof p_);
    pub_ = trd_ = TC_CONN_DISCONNECTED; verified_ = 0; p_.balance_known = 0;
    if (p_.bot == TC_BOT_RUNNING && !resume) p_.bot = TC_BOT_PAUSED;
    if (p_.emergency) p_.bot = TC_BOT_EMERGENCY;
    if (p_.fsm == TC_FSM_EXECUTING) { p_.needs_reconcile = 1; if (p_.bot == TC_BOT_RUNNING) p_.bot = TC_BOT_PAUSED; }
    if (p_.fsm == TC_FSM_TRIGGER_DETECTED || p_.fsm == TC_FSM_VALIDATING || p_.fsm == TC_FSM_SETTLED || p_.fsm == TC_FSM_STATE_UPDATE) p_.fsm = TC_FSM_MONITORING;
    sync_idle(); return 0;
  }

  static int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
  }

 private:
  static int validate(const TcConfig& c) {
    if (c.market < 0 || c.market > 4 || (c.direction != 0 && c.direction != 1)) return TC_ERR_INVALID_CONFIG;
    if ((c.recovery_direction1 != 0 && c.recovery_direction1 != 1) || (c.recovery_direction2 != 0 && c.recovery_direction2 != 1)) return TC_ERR_INVALID_CONFIG;
    if (!barrier_ok((int)c.direction, c.initial_barrier) || !barrier_ok((int)c.recovery_direction1, c.recovery_barrier1) ||
        !barrier_ok((int)c.recovery_direction2, c.recovery_barrier2)) return TC_ERR_INVALID_BARRIER;
    if (c.trigger_digit < 0 || c.trigger_digit > 9 || c.consecutive_count < 1 || c.consecutive_count > 50 ||
        (c.deviation_direction != 0 && c.deviation_direction != 1) || (c.win_behavior != 0 && c.win_behavior != 1)) return TC_ERR_INVALID_CONFIG;
    if (!(c.stake > 0) || !std::isfinite(c.stake) || c.take_profit < 0 || c.stop_loss < 0 || c.max_stake < 0 || c.max_daily_loss < 0) return TC_ERR_INVALID_STAKE;
    if (c.martingale_enabled && (!(c.martingale_multiplier >= 1.0) || c.martingale_max_steps < 0 || c.martingale_max_steps > 20)) return TC_ERR_INVALID_CONFIG;
    if (c.trigger_mode != 0 && c.trigger_mode != 1) return TC_ERR_INVALID_CONFIG;
    if (c.trigger_mode == 1) {   // doubled deviation: +-0.5 steps up to +-4.5; its sign must match the required run, 0 can never be in a run
      if (c.trigger_dev2 == 0 || c.trigger_dev2 < -9 || c.trigger_dev2 > 9) return TC_ERR_INVALID_CONFIG;
      if ((c.deviation_direction == 0) != (c.trigger_dev2 > 0)) return TC_ERR_INVALID_CONFIG;
    }
    if (c.s2_dev1 < -9 || c.s2_dev1 > 9 || c.s2_dev2 < -9 || c.s2_dev2 > 9 || c.s2_dev3 < -9 || c.s2_dev3 > 9) return TC_ERR_INVALID_CONFIG;
    if (c.max_consecutive_losses < 0) return TC_ERR_INVALID_CONFIG;
    return 0;
  }
  bool go(int to) { if (!fsm_allowed(p_.fsm, to)) { p_.last_error = TC_ERR_STATE_SYNC_FAILED; return false; } p_.fsm = to; return true; }
  void sync_idle() {
    if (p_.fsm == TC_FSM_MONITORING && p_.bot != TC_BOT_RUNNING) go(TC_FSM_IDLE);
    else if (p_.fsm == TC_FSM_IDLE && p_.bot == TC_BOT_RUNNING) go(TC_FSM_MONITORING);
  }
  void finalize() { p_.last_done = p_.rec; p_.record_seq++; p_.trade_owner = -1; }
  void settle(bool win, double profit) {
    go(TC_FSM_SETTLED); go(TC_FSM_STATE_UPDATE);
    p_.total_trades++; p_.stats_pnl += profit; p_.session_pnl += profit; p_.daily_pnl += profit; p_.last_profit = profit;
    p_.rec.profit = profit; p_.rec.result = win ? TC_RES_WIN : TC_RES_LOSS; p_.last_result = p_.rec.result;
    if (win) {
      p_.wins++; p_.consec_losses = 0; p_.mlevel = 0;
      p_.recovery = p_.cfg.win_behavior == 0 ? 0 : (p_.recovery > 0 ? p_.recovery - 1 : 0);   // explicit, configurable
    } else {
      p_.losses++; p_.consec_losses++;
      if (p_.cfg.martingale_enabled) p_.mlevel++;
      if (p_.recovery < 2) p_.recovery++;                                                    // RECOVERY_2 holds on further losses
    }
    if (p_.trade_owner == 1 && p_.s2_last_applied != p_.rec.trade_id) {          // Strategy 2 transition table, applied once per confirmed result
      p_.s2_last_applied = p_.rec.trade_id;
      static const int kWin[3] = {1, 2, 1}, kLoss[3] = {2, 0, 0};
      int from = p_.s2_trade_idx; if (from < 0 || from > 2) from = 0;
      p_.s2_idx = win ? kWin[from] : kLoss[from];
      if (win) p_.s2_wins++; else p_.s2_losses++;
    }
    if (p_.cfg.loss_dev_filter) {
      if (win) p_.has_restrict = 0;                                   // restriction consumed by an allowed winning trade
      else { p_.restrict_dev2 = (int32_t)(p_.rec.cur_digit - p_.rec.prev_digit); p_.has_restrict = 1; }   // only the latest loss
    }
    p_.open_contract = 0; p_.needs_reconcile = 0; finalize();
    RiskView r{p_.session_pnl, p_.daily_pnl, p_.balance, p_.balance_known, p_.consec_losses, p_.mlevel};
    int e = limit_hit(p_.cfg, r, stake_for(p_.cfg, p_.mlevel));
    if (e) { p_.last_error = e; if (p_.bot == TC_BOT_RUNNING || p_.bot == TC_BOT_PAUSED) p_.bot = TC_BOT_STOPPED; }
    go(p_.bot == TC_BOT_RUNNING ? TC_FSM_MONITORING : TC_FSM_IDLE);
  }
  std::mutex mu_; Persist p_; int pub_ = 0, trd_ = 0, verified_ = 0;
};
}  // namespace tc

using tc::Engine;
extern "C" {
void* engine_create(void) { return new (std::nothrow) Engine(); }
void engine_destroy(void* h) { delete static_cast<Engine*>(h); }
int64_t engine_now_us(void) { return Engine::now_us(); }
int32_t engine_abi_sizes(int64_t* o) { o[0] = sizeof(TcConfig); o[1] = sizeof(TcState); o[2] = sizeof(TcTickResult); o[3] = sizeof(TcRecord); return 4; }
int32_t engine_configure(void* h, const TcConfig* c) { return static_cast<Engine*>(h)->configure(c); }
int32_t engine_command(void* h, int32_t c) { return static_cast<Engine*>(h)->command(c); }
void engine_set_conn(void* h, int32_t k, int32_t s) { static_cast<Engine*>(h)->set_conn(k, s); }
int32_t engine_set_account(void* h, const char* id, int32_t r, const char* cur) { return static_cast<Engine*>(h)->set_account(id, r, cur); }
int32_t engine_on_balance(void* h, const char* l, double b, const char* c) { return static_cast<Engine*>(h)->on_balance(l, b, c); }
void engine_process_tick(void* h, int64_t e, double q, int32_t p, int64_t rx, TcTickResult* o, char* pl, int32_t cap) { static_cast<Engine*>(h)->process_tick(e, q, p, rx, o, pl, cap); }
int32_t engine_on_buy_result(void* h, int64_t t, int32_t ok, int64_t c, double pr, int32_t er, int64_t a) { return static_cast<Engine*>(h)->on_buy_result(t, ok, c, pr, er, a); }
int32_t engine_on_contract_update(void* h, int64_t c, int32_t s, double p, int64_t n) { return static_cast<Engine*>(h)->on_contract_update(c, s, p, n); }
int32_t engine_on_exec_timeout(void* h, int64_t t) { return static_cast<Engine*>(h)->on_exec_timeout(t); }
int32_t engine_reconcile(void* h, int64_t t, int32_t f, int64_t c, int32_t s, double p, int64_t n) { return static_cast<Engine*>(h)->reconcile(t, f, c, s, p, n); }
void engine_report_error(void* h, int32_t c) { static_cast<Engine*>(h)->report_error(c); }
void engine_get_state(void* h, TcState* o) { static_cast<Engine*>(h)->get_state(o); }
int32_t engine_get_last_record(void* h, TcRecord* o) { return static_cast<Engine*>(h)->last_record(o); }
int32_t engine_serialize(void* h, uint8_t* b, int32_t cap) { return static_cast<Engine*>(h)->serialize(b, cap); }
int32_t engine_restore(void* h, const uint8_t* b, int32_t n, int32_t r) { return static_cast<Engine*>(h)->restore(b, n, r); }
}
