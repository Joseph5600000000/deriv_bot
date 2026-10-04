#pragma once
#include "../engine/engine_api.h"
namespace tc {
// Deterministic trade state machine. Anything not listed is an invalid transition and is rejected.
inline bool fsm_allowed(int from, int to) {
  switch (from) {
    case TC_FSM_IDLE:             return to == TC_FSM_MONITORING;
    case TC_FSM_MONITORING:       return to == TC_FSM_TRIGGER_DETECTED || to == TC_FSM_IDLE;
    case TC_FSM_TRIGGER_DETECTED: return to == TC_FSM_VALIDATING;
    case TC_FSM_VALIDATING:       return to == TC_FSM_EXECUTING || to == TC_FSM_MONITORING;
    case TC_FSM_EXECUTING:        return to == TC_FSM_OPEN || to == TC_FSM_MONITORING || to == TC_FSM_IDLE;
    case TC_FSM_OPEN:             return to == TC_FSM_SETTLED;
    case TC_FSM_SETTLED:          return to == TC_FSM_STATE_UPDATE;
    case TC_FSM_STATE_UPDATE:     return to == TC_FSM_MONITORING || to == TC_FSM_IDLE;
  }
  return false;
}
}
