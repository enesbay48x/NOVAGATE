# TEK KAYNAK: istemci (data.gd) ve sunucu (server_db.py) bu tablodan uretilir -> degerler AYNI kalir.
SHIPS = {  # id: (cr, uri)   -- listede olmayanlara dokunulmadi (spearhead mevcut fiyatiyla)
    "phoenix": (0, 0), "yamato": (16000, 0), "defcom": (32000, 0), "liberator": (64000, 0),
    "piranha": (80000, 0), "nostromo": (100000, 0), "leonov": (0, 9000),
    "vengeance": (0, 30000), "goliath": (0, 80000), "spearhead": (0, 80000),
}
SHIP_HIDDEN = ["bigboy", "aegis", "citadel", "police"]   # satin alinamaz (mevcut MARKET_HIDDEN)
LASERS = {  # id: (dmg, cr, uri)
    "lf1": (65, 1000, 0), "mp1": (70, 10000, 0), "lf2": (140, 50000, 0),
    "lf3": (150, 0, 10000), "lf4": (200, 0, 45000),
}
SPD_GENS = {  # id: (hiz, cr, uri)
    "g3n-1010": (2, 2000, 0), "g3n-2010": (3, 4000, 0), "g3n-3210": (4, 8000, 0),
    "g3n-3310": (5, 16000, 0), "g3n-6900": (7, 0, 1000), "g3n-7900": (10, 0, 8000),
}
SH_GENS = {  # id: (kalkan, emilim(0..1) = hasarin kalkana giden orani, cr, uri)
    "sg3n-a01": (1000, 0.40, 8000, 0), "sg3n-a02": (2000, 0.50, 16000, 0),
    "sg3n-a03": (5000, 0.60, 256000, 0), "sg3n-b01": (9500, 0.70, 0, 2500),
    "sg3n-b02": (10000, 0.80, 0, 10000), "fs-01": (3200, 0.70, 256000, 0),
    "fs-02": (5600, 0.75, 2560000, 0),
}
AMMO = {  # id: (carpan, 1000 adet fiyati, para birimi)  -- 10.000/50.000 paket = dogrusal (x10 / x50)
    "x1": (1.0, 10000, "cr"), "x2": (2.0, 500, "uri"), "x3": (3.0, 1000, "uri"),
    "x4": (4.0, 4000, "uri"), "rsb": (6.0, 5000, "uri"), "sab": (2.0, 1000, "uri"),
    "job": (2.0, 500, "uri"), "pib": (4.0, 9000, "uri"),
}
AMMO_PACKS = (1000, 10000, 50000)
DRONE_PRICES = {  # id: (para birimi, [1..10. droid fiyati])
    "flax": ("cr", [100000, 200000, 400000, 800000, 1600000, 3200000, 6400000, 12800000, 20000000, 20000000]),
    "iris": ("uri", [15000, 24000, 42000, 60000, 84000, 96000, 126000, 200000, 375000, 589000]),
}
MAX_DRONES = 10
SELL_RATE = 0.4
assert sum(DRONE_PRICES["flax"][1]) == 65_500_000 and sum(DRONE_PRICES["iris"][1]) == 1_611_000
