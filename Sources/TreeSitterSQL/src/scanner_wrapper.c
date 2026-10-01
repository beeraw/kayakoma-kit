// Compiles the grammar's external scanner, kept unchanged, without the
// implicit conversion warnings that the default build flags raise in it.
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#include "scanner.c"
