#pragma once
#include <stdint.h>
#include <math.h>
namespace tc {
// Last digit of the quote, using the symbol's pip_size so trailing zeros are respected.
inline int extract_digit(double quote, int pip) {
  if (!(quote > 0) || pip < 0 || pip > 8) return -1;
  double scale = 1; for (int i = 0; i < pip; i++) scale *= 10;
  long long v = llround(quote * scale);
  return (int)(v % 10);
}
// Exactly two latest digits. Average=(prev+cur)/2, Deviation=cur-Average (sign preserved).
struct RollingWindow {
  int32_t prev = -1, cur = -1, sign = 0, consec_pos = 0, consec_neg = 0, has_dev = 0;
  double average = 0, deviation = 0;
  void reset() { *this = RollingWindow(); }
  void push(int digit) {
    prev = cur; cur = digit;
    if (prev < 0) return;
    average = (prev + cur) / 2.0;
    deviation = cur - average;
    sign = (cur > prev) - (cur < prev);            // exact integer sign
    has_dev = 1;
    if (sign > 0)      { consec_pos++; consec_neg = 0; }
    else if (sign < 0) { consec_neg++; consec_pos = 0; }
    else               { consec_pos = 0; consec_neg = 0; }   // ZERO breaks any sequence
  }
};
}
