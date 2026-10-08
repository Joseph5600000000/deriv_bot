import '../ffi/tc_structs.dart';

class StrategyConfig {
  int triggerMode; // 0 = Trigger Digit, 1 = Deviation Trigger
  double triggerDeviation; // signed, e.g. +0.5 / -1.5 (steps of 0.5)
  int market, direction, recoveryDirection1, recoveryDirection2, initialBarrier, recoveryBarrier1, recoveryBarrier2, triggerDigit, consecutiveCount,
      deviationDirection, martingaleMaxSteps, maxConsecutiveLosses, winBehavior;
  bool martingale, lossDevFilter;
  double stake, takeProfit, stopLoss, multiplier, maxStake, maxDailyLoss;

  StrategyConfig({
    this.triggerMode = 0, this.triggerDeviation = 0.5, this.market = 4, this.direction = 0, this.recoveryDirection1 = 0, this.recoveryDirection2 = 0, this.initialBarrier = 4, this.recoveryBarrier1 = 6, this.recoveryBarrier2 = 8,
    this.triggerDigit = 3, this.consecutiveCount = 2, this.deviationDirection = 0, this.martingaleMaxSteps = 3,
    this.maxConsecutiveLosses = 5, this.winBehavior = 0, this.martingale = false, this.lossDevFilter = false, this.stake = 1.0,
    this.takeProfit = 0, this.stopLoss = 0, this.multiplier = 2.0, this.maxStake = 50, this.maxDailyLoss = 20,
  });

  StrategyConfig copy() => StrategyConfig.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'triggerMode': triggerMode, 'triggerDeviation': triggerDeviation, 'market': market, 'direction': direction, 'recoveryDirection1': recoveryDirection1, 'recoveryDirection2': recoveryDirection2, 'initialBarrier': initialBarrier,
        'recoveryBarrier1': recoveryBarrier1, 'recoveryBarrier2': recoveryBarrier2, 'triggerDigit': triggerDigit,
        'consecutiveCount': consecutiveCount, 'deviationDirection': deviationDirection,
        'martingaleMaxSteps': martingaleMaxSteps, 'maxConsecutiveLosses': maxConsecutiveLosses,
        'winBehavior': winBehavior, 'martingale': martingale, 'lossDevFilter': lossDevFilter, 'stake': stake, 'takeProfit': takeProfit,
        'stopLoss': stopLoss, 'multiplier': multiplier, 'maxStake': maxStake, 'maxDailyLoss': maxDailyLoss,
      };

  factory StrategyConfig.fromJson(Map j) {
    final d = StrategyConfig();
    int i(String k, int dv) => (j[k] as num?)?.toInt() ?? dv;
    double f(String k, double dv) => (j[k] as num?)?.toDouble() ?? dv;
    return StrategyConfig(
      triggerMode: i('triggerMode', 0), triggerDeviation: f('triggerDeviation', d.triggerDeviation),
      market: i('market', d.market), direction: i('direction', d.direction),
      recoveryDirection1: i('recoveryDirection1', i('direction', d.direction)), recoveryDirection2: i('recoveryDirection2', i('direction', d.direction)),
      initialBarrier: i('initialBarrier', d.initialBarrier), recoveryBarrier1: i('recoveryBarrier1', d.recoveryBarrier1),
      recoveryBarrier2: i('recoveryBarrier2', d.recoveryBarrier2), triggerDigit: i('triggerDigit', d.triggerDigit),
      consecutiveCount: i('consecutiveCount', d.consecutiveCount), deviationDirection: i('deviationDirection', d.deviationDirection),
      martingaleMaxSteps: i('martingaleMaxSteps', d.martingaleMaxSteps),
      maxConsecutiveLosses: i('maxConsecutiveLosses', d.maxConsecutiveLosses), winBehavior: i('winBehavior', d.winBehavior),
      martingale: j['martingale'] == true, lossDevFilter: j['lossDevFilter'] == true, stake: f('stake', d.stake), takeProfit: f('takeProfit', d.takeProfit),
      stopLoss: f('stopLoss', d.stopLoss), multiplier: f('multiplier', d.multiplier), maxStake: f('maxStake', d.maxStake),
      maxDailyLoss: f('maxDailyLoss', d.maxDailyLoss),
    );
  }

  /// Text like "+0.5" or "-1.5". Returns null when it is not an exact multiple of 0.5 in [-4.5, 4.5] or its sign
  /// contradicts the deviation direction (a positive run can never end on a negative deviation).
  String? deviationProblem(double v) {
    if (v.isNaN || (v * 2) != (v * 2).roundToDouble()) return 'Deviation must be a multiple of 0.5 (e.g. +0.5, -1.5).';
    if (v == 0 || v.abs() > 4.5) return 'Deviation must be between 0.5 and 4.5 (plus or minus).';
    if ((deviationDirection == 0) != (v > 0)) return deviationDirection == 0 ? 'Positive direction needs a positive deviation (e.g. +0.5).' : 'Negative direction needs a negative deviation (e.g. -1.5).';
    return null;
  }

  void writeTo(TcConfig c) {
    c.trigger_mode = triggerMode; c.trigger_dev2 = (triggerDeviation * 2).round(); // exact: deviations are multiples of 0.5
    c.market = market; c.direction = direction; c.recovery_direction1 = recoveryDirection1; c.recovery_direction2 = recoveryDirection2; c.initial_barrier = initialBarrier;
    c.recovery_barrier1 = recoveryBarrier1; c.recovery_barrier2 = recoveryBarrier2; c.trigger_digit = triggerDigit;
    c.consecutive_count = consecutiveCount; c.deviation_direction = deviationDirection;
    c.martingale_enabled = martingale ? 1 : 0; c.martingale_max_steps = martingaleMaxSteps;
    c.max_consecutive_losses = maxConsecutiveLosses; c.win_behavior = winBehavior; c.loss_dev_filter = lossDevFilter ? 1 : 0;
    c.stake = stake; c.take_profit = takeProfit; c.stop_loss = stopLoss; c.martingale_multiplier = multiplier;
    c.max_stake = maxStake; c.max_daily_loss = maxDailyLoss;
  }
}
