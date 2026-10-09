#pragma once
#include <cmath>
#include "../engine/tc_structs.h"
#include "../analysis/rolling_window.hpp"
namespace tc {
// OVER 9 and UNDER 0 can never win/exist, so they are rejected here, before execution.
inline bool barrier_ok(int dir, int64_t b) { return dir == 0 ? (b >= 0 && b <= 8) : (b >= 1 && b <= 9); }
inline int64_t barrier_for(const TcConfig& c, int level) {
  return level == 0 ? c.initial_barrier : level == 1 ? c.recovery_barrier1 : c.recovery_barrier2;
}
inline int64_t direction_for(const TcConfig& c, int level) {
  return level == 0 ? c.direction : level == 1 ? c.recovery_direction1 : c.recovery_direction2;
}
inline int64_t s2_dev_for(const TcConfig& c, int idx) { return idx == 0 ? c.s2_dev1 : idx == 1 ? c.s2_dev2 : c.s2_dev3; }   // doubled deviation (cur-prev)
// Trigger = required consecutive run in the chosen direction AND the final-deviation condition of the active mode:
//   mode 0 (Trigger Digit):      current digit == trigger digit            (original behaviour, unchanged)
//   mode 1 (Deviation Trigger):  signed deviation == configured deviation  (exact: compared as doubled integer cur-prev,
//                                                                           so +1.5 and -1.5 differ and nothing is rounded)
inline bool qualified(const TcConfig& c, const RollingWindow& w) {
  if (!w.has_dev) return false;
  int run = c.deviation_direction == 0 ? w.consec_pos : w.consec_neg;
  if (run < c.consecutive_count) return false;
  if (c.trigger_mode == 1) return (int64_t)(w.cur - w.prev) == c.trigger_dev2;
  return w.cur == c.trigger_digit;
}
inline double round2(double v) { return std::round(v * 100.0) / 100.0; }
inline double stake_for(const TcConfig& c, int mlevel) {
  double s = c.stake;
  if (c.martingale_enabled) for (int i = 0; i < mlevel && i < 64; i++) s *= c.martingale_multiplier;
  return round2(s);
}
}
