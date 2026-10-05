// App-wide constants. The App ID is NOT a secret (Deriv requires it as the Deriv-App-ID header for PAT apps);
// override at build time with --dart-define=DERIV_APP_ID=... if needed. The PAT is never stored here.
const String kDerivAppId = String.fromEnvironment('DERIV_APP_ID', defaultValue: '34ngJDQGWOLVM9Qoamb4');
const String kRestBase = 'https://api.derivws.com';
const String kPublicWs = 'wss://api.derivws.com/trading/v1/options/ws/public';
const List<String> kSymbols = ['R_10', 'R_25', 'R_50', 'R_75', 'R_100'];
const List<String> kMarketNames = ['Volatility 10', 'Volatility 25', 'Volatility 50', 'Volatility 75', 'Volatility 100'];

// Must mirror native/cpp/engine/engine_api.h
class Err {
  static const int none = 0, patInvalid = 1, patExpired = 2, patScopeMissing = 3, accountNotFound = 4, otpFailed = 5,
      wsDisconnected = 6, wsTimeout = 7, staleTick = 8, tradeRejected = 9, insufficientBalance = 10,
      invalidBarrier = 11, invalidStake = 12, riskLimit = 13, executionTimeout = 14, stateSyncFailed = 15,
      accountMismatch = 16, notReady = 17, busy = 18, strategyDisabled = 19, emergencyStop = 20,
      invalidConfig = 21, duplicateTick = 22, network = 23, unknown = 24, badSnapshot = 25;
}
class Conn {
  static const int disconnected = 0, reconnecting = 1, authenticating = 2, synchronizing = 3, connected = 4,
      degraded = 5, ready = 6, error = 7;
  static const names = ['DISCONNECTED', 'RECONNECTING', 'AUTHENTICATING', 'SYNCHRONIZING', 'CONNECTED', 'DEGRADED', 'READY', 'ERROR'];
}
class Bot {
  static const int stopped = 0, running = 1, paused = 2, emergency = 3;
  static const names = ['STOPPED', 'RUNNING', 'PAUSED', 'EMERGENCY'];
}
class Fsm {
  static const int idle = 0, monitoring = 1, triggerDetected = 2, validating = 3, executing = 4, open = 5, settled = 6, stateUpdate = 7;
  static const names = ['IDLE', 'MONITORING', 'TRIGGER_DETECTED', 'VALIDATING', 'EXECUTING', 'OPEN', 'SETTLED', 'STATE_UPDATE'];
}
class Cmd {
  static const int start = 1, pause = 2, stop = 3, emergencyStop = 4, clearEmergency = 5, resetAnalysis = 6, resetStrategy = 7, clearHistory = 8;
}
const List<String> kResultNames = ['-', 'WIN', 'LOSS', 'REJECTED', 'UNCONFIRMED'];
