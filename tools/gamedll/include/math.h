#pragma once
// Only operations the compiler turns into exact instructions (sqrt, fabs, copysign, the SSE4.1 roundings or exact
// SSE2 sequences): never a C runtime math call, so every player computes the same bits.
#ifdef __cplusplus
extern "C" {
#endif
static inline float sqrtf(float x) { return __builtin_sqrtf(x); }
static inline double sqrt(double x) { return __builtin_sqrt(x); }
static inline float fabsf(float x) { return __builtin_fabsf(x); }
static inline double fabs(double x) { return __builtin_fabs(x); }
static inline float copysignf(float x, float y) { return __builtin_copysignf(x, y); }
#ifdef __cplusplus
}
#endif
