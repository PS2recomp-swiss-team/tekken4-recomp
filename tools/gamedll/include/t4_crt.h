// Tekken 4 game DLL: the few C library declarations the generated code needs. The DLL is compiled with clang-cl /X
// (no Visual Studio or Windows SDK headers) and gets these functions from ps2EntryRunner.exe (its static C runtime:
// one implementation for every player, never the PC's ucrtbase.dll).
#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
#define T4_BEGIN extern "C" {
#define T4_END }
#else
#define T4_BEGIN
#define T4_END
#endif
#define T4_CRT
T4_BEGIN
T4_CRT void* memcpy(void*, const void*, size_t);
T4_CRT void* memmove(void*, const void*, size_t);
T4_CRT void* memset(void*, int, size_t);
T4_CRT int memcmp(const void*, const void*, size_t);
T4_CRT size_t strlen(const char*);
T4_CRT int strcmp(const char*, const char*);
T4_CRT char* getenv(const char*);
T4_CRT int atoi(const char*);
T4_CRT void* malloc(size_t);
T4_CRT void free(void*);
T4_CRT void* _aligned_malloc(size_t, size_t);
T4_CRT void _aligned_free(void*);
T4_CRT __declspec(noreturn) void abort(void);
T4_END
