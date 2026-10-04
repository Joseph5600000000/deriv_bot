#pragma once
#include "../engine/tc_structs.h"
#include "../engine/engine_api.h"
#include "../strategy/strategy.hpp"
namespace tc {
struct RiskView { double session_pnl, daily_pnl, balance; int32_t balance_known, consec_losses, mlevel; };
inline bool is_halting(int err) { return err == TC_ERR_RISK_LIMIT_REACHED; }
// Limits that must stop the bot. Enforced here (C++), never only in the UI.
inline int limit_hit(const TcConfig& c, const RiskView& r, double next_stake) {
  if (c.max_stake > 0 && next_stake > c.max_stake + 1e-9) return TC_ERR_RISK_LIMIT_REACHED;
  if (c.martingale_enabled && r.mlevel > c.martingale_max_steps) return TC_ERR_RISK_LIMIT_REACHED;
  if (c.max_consecutive_losses > 0 && r.consec_losses >= c.max_consecutive_losses) return TC_ERR_RISK_LIMIT_REACHED;
  if (c.max_daily_loss > 0 && -r.daily_pnl >= c.max_daily_loss) return TC_ERR_RISK_LIMIT_REACHED;
  if (c.stop_loss > 0 && -r.session_pnl >= c.stop_loss) return TC_ERR_RISK_LIMIT_REACHED;
  if (c.take_profit > 0 && r.session_pnl >= c.take_profit) return TC_ERR_RISK_LIMIT_REACHED;
  return 0;
}
inline int pre_trade(const TcConfig& c, const RiskView& r, double stake) {
  if (!(stake > 0) || !std::isfinite(stake)) return TC_ERR_INVALID_STAKE;
  int e = limit_hit(c, r, stake); if (e) return e;
  if (r.balance_known && stake > r.balance + 1e-9) return TC_ERR_INSUFFICIENT_BALANCE;
  return 0;
}
}
