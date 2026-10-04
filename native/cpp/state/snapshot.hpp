#pragma once
#include <stdint.h>
#include <string.h>
namespace tc {
constexpr uint32_t kSnapMagic = 0x4E534354u;   // "TCSN"
constexpr uint32_t kSnapVersion = 1;
struct SnapHeader { uint32_t magic, version, size, checksum; };
inline uint32_t fnv1a(const uint8_t* p, size_t n) {
  uint32_t h = 2166136261u; for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 16777619u; } return h;
}
}
