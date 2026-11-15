// Ours (not a ported file): the C bodies of the core library's `external`
// functions (prelude.dart), and which built-in classes each one creates
// values of, which the reachability analysis needs to know.

/// A built-in class a native can create values of.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Makes {
    String,
    List,
}

pub struct Native {
    pub name: &'static str,
    pub makes: &'static [Makes],
    /// The body; the parameters are `a0`, `a1`, ...
    pub body: &'static str,
}

pub const NATIVES: &[Native] = &[
    Native {
        name: "_printString",
        makes: &[],
        body: "Str *s = dv_str_check(a0); fwrite(s->s, 1, (size_t)s->n, stdout); fputc('\\n', stdout); return NUL;",
    },
    Native { name: "_throw", makes: &[], body: "return dv_throw_str(a0);" },
    Native {
        name: "_className",
        makes: &[Makes::String],
        body: "const char *name = a0.c >= 0 && a0.c < (int64_t)(sizeof dv_names / sizeof *dv_names) ? dv_names[a0.c] : 0;\n  \
               if (!name) name = \"?\";\n  return dv_str_from(name, (int64_t)strlen(name));",
    },
    Native {
        name: "_intToString",
        makes: &[Makes::String],
        body: "char buffer[24]; int n = snprintf(buffer, sizeof buffer, \"%lld\", (long long)dv_int(a0)); return dv_str_from(buffer, n);",
    },
    Native { name: "_strLen", makes: &[], body: "return mkint(dv_str_check(a0)->n);" },
    Native {
        name: "_strSub",
        makes: &[Makes::String],
        body: "Str *s = dv_str_check(a0); int64_t start = dv_int(a1), end = dv_int(a2);\n  \
               if (start < 0 || end < start || end > s->n) {\n    \
               char buffer[160]; snprintf(buffer, sizeof buffer, \"RangeError: Invalid range %lld..%lld of a string of length %lld\", (long long)start, (long long)end, (long long)s->n);\n    \
               dv_throw(buffer);\n  }\n  return dv_str_from(s->s + start, end - start);",
    },
    Native {
        name: "_strIndexOf",
        makes: &[],
        body: "Str *s = dv_str_check(a0), *p = dv_str_check(a1); int64_t start = dv_int(a2);\n  \
               for (int64_t i = start < 0 ? 0 : start; i + p->n <= s->n; i++)\n    \
               if (memcmp(s->s + i, p->s, (size_t)p->n) == 0) return mkint(i);\n  return mkint(-1);",
    },
    Native {
        name: "_strCodeUnitAt",
        makes: &[],
        body: "Str *s = dv_str_check(a0); int64_t i = dv_int(a1); dv_range(i, s->n); return mkint((unsigned char)s->s[i]);",
    },
    Native {
        name: "_strFromCharCode",
        makes: &[Makes::String],
        body: "int64_t c = dv_int(a0);\n  \
               if (c < 0 || c > 127) dv_throw(\"Unsupported: dartvel_aot strings are ASCII in this increment\");\n  \
               char ch = (char)c; return dv_str_from(&ch, 1);",
    },
    Native {
        name: "_strTrim",
        makes: &[Makes::String],
        body: "Str *s = dv_str_check(a0); int64_t a = 0, b = s->n;\n  \
               while (a < b && (s->s[a] == ' ' || (s->s[a] >= 9 && s->s[a] <= 13))) a++;\n  \
               while (b > a && (s->s[b - 1] == ' ' || (s->s[b - 1] >= 9 && s->s[b - 1] <= 13))) b--;\n  \
               return dv_str_from(s->s + a, b - a);",
    },
    Native {
        name: "_strLower",
        makes: &[Makes::String],
        body: "Str *s = dv_str_check(a0); V out = dv_str_from(s->s, s->n);\n  \
               for (int64_t i = 0; i < s->n; i++) if (S(out)->s[i] >= 'A' && S(out)->s[i] <= 'Z') S(out)->s[i] += 32;\n  return out;",
    },
    Native {
        name: "_strUpper",
        makes: &[Makes::String],
        body: "Str *s = dv_str_check(a0); V out = dv_str_from(s->s, s->n);\n  \
               for (int64_t i = 0; i < s->n; i++) if (S(out)->s[i] >= 'a' && S(out)->s[i] <= 'z') S(out)->s[i] -= 32;\n  return out;",
    },
    Native {
        name: "_strJoin",
        makes: &[Makes::String],
        body: "List *l = dv_list_check(a0); Str *sep = dv_str_check(a1); int64_t n = 0;\n  \
               for (int64_t i = 0; i < l->n; i++) n += dv_str_check(l->a[i])->n + (i ? sep->n : 0);\n  \
               V out = dv_str_new(n); char *at = S(out)->s;\n  \
               for (int64_t i = 0; i < l->n; i++) {\n    \
               if (i) { memcpy(at, sep->s, (size_t)sep->n); at += sep->n; }\n    \
               memcpy(at, S(l->a[i])->s, (size_t)S(l->a[i])->n); at += S(l->a[i])->n;\n  }\n  return out;",
    },
    Native { name: "_listLen", makes: &[], body: "return mkint(dv_list_check(a0)->n);" },
    Native { name: "_listAdd", makes: &[], body: "dv_list_push(a0, a1); return NUL;" },
    Native {
        name: "_listGet",
        makes: &[],
        body: "List *l = dv_list_check(a0); int64_t i = dv_int(a1); dv_range(i, l->n); return l->a[i];",
    },
    Native {
        name: "_listSet",
        makes: &[],
        body: "List *l = dv_list_check(a0); int64_t i = dv_int(a1); dv_range(i, l->n); l->a[i] = a2; return NUL;",
    },
    Native {
        name: "_listRemoveLast",
        makes: &[],
        body: "List *l = dv_list_check(a0); if (!l->n) dv_throw(\"RangeError: the list is empty\"); return l->a[--l->n];",
    },
    Native {
        name: "_mapGet",
        makes: &[],
        body: "Map *m = dv_map_check(a0); int64_t e = dv_map_find(m, a1); return e < 0 ? NUL : m->v[e];",
    },
    Native { name: "_mapSet", makes: &[], body: "dv_map_set(a0, a1, a2); return NUL;" },
    Native {
        name: "_mapContainsKey",
        makes: &[],
        body: "return mkbool(dv_map_find(dv_map_check(a0), a1) >= 0);",
    },
    Native { name: "_mapLen", makes: &[], body: "return mkint(dv_map_check(a0)->live);" },
    Native {
        name: "_mapKeyList",
        makes: &[Makes::List],
        body: "Map *m = dv_map_check(a0); V out = dv_list_new(m->live);\n  \
               for (int64_t e = 0; e < m->n; e++) if (!m->dead[e]) dv_list_push(out, m->k[e]);\n  return out;",
    },
    Native {
        name: "_mapRemove",
        makes: &[],
        body: "Map *m = dv_map_check(a0); int64_t e = dv_map_find(m, a1); if (e < 0) return NUL;\n  \
               m->dead[e] = 1; m->live--; return m->v[e];",
    },
];

pub fn find(name: &str) -> Option<&'static Native> {
    NATIVES.iter().find(|n| n.name == name)
}
