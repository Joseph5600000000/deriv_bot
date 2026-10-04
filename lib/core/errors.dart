import 'constants.dart';

class ErrInfo {
  final String name, message, action;
  const ErrInfo(this.name, this.message, this.action);
}

const Map<int, ErrInfo> kErrors = {
  Err.patInvalid: ErrInfo('PAT_INVALID', 'Deriv rejected this token.', 'Re-copy the Personal Access Token from your Deriv account and check the App ID is a PAT app.'),
  Err.patExpired: ErrInfo('PAT_EXPIRED', 'This token has expired.', 'Create a new PAT in your Deriv account and paste it again.'),
  Err.patScopeMissing: ErrInfo('PAT_SCOPE_MISSING', 'The token lacks the required scope.', 'Create a PAT with the "trade" scope (and "account_manage" if you need it).'),
  Err.accountNotFound: ErrInfo('ACCOUNT_NOT_FOUND', 'No matching Options account was found.', 'Check the token belongs to an account with an Options (Demo/Real) account.'),
  Err.otpFailed: ErrInfo('OTP_FAILED', 'Could not obtain a WebSocket OTP.', 'Retrying automatically. If it persists, check the PAT scopes and App ID.'),
  Err.wsDisconnected: ErrInfo('WEBSOCKET_DISCONNECTED', 'The trading connection is down.', 'Reconnecting automatically; trading resumes only when READY.'),
  Err.wsTimeout: ErrInfo('WEBSOCKET_TIMEOUT', 'The connection stopped responding.', 'Reconnecting automatically.'),
  Err.staleTick: ErrInfo('STALE_TICK', 'No fresh ticks are arriving.', 'Trading is blocked until ticks resume. Check your network.'),
  Err.tradeRejected: ErrInfo('TRADE_REJECTED', 'Deriv rejected the trade.', 'Bot paused. Review the message, then press START.'),
  Err.insufficientBalance: ErrInfo('INSUFFICIENT_BALANCE', 'Balance is lower than the stake.', 'Lower the stake or top up the account.'),
  Err.invalidBarrier: ErrInfo('INVALID_BARRIER', 'Barrier invalid for this direction.', 'OVER allows 0-8, UNDER allows 1-9.'),
  Err.invalidStake: ErrInfo('INVALID_STAKE', 'Stake is not valid.', 'Enter a positive stake.'),
  Err.riskLimit: ErrInfo('RISK_LIMIT_REACHED', 'A risk limit stopped the bot.', 'Review limits; press START for a new session when ready.'),
  Err.executionTimeout: ErrInfo('EXECUTION_TIMEOUT', 'No confirmation for the last buy.', 'Reconciling with Deriv; bot paused until resolved.'),
  Err.stateSyncFailed: ErrInfo('STATE_SYNC_FAILED', 'Could not confirm the last contract.', 'Check Deriv statement/balance, then press START.'),
  Err.accountMismatch: ErrInfo('ACCOUNT_MISMATCH', 'Connected account differs from the selected one.', 'Re-select the account. No trade was sent.'),
  Err.notReady: ErrInfo('NOT_READY', 'Connections are not READY.', 'Wait for both connections to show READY.'),
  Err.busy: ErrInfo('BUSY', 'A trade is in progress.', 'Wait for the open contract to settle.'),
  Err.emergencyStop: ErrInfo('EMERGENCY_STOP', 'Emergency stop is latched.', 'Clear the emergency stop explicitly to continue.'),
  Err.invalidConfig: ErrInfo('INVALID_CONFIG', 'Strategy settings are out of range.', 'Check every field.'),
  Err.network: ErrInfo('NETWORK_ERROR', 'Network problem.', 'Check your internet connection and retry.'),
  Err.badSnapshot: ErrInfo('BAD_SNAPSHOT', 'Saved state was unusable.', 'Starting fresh; nothing was traded from it.'),
  Err.unknown: ErrInfo('UNKNOWN', 'Unexpected error.', 'See technical details.'),
};

ErrInfo errInfo(int code) => kErrors[code] ?? kErrors[Err.unknown]!;

class DerivException implements Exception {
  final int code;
  final String technical;
  final bool retryable;
  DerivException(this.code, this.technical, {this.retryable = false});
  @override
  String toString() => '${errInfo(code).name}: $technical';
}
