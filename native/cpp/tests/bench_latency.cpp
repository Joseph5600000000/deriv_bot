// Measures tick -> execute-payload time inside the C++ core (excludes network). Run via run_bench.sh
#include <stdio.h>
#include <algorithm>
#include <vector>
#include "../engine/engine_api.h"
int main() {
  void* h = engine_create(); TcConfig c{}; c.market=4; c.initial_barrier=4; c.recovery_barrier1=6; c.recovery_barrier2=8;
  c.trigger_digit=8; c.consecutive_count=2; c.stake=1; engine_configure(h, &c);
  engine_set_account(h, "VRTC1", 0, "USD"); engine_set_conn(h,0,6); engine_set_conn(h,1,6); engine_on_balance(h,"VRTC1",1e6,"USD");
  engine_command(h, TC_CMD_START);
  std::vector<double> us; char pl[1024]; TcTickResult r; int64_t ep = 1; const int seq[3] = {0, 7, 8};
  for (int i = 0; i < 20000; i++) {
    for (int k = 0; k < 3; k++) {
      int64_t t0 = engine_now_us(); engine_process_tick(h, ++ep, 1230.0 + seq[k] / 100.0, 2, t0, &r, pl, sizeof pl);
      if (r.action == TC_ACT_EXECUTE) { us.push_back((double)(engine_now_us() - t0)); engine_on_buy_result(h, r.trade_id, 1, i + 1, 1, 0, 0); engine_on_contract_update(h, i + 1, 1, 0.9, 0); }
    }
  }
  std::sort(us.begin(), us.end());
  printf("trades=%zu  tick->payload  median=%.1fus  p99=%.1fus  max=%.1fus\n", us.size(), us[us.size()/2], us[us.size()*99/100], us.back());
  engine_destroy(h); return 0; }
