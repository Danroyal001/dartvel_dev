// An R8 mapping.txt in the format R8 8.x writes (the "Retracing" section of
// the Android developer docs and r8's mapping-file test fixtures use this
// same grammar): header comments, `original -> obfuscated:` class lines, field
// lines, and method lines with `minStart:minEnd:` and `:origStart[:origEnd]`
// line ranges, where several lines for one minified range are an inlining
// chain, innermost first.
library;

const String r8Mapping = r'''
# compiler: R8
# compiler_version: 8.5.35
# min_api: 24
# pg_map_id: 7fa5f2b
# common_typos_disable
com.example.shop.CheckoutActivity -> a.a.a:
# {"id":"sourceFile","fileName":"CheckoutActivity.kt"}
    int itemCount -> a
    1:1:void <init>():8:8 -> <init>
    1:3:void onCreate(android.os.Bundle):12:14 -> onCreate
    4:4:void validate():30 -> onCreate
    4:4:void onCreate(android.os.Bundle):15:15 -> onCreate
    5:9:void pay(java.lang.String,int):40:44 -> b
    void reset() -> c
com.example.shop.CheckoutActivity$Companion -> a.a.b:
    1:2:com.example.shop.Cart load():60:61 -> a
com.example.shop.PaymentGateway -> a.b:
    void charge(long) -> a
    1:1:void charge(long):10:10 -> b
    2:2:void charge(long):11:11 -> b
''';
