import 'package:flutter_test/flutter_test.dart';
import 'package:deriv_bot/models/strategy_config.dart';

void main() {
  test('strategy config JSON round trip keeps every field', () {
    final c = StrategyConfig(stake: 2.5, martingale: true, multiplier: 2.2, initialBarrier: 3, triggerDigit: 8);
    final r = StrategyConfig.fromJson(c.toJson());
    expect(r.stake, 2.5); expect(r.martingale, true); expect(r.multiplier, 2.2);
    expect(r.initialBarrier, 3); expect(r.triggerDigit, 8);
  });
}
