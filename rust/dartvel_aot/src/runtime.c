/* dartvel_aot runtime (not a ported file). Every function is static, so a
 * helper no reachable code calls is not in the binary. Memory is never
 * freed in this increment: programs are short-lived (see README). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct V { int64_t c; union { int64_t i; void *p; } u; } V;
typedef struct Str { int64_t n; char s[]; } Str;
typedef struct List { int64_t n, cap; V *a; } List;
typedef struct Map { int64_t n, cap, live, icap; V *k, *v; char *dead; int64_t *ix; } Map;

#define C_ABSENT (-1)
static const V NUL = {CID_NULL, {0}};
static const V ABSENT = {C_ABSENT, {0}};
#define S(v) ((Str *)(v).u.p)
#define L(v) ((List *)(v).u.p)
#define M(v) ((Map *)(v).u.p)
#define F(v) ((V *)(v).u.p)

static inline V mkint(int64_t i) { V v; v.c = CID_INT; v.u.i = i; return v; }
static inline V mkbool(int b) { V v; v.c = CID_BOOL; v.u.i = b != 0; return v; }
static inline V mkptr(int64_t c, void *p) { V v; v.c = c; v.u.p = p; return v; }

static void *dv_alloc(size_t n) {
  void *p = calloc(1, n ? n : 1);
  if (!p) { fputs("Out of memory\n", stderr); exit(255); }
  return p;
}

static void dv_throw(const char *message) {
  fflush(stdout);
  fprintf(stderr, "Unhandled exception:\n%s\n", message);
  exit(255);
}

static V dv_throw_str(V message) {
  fflush(stdout);
  fputs("Unhandled exception:\n", stderr);
  if (message.c == CID_STRING) fwrite(S(message)->s, 1, S(message)->n, stderr);
  fputc('\n', stderr);
  exit(255);
}

static V dv_nsm(const char *selector, V receiver) {
  char buffer[200];
  snprintf(buffer, sizeof buffer, "NoSuchMethodError: Class id %lld has no instance member '%s'.",
           (long long)receiver.c, selector);
  dv_throw(buffer);
  return NUL;
}

static void dv_cast_fail(V value) {
  (void)value;
  dv_throw("TypeError: a value failed an `as` cast");
}

static int dv_truth(V v) {
  if (v.c != CID_BOOL) dv_throw("TypeError: a condition is not a bool");
  return (int)v.u.i;
}

static int64_t dv_int(V v) {
  if (v.c != CID_INT) dv_throw("TypeError: an operand is not an int");
  return v.u.i;
}

static Str *dv_str_check(V v) {
  if (v.c != CID_STRING) dv_throw("TypeError: a value is not a String");
  return S(v);
}

static V dv_str_new(int64_t n) {
  Str *s = dv_alloc(sizeof(Str) + (size_t)n + 1);
  s->n = n;
  return mkptr(CID_STRING, s);
}

static V dv_str_from(const char *text, int64_t n) {
  V v = dv_str_new(n);
  memcpy(S(v)->s, text, (size_t)n);
  return v;
}

static V dv_concatn(int count, V *parts) {
  int64_t n = 0;
  for (int i = 0; i < count; i++) n += dv_str_check(parts[i])->n;
  V out = dv_str_new(n);
  char *at = S(out)->s;
  for (int i = 0; i < count; i++) { memcpy(at, S(parts[i])->s, (size_t)S(parts[i])->n); at += S(parts[i])->n; }
  return out;
}

static int dv_eq(V a, V b) {
  if (a.c != b.c) return 0;
  if (a.c == CID_INT || a.c == CID_BOOL) return a.u.i == b.u.i;
  if (a.c == CID_NULL) return 1;
  if (a.c == CID_STRING) return S(a)->n == S(b)->n && memcmp(S(a)->s, S(b)->s, (size_t)S(a)->n) == 0;
  return a.u.p == b.u.p;
}

static uint64_t dv_hash(V v) {
  uint64_t h;
  if (v.c == CID_STRING) {
    h = 1469598103934665603ULL;
    for (int64_t i = 0; i < S(v)->n; i++) h = (h ^ (unsigned char)S(v)->s[i]) * 1099511628211ULL;
  } else if (v.c == CID_INT || v.c == CID_BOOL) {
    h = (uint64_t)v.u.i * 0x9E3779B97F4A7C15ULL;
  } else if (v.c == CID_NULL) {
    h = 0;
  } else {
    h = (uint64_t)(uintptr_t)v.u.p * 0x9E3779B97F4A7C15ULL;
  }
  return h ^ (h >> 29);
}

static V dv_add(V a, V b) {
  if (a.c == CID_INT && b.c == CID_INT) return mkint((int64_t)((uint64_t)a.u.i + (uint64_t)b.u.i));
  if (a.c == CID_STRING && b.c == CID_STRING) { V parts[2] = {a, b}; return dv_concatn(2, parts); }
  dv_throw("NoSuchMethodError: operator + is not defined for these operands");
  return NUL;
}
static V dv_sub(V a, V b) { return mkint((int64_t)((uint64_t)dv_int(a) - (uint64_t)dv_int(b))); }
static V dv_mul(V a, V b) { return mkint((int64_t)((uint64_t)dv_int(a) * (uint64_t)dv_int(b))); }
static V dv_tdiv(V a, V b) {
  int64_t x = dv_int(a), y = dv_int(b);
  if (y == 0) dv_throw("IntegerDivisionByZeroException");
  if (x == INT64_MIN && y == -1) return mkint(INT64_MIN);
  return mkint(x / y);
}
static V dv_mod(V a, V b) {
  int64_t x = dv_int(a), y = dv_int(b);
  if (y == 0) dv_throw("IntegerDivisionByZeroException");
  if (y == -1) return mkint(0);
  int64_t r = x % y;
  if (r < 0) r += y < 0 ? -y : y;
  return mkint(r);
}
static V dv_lt(V a, V b) { return mkbool(dv_int(a) < dv_int(b)); }
static V dv_le(V a, V b) { return mkbool(dv_int(a) <= dv_int(b)); }
static V dv_gt(V a, V b) { return mkbool(dv_int(a) > dv_int(b)); }
static V dv_ge(V a, V b) { return mkbool(dv_int(a) >= dv_int(b)); }
static V dv_band(V a, V b) {
  if (a.c == CID_BOOL && b.c == CID_BOOL) return mkbool(a.u.i & b.u.i);
  return mkint(dv_int(a) & dv_int(b));
}
static V dv_bor(V a, V b) {
  if (a.c == CID_BOOL && b.c == CID_BOOL) return mkbool(a.u.i | b.u.i);
  return mkint(dv_int(a) | dv_int(b));
}
static V dv_bxor(V a, V b) {
  if (a.c == CID_BOOL && b.c == CID_BOOL) return mkbool(a.u.i ^ b.u.i);
  return mkint(dv_int(a) ^ dv_int(b));
}
static V dv_shl(V a, V b) {
  int64_t x = dv_int(a), y = dv_int(b);
  if (y < 0) dv_throw("ArgumentError: negative shift count");
  return mkint(y >= 64 ? 0 : (int64_t)((uint64_t)x << y));
}
static V dv_shr(V a, V b) {
  int64_t x = dv_int(a), y = dv_int(b);
  if (y < 0) dv_throw("ArgumentError: negative shift count");
  return mkint(x >> (y >= 64 ? 63 : y));
}
static V dv_ushr(V a, V b) {
  int64_t x = dv_int(a), y = dv_int(b);
  if (y < 0) dv_throw("ArgumentError: negative shift count");
  return mkint(y >= 64 ? 0 : (int64_t)((uint64_t)x >> y));
}
static V dv_neg(V a) { return mkint((int64_t)(0 - (uint64_t)dv_int(a))); }
static V dv_bnot(V a) { return mkint(~dv_int(a)); }

static V dv_new(int64_t cid, int64_t fields) {
  V *f = dv_alloc(sizeof(V) * (size_t)fields);
  for (int64_t i = 0; i < fields; i++) f[i] = NUL;
  return mkptr(cid, f);
}

static List *dv_list_check(V v) {
  if (v.c != CID_LIST) dv_throw("TypeError: a value is not a List");
  return L(v);
}

static V dv_list_new(int64_t cap) {
  List *l = dv_alloc(sizeof(List));
  l->cap = cap > 4 ? cap : 4;
  l->a = dv_alloc(sizeof(V) * (size_t)l->cap);
  return mkptr(CID_LIST, l);
}

static void dv_list_push(V list, V value) {
  List *l = dv_list_check(list);
  if (l->n == l->cap) {
    l->cap *= 2;
    V *a = dv_alloc(sizeof(V) * (size_t)l->cap);
    memcpy(a, l->a, sizeof(V) * (size_t)l->n);
    l->a = a;
  }
  l->a[l->n++] = value;
}

static void dv_range(int64_t index, int64_t length) {
  if (index < 0 || index >= length) {
    char buffer[160];
    snprintf(buffer, sizeof buffer, "RangeError (index): Index out of range: index should be less than %lld: %lld",
             (long long)length, (long long)index);
    dv_throw(buffer);
  }
}

static Map *dv_map_check(V v) {
  if (v.c != CID_MAP) dv_throw("TypeError: a value is not a Map");
  return M(v);
}

static V dv_map_new(void) { return mkptr(CID_MAP, dv_alloc(sizeof(Map))); }

/* The entry holding [key], or -1. */
static int64_t dv_map_find(Map *m, V key) {
  if (!m->icap) return -1;
  uint64_t j = dv_hash(key) & (uint64_t)(m->icap - 1);
  for (;;) {
    int64_t e = m->ix[j];
    if (e == 0) return -1;
    if (!m->dead[e - 1] && dv_eq(m->k[e - 1], key)) return e - 1;
    j = (j + 1) & (uint64_t)(m->icap - 1);
  }
}

static void dv_map_reindex(Map *m) {
  /* Compacts away removed entries, keeping insertion order. */
  int64_t w = 0;
  for (int64_t r = 0; r < m->n; r++) {
    if (m->dead[r]) continue;
    m->k[w] = m->k[r]; m->v[w] = m->v[r]; m->dead[w] = 0; w++;
  }
  m->n = w;
  int64_t icap = 8;
  while (icap < (m->n + 1) * 2) icap *= 2;
  m->icap = icap;
  m->ix = dv_alloc(sizeof(int64_t) * (size_t)icap);
  for (int64_t e = 0; e < m->n; e++) {
    uint64_t j = dv_hash(m->k[e]) & (uint64_t)(icap - 1);
    while (m->ix[j]) j = (j + 1) & (uint64_t)(icap - 1);
    m->ix[j] = e + 1;
  }
}

static void dv_map_set(V map, V key, V value) {
  Map *m = dv_map_check(map);
  int64_t e = dv_map_find(m, key);
  if (e >= 0) { m->v[e] = value; return; }
  if (m->n == m->cap) {
    int64_t cap = m->cap ? m->cap * 2 : 8;
    V *k = dv_alloc(sizeof(V) * (size_t)cap), *v = dv_alloc(sizeof(V) * (size_t)cap);
    char *dead = dv_alloc((size_t)cap);
    if (m->n) {
      memcpy(k, m->k, sizeof(V) * (size_t)m->n);
      memcpy(v, m->v, sizeof(V) * (size_t)m->n);
      memcpy(dead, m->dead, (size_t)m->n);
    }
    m->k = k; m->v = v; m->dead = dead; m->cap = cap;
  }
  m->k[m->n] = key; m->v[m->n] = value; m->dead[m->n] = 0; m->n++; m->live++;
  if (m->n * 2 > m->icap) dv_map_reindex(m);
  else {
    uint64_t j = dv_hash(key) & (uint64_t)(m->icap - 1);
    while (m->ix[j]) j = (j + 1) & (uint64_t)(m->icap - 1);
    m->ix[j] = m->n;
  }
}
