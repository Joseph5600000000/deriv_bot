import '../ffi/tc_structs.dart';

class StrategyConfig {
  int market, direction, initialBarrier, recoveryBarrier1, recoveryBarrier2, triggerDigit, consecutiveCount,
      deviationDirection, martingaleMaxSteps, maxConsecutiveLosses, winBehavior;
  bool martingale;
  double stake, takeProfit, stopLoss, multiplier, maxStake, maxDailyLoss;

  StrategyConfig({
    this.market = 4, this.direction = 0, this.initialBarrier = 4, this.recoveryBarrier1 = 6, this.recoveryBarrier2 = 8,
    this.triggerDigit = 3, this.consecutiveCount = 2, this.deviationDirection = 0, this.martingaleMaxSteps = 3,
    this.maxConsecutiveLosses = 5, this.winBehavior = 0, this.martingale = false, this.stake = 1.0,
    this.takeProfit = 0, this.stopLoss = 0, this.multiplier = 2.0, this.maxStake = 50, this.maxDailyLoss = 20,
  });

  StrategyConfig copy() => StrategyConfig.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'market': market, 'direction': direction, 'initialBarrier': initialBarrier,
        'recoveryBarrier1': recoveryBarrier1, 'recoveryBarrier2': recoveryBarrier2, 'triggerDigit': triggerDigit,
        'consecutiveCount': consecutiveCount, 'deviationDirection': deviationDirection,
        'martingaleMaxSteps': martingaleMaxSteps, 'maxConsecutiveLosses': maxConsecutiveLosses,
        'winBehavior': winBehavior, 'martingale': martingale, 'stake': stake, 'takeProfit': takeProfit,
        'stopLoss': stopLoss, 'multiplier': multiplier, 'maxStake': maxStake, 'maxDailyLoss': maxDailyLoss,
      };

  factory StrategyConfig.fromJson(Map j) {
    final d = StrategyConfig();
    int i(String k, int dv) => (j[k] as num?)?.toInt() ?? dv;
    double f(String k, double dv) => (j[k] as num?)?.toDouble() ?? dv;
    return StrategyConfig(
      market: i('market', d.market), direction: i('direction', d.direction),
      initialBarrier: i('initialBarrier', d.initialBarrier), recoveryBarrier1: i('recoveryBarrier1', d.recoveryBarrier1),
      recoveryBarrier2: i('recoveryBarrier2', d.recoveryBarrier2), triggerDigit: i('triggerDigit', d.triggerDigit),
      consecutiveCount: i('consecutiveCount', d.consecutiveCount), deviationDirection: i('deviationDirection', d.deviationDirection),
      martingaleMaxSteps: i('martingaleMaxSteps', d.martingaleMaxSteps),
      maxConsecutiveLosses: i('maxConsecutiveLosses', d.maxConsecutiveLosses), winBehavior: i('winBehavior', d.winBehavior),
      martingale: j['martingale'] == true, stake: f('stake', d.stake), takeProfit: f('takeProfit', d.takeProfit),
      stopLoss: f('stopLoss', d.stopLoss), multiplier: f('multiplier', d.multiplier), maxStake: f('maxStake', d.maxStake),
      maxDailyLoss: f('maxDailyLoss', d.maxDailyLoss),
    );
  }

  void writeTo(TcConfig c) {
    c.market = market; c.direction = direction; c.initial_barrier = initialBarrier;
    c.recovery_barrier1 = recoveryBarrier1; c.recovery_barrier2 = recoveryBarrier2; c.trigger_digit = triggerDigit;
    c.consecutive_count = consecutiveCount; c.deviation_direction = deviationDirection;
    c.martingale_enabled = martingale ? 1 : 0; c.martingale_max_steps = martingaleMaxSteps;
    c.max_consecutive_losses = maxConsecutiveLosses; c.win_behavior = winBehavior;
    c.stake = stake; c.take_profit = takeProfit; c.stop_loss = stopLoss; c.martingale_multiplier = multiplier;
    c.max_stake = maxStake; c.max_daily_loss = maxDailyLoss;
  }
}
