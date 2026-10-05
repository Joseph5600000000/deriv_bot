// Stable C ABI of the Deriv trading core. Only plain C types cross the FFI boundary.
#pragma once
#include <stdint.h>
#include "tc_structs.h"
#ifdef __cplusplus
extern "C" {
#endif
#define TC_API __attribute__((visibility("default")))

enum TcErr { TC_ERR_NONE=0, TC_ERR_PAT_INVALID=1, TC_ERR_PAT_EXPIRED=2, TC_ERR_PAT_SCOPE_MISSING=3,
  TC_ERR_ACCOUNT_NOT_FOUND=4, TC_ERR_OTP_FAILED=5, TC_ERR_WS_DISCONNECTED=6, TC_ERR_WS_TIMEOUT=7,
  TC_ERR_STALE_TICK=8, TC_ERR_TRADE_REJECTED=9, TC_ERR_INSUFFICIENT_BALANCE=10, TC_ERR_INVALID_BARRIER=11,
  TC_ERR_INVALID_STAKE=12, TC_ERR_RISK_LIMIT_REACHED=13, TC_ERR_EXECUTION_TIMEOUT=14, TC_ERR_STATE_SYNC_FAILED=15,
  TC_ERR_ACCOUNT_MISMATCH=16, TC_ERR_NOT_READY=17, TC_ERR_BUSY=18, TC_ERR_STRATEGY_DISABLED=19,
  TC_ERR_EMERGENCY_STOP=20, TC_ERR_INVALID_CONFIG=21, TC_ERR_DUPLICATE_TICK=22, TC_ERR_NETWORK=23,
  TC_ERR_UNKNOWN=24, TC_ERR_BAD_SNAPSHOT=25 };
enum TcConn { TC_CONN_DISCONNECTED=0, TC_CONN_RECONNECTING=1, TC_CONN_AUTHENTICATING=2, TC_CONN_SYNCHRONIZING=3,
  TC_CONN_CONNECTED=4, TC_CONN_DEGRADED=5, TC_CONN_READY=6, TC_CONN_ERROR=7 };
enum TcBot { TC_BOT_STOPPED=0, TC_BOT_RUNNING=1, TC_BOT_PAUSED=2, TC_BOT_EMERGENCY=3 };
enum TcFsm { TC_FSM_IDLE=0, TC_FSM_MONITORING=1, TC_FSM_TRIGGER_DETECTED=2, TC_FSM_VALIDATING=3,
  TC_FSM_EXECUTING=4, TC_FSM_OPEN=5, TC_FSM_SETTLED=6, TC_FSM_STATE_UPDATE=7 };
enum TcCmd { TC_CMD_START=1, TC_CMD_PAUSE=2, TC_CMD_STOP=3, TC_CMD_EMERGENCY_STOP=4, TC_CMD_CLEAR_EMERGENCY=5,
  TC_CMD_RESET_ANALYSIS=6, TC_CMD_RESET_STRATEGY=7, TC_CMD_CLEAR_HISTORY=8 };
enum TcResult { TC_RES_NONE=0, TC_RES_WIN=1, TC_RES_LOSS=2, TC_RES_REJECTED=3, TC_RES_UNCONFIRMED=4 };
enum TcAction { TC_ACT_NONE=0, TC_ACT_EXECUTE=1, TC_ACT_BLOCKED=2, TC_ACT_FILTERED=3 };

TC_API void*   engine_create(void);                       /* initialize_engine */
TC_API void    engine_destroy(void* h);                   /* shutdown_engine   */
TC_API int64_t engine_now_us(void);                       /* monotonic clock   */
TC_API int32_t engine_abi_sizes(int64_t* out4);           /* cfg,state,tickres,record */
TC_API int32_t engine_configure(void* h, const TcConfig* c);          /* configure_strategy */
TC_API int32_t engine_command(void* h, int32_t cmd);
TC_API void    engine_set_conn(void* h, int32_t kind /*0 public,1 trade*/, int32_t state);
TC_API int32_t engine_set_account(void* h, const char* id, int32_t is_real, const char* currency);
TC_API int32_t engine_on_balance(void* h, const char* loginid, double balance, const char* currency);
TC_API void    engine_process_tick(void* h, int64_t epoch, double quote, int32_t pip, int64_t rx_us,
                                   TcTickResult* out, char* payload, int32_t cap);   /* process_tick+get_signal+execute */
TC_API int32_t engine_on_buy_result(void* h, int64_t trade_id, int32_t ok, int64_t contract_id,
                                    double buy_price, int32_t err, int64_t ack_us);
TC_API int32_t engine_on_contract_update(void* h, int64_t contract_id, int32_t status /*0 open,1 won,2 lost*/,
                                         double profit, int64_t now_us);
TC_API int32_t engine_on_exec_timeout(void* h, int64_t trade_id);
TC_API int32_t engine_reconcile(void* h, int64_t trade_id, int32_t found, int64_t contract_id,
                                int32_t status, double profit, int64_t now_us);
TC_API void    engine_report_error(void* h, int32_t code);
TC_API void    engine_get_state(void* h, TcState* out);                /* get_engine_state */
TC_API int32_t engine_get_last_record(void* h, TcRecord* out);
TC_API int32_t engine_serialize(void* h, uint8_t* buf, int32_t cap);
TC_API int32_t engine_restore(void* h, const uint8_t* buf, int32_t size, int32_t resume_running);
#ifdef __cplusplus
}
#endif
