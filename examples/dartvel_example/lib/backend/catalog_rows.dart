// The season's coffees as rows: plain Dart, so the server can seed its SQLite
// table from them and the app can seed its own store from the same list.
const List<Map<String, Object?>> catalogRows = <Map<String, Object?>>[
  <String, Object?>{
    'slug': 'huila',
    'name': 'Huila',
    'origin': 'Huila, Colombia',
    'roast': 'medium',
    'notes': 'Red apple, panela, cocoa',
    'description': 'Grown by a co-operative of forty smallholders above '
        '1,700 metres. Sweet and round, with enough body to take milk.',
    'priceCents': 1700,
    'weightGrams': 250,
    'published': true,
  },
  <String, Object?>{
    'slug': 'yirgacheffe',
    'name': 'Yirgacheffe',
    'origin': 'Gedeo, Ethiopia',
    'roast': 'light',
    'notes': 'Jasmine, bergamot, lemon curd',
    'description': 'Washed heirloom varieties, dried on raised beds for '
        'twelve days. Floral and bright, best as a pour-over.',
    'priceCents': 1900,
    'weightGrams': 250,
    'published': true,
  },
  <String, Object?>{
    'slug': 'nyeri',
    'name': 'Nyeri',
    'origin': 'Nyeri, Kenya',
    'roast': 'light',
    'notes': 'Blackcurrant, grapefruit, cane sugar',
    'description': 'SL28 and SL34 from the slopes of Mount Kenya. Juicy and '
        'vivid; try it as a cold brew.',
    'priceCents': 2100,
    'weightGrams': 250,
    'published': true,
  },
  <String, Object?>{
    'slug': 'harbour-blend',
    'name': 'Harbour Blend',
    'origin': 'Brazil and Guatemala',
    'roast': 'dark',
    'notes': 'Dark chocolate, hazelnut, molasses',
    'description': 'Our house espresso. Built to be forgiving in a home '
        'machine and to cut through a flat white.',
    'priceCents': 1500,
    'weightGrams': 500,
    'published': true,
  },
  <String, Object?>{
    'slug': 'huehuetenango',
    'name': 'Huehuetenango',
    'origin': 'Huehuetenango, Guatemala',
    'roast': 'medium',
    'notes': 'Toffee, orange peel, almond',
    'description': 'From the highlands near the Mexican border, where dry '
        'winds let the cherries ripen slowly. Balanced and sweet.',
    'priceCents': 1800,
    'weightGrams': 250,
    'published': true,
  },
  <String, Object?>{
    'slug': 'night-shift-decaf',
    'name': 'Night Shift Decaf',
    'origin': 'Cauca, Colombia',
    'roast': 'medium',
    'notes': 'Milk chocolate, plum, brown sugar',
    'description': 'Decaffeinated with sugarcane ethyl acetate at origin, so '
        'it still tastes like coffee at nine in the evening.',
    'priceCents': 1600,
    'weightGrams': 250,
    'published': true,
  },
];
