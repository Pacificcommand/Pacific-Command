"""The battle islands, as close to the real ones as we can get.

Coastlines come from geoBoundaries (OpenStreetMap-quality country outlines) cropped to a window
round the place the battle is fought (see fetch.py); Wake and Midway, which no open dataset here
has at a usable scale, are traced by hand onto the Natural Earth outline. Heights come from the
real summits (peaks) and the kind of island; airfields, towns and the landing beach are where they
were in 1942-45.

Per island:
  center   (lon, lat) of the battle window; half = half its size in metres
  src      geoBoundaries file key(s) to crop the coast from (see fetch.py), or 'hand'
  kind     atoll (flat coral islets on a reef ring), coral (raised limestone: cliffs, plateaus),
           volcanic (high, steep, jungle), ash (Iwo Jima: bare volcanic sand and scrub)
  base     height the land climbs to a little way in from the shore (m); rise = how far in (m)
  peaks    [(lon, lat, height m, radius m)] real summits and ridges
  veg      vegetation cover 0..1; vtype 'palm' (coconut groves), 'jungle', 'scrub', 'cane' (fields)
  reef     fringing reef width (m) off the shore; rim: the atoll's reef rim [(lon, lat)] traced from
           the real atoll (inside is lagoon, a reef flat runs along it); lagoon: closing radius (m)
           that joins islets into a ring where no rim is given (Wake); reef_ring: an ellipse rim
           (Midway); lagoon_all: the whole window is a lagoon (Truk)
  fields   airfields [(lon, lat, heading deg or None = along the island, length m, width m)]
  towns    [(lon, lat, radius m)]
  beach    (lon, lat) the landing beach / bombardment target; the approach is from the sea off it
           (the clearest bearing, or approach = deg where history fixes it; approach_dist m)
"""

ISLANDS = {
    'wake': dict(name='Wake Island', center=(166.627, 19.294), half=5200, src='hand', kind='atoll',
                 base=3.5, rise=120, peaks=[], veg=0.55, vtype='scrub', reef=380, lagoon=2600,
                 fields=[(166.6395, 19.2785, 104, 1500, 60)], towns=[(166.6500, 19.2830, 260)],
                 beach=(166.640, 19.276)),
    'midway': dict(name='Midway', center=(-177.355, 28.225), half=7500, src='hand', kind='atoll',
                   base=4.0, rise=150, peaks=[(-177.378, 28.209, 12, 700)], veg=0.6, vtype='scrub', reef=300,
                   lagoon=0, reef_ring=((-177.355, 28.243), 5300, 4700),
                   fields=[(-177.3290, 28.2075, 72, 1500, 60), (-177.3270, 28.2085, 140, 1100, 50), (-177.3300, 28.2090, 15, 1000, 50)],
                   towns=[(-177.375, 28.211, 350)], beach=(-177.370, 28.199)),
    'tarawa': dict(approach=0, approach_dist=7000, name='Tarawa (Betio)', center=(172.955, 1.372), half=7000, src='KIR', kind='atoll', rim=[(172.915, 1.352), (173.040, 1.336), (173.170, 1.365), (173.165, 1.420), (173.050, 1.600), (172.990, 1.720), (172.960, 1.600), (172.930, 1.440)],
                 
                   base=3.0, rise=90, peaks=[], veg=0.9, vtype='palm', reef=650, lagoon=2500,
                   fields=[(172.937, 1.354, None, 1250, 70)], towns=[], beach=(172.932, 1.362)),
    'makin': dict(name='Makin (Butaritari)', center=(172.82, 3.08), half=8000, src='KIR', kind='atoll', rim=[(172.735, 3.078), (172.780, 3.068), (172.820, 3.090), (172.900, 3.100), (172.975, 3.185), (172.880, 3.260), (172.775, 3.240), (172.690, 3.275), (172.690, 3.200)],
                 
                  base=3.0, rise=100, peaks=[], veg=0.95, vtype='palm', reef=500, lagoon=3000,
                  fields=[], towns=[(172.79, 3.07, 400)], beach=(172.775, 3.068)),
    'kwajalein': dict(name='Kwajalein', center=(167.73, 8.75), half=8000, src='MHL', kind='atoll', rim=[(167.725, 8.710), (167.765, 8.745), (167.800, 8.850), (167.720, 9.150), (167.470, 9.400), (167.100, 9.050), (167.050, 8.850), (167.350, 8.740), (167.600, 8.715)],
                 
                      base=3.0, rise=90, peaks=[], veg=0.85, vtype='palm', reef=500, lagoon=3500,
                      fields=[(167.732, 8.722, None, 1500, 70)], towns=[], beach=(167.725, 8.718)),
    'majuro': dict(name='Majuro', center=(171.26, 7.10), half=9000, src='MHL', kind='atoll', rim=[(171.030, 7.080), (171.100, 7.060), (171.250, 7.090), (171.380, 7.070), (171.400, 7.120), (171.330, 7.200), (171.150, 7.220), (171.050, 7.170)],
                 
                   base=3.0, rise=90, peaks=[], veg=0.9, vtype='palm', reef=450, lagoon=3500,
                   fields=[], towns=[], beach=(171.20, 7.08)),
    'eniwetok': dict(name='Eniwetok', center=(162.32, 11.37), half=9000, src='MHL', kind='atoll', rim=[(162.350, 11.330), (162.400, 11.450), (162.380, 11.600), (162.250, 11.680), (162.120, 11.600), (162.050, 11.450), (162.150, 11.350)],
                 
                     base=3.0, rise=90, peaks=[], veg=0.8, vtype='palm', reef=500, lagoon=3500,
                     fields=[(162.345, 11.345, None, 1700, 70)], towns=[], beach=(162.34, 11.335)),
    'truk': dict(name='Truk (Dublon and Moen)', center=(151.865, 7.39), half=12000, src='FSM', kind='volcanic',
                 base=40, rise=300, veg=0.95, vtype='jungle', reef=250, lagoon=0, lagoon_all=True,
                 peaks=[(151.857, 7.447, 370, 2600), (151.887, 7.362, 354, 1700), (151.842, 7.336, 300, 2200),
                        (151.880, 7.297, 260, 1600), (151.735, 7.380, 300, 2400)],
                 fields=[(151.885, 7.342, None, 1050, 70), (151.846, 7.460, None, 1300, 70)],
                 towns=[(151.890, 7.367, 450)], beach=(151.895, 7.352)),
    'ulithi': dict(name='Ulithi', center=(139.75, 10.02), half=9000, src='FSM', kind='atoll', rim=[(139.800, 10.030), (139.790, 9.900), (139.660, 9.850), (139.600, 9.950), (139.620, 10.100), (139.720, 10.120)],
                 
                   base=3.0, rise=90, peaks=[], veg=0.9, vtype='palm', reef=500, lagoon=4000,
                   fields=[(139.790, 10.020, None, 1300, 60)], towns=[], beach=(139.788, 10.012)),
    'rabaul': dict(approach=150, name='Rabaul', center=(152.19, -4.24), half=12000, src='PNG2', kind='volcanic',
                   base=60, rise=400, veg=0.85, vtype='jungle', reef=150, lagoon=0,
                   peaks=[(152.207, -4.203, 688, 2400), (152.190, -4.193, 535, 1800), (152.225, -4.232, 534, 1800),
                          (152.203, -4.271, 223, 900), (152.163, -4.272, 225, 1100), (152.10, -4.30, 350, 7000)],
                   fields=[(152.199, -4.224, 165, 1300, 70)], towns=[(152.177, -4.199, 800)], beach=(152.178, -4.215)),
    'manus': dict(name='Manus (Admiralties)', center=(147.36, -2.04), half=13000, src='PNG2', kind='volcanic',
                  base=25, rise=500, veg=0.95, vtype='jungle', reef=400, lagoon=0,
                  peaks=[(147.22, -2.07, 350, 6000), (147.10, -2.10, 500, 8000)],
                  fields=[(147.4245, -2.0617, 98, 1700, 70)], towns=[(147.272, -2.023, 450)], beach=(147.43, -2.07)),
    'tulagi': dict(name='Guadalcanal and Tulagi', center=(160.00, -9.28), half=22000, src='SLB2', kind='volcanic',
                   base=25, rise=1500, veg=0.95, vtype='jungle', reef=150, lagoon=0,
                   peaks=[(159.988, -9.463, 410, 3200), (160.05, -9.56, 900, 11000), (159.90, -9.52, 800, 10000),
                          (160.20, -9.55, 700, 9000), (160.20, -9.03, 420, 6000), (160.10, -9.05, 300, 4000),
                          (159.81, -9.13, 485, 3400)],
                   fields=[(160.0546, -9.428, 62, 1200, 70)], towns=[(160.150, -9.105, 350)], beach=(160.030, -9.405)),
    'munda': dict(name='Munda (New Georgia)', center=(157.27, -8.30), half=13000, src='SLB2', kind='volcanic',
                  base=30, rise=900, veg=0.95, vtype='jungle', reef=400, lagoon=0,
                  peaks=[(157.33, -8.22, 500, 8000), (157.42, -8.24, 600, 7000), (157.20, -8.20, 300, 5000)],
                  fields=[(157.263, -8.327, 96, 1400, 70)], towns=[], beach=(157.262, -8.332)),
    'bougainville': dict(name='Bougainville (Empress Augusta Bay)', center=(155.10, -6.20), half=15000, src='PNG2', kind='volcanic',
                         base=15, rise=3000, veg=0.95, vtype='jungle', reef=120, lagoon=0,
                         peaks=[(155.195, -6.137, 1750, 7000), (155.15, -6.05, 1200, 12000), (155.25, -6.25, 900, 9000)],
                         fields=[(155.048, -6.215, 128, 1200, 70)], towns=[], beach=(155.045, -6.225)),
    'milne': dict(name='Milne Bay', center=(150.42, -10.33), half=15000, src='PNG2', kind='volcanic',
                  base=20, rise=1200, veg=0.95, vtype='jungle', reef=150, lagoon=0,
                  peaks=[(150.40, -10.20, 900, 10000), (150.47, -10.45, 700, 9000), (150.25, -10.32, 1000, 8000)],
                  fields=[(150.334, -10.311, 98, 1500, 70)], towns=[(150.45, -10.31, 400)], beach=(150.36, -10.33)),
    'saipan': dict(name='Saipan and Tinian', center=(145.71, 15.11), half=14000, src='MNP', kind='coral',
                   base=40, rise=250, veg=0.7, vtype='cane', reef=500, lagoon=0,
                   peaks=[(145.745, 15.183, 474, 5000), (145.802, 15.270, 250, 3000), (145.780, 15.170, 120, 2500),
                          (145.730, 15.120, 60, 4000), (145.640, 15.040, 180, 3500)],
                   fields=[(145.729, 15.119, 70, 1700, 70), (145.632, 15.068, 85, 1500, 70)],
                   towns=[(145.718, 15.212, 800), (145.690, 15.158, 450)], beach=(145.690, 15.155)),
    'guam': dict(approach=290, name='Guam', center=(144.70, 13.43), half=15000, src='GUM', kind='coral',
                 base=50, rise=300, veg=0.85, vtype='jungle', reef=300, lagoon=0,
                 peaks=[(144.663, 13.338, 406, 6000), (144.705, 13.440, 330, 4000), (144.690, 13.400, 316, 4000),
                        (144.850, 13.550, 150, 15000)],
                 fields=[(144.645, 13.437, 105, 1400, 70)], towns=[(144.752, 13.475, 700)], beach=(144.690, 13.475)),
    'palau': dict(name='Peleliu (Palau)', center=(134.25, 7.03), half=8000, src='PLW', kind='coral',
                  base=8, rise=150, veg=0.85, vtype='jungle', reef=700, lagoon=0,
                  peaks=[(134.255, 7.018, 90, 1300), (134.262, 7.040, 60, 1500)],
                  fields=[(134.231, 7.002, 45, 1300, 70), (134.231, 7.002, 128, 1300, 70)], towns=[], beach=(134.222, 6.998)),
    'leyte': dict(name='Leyte (Tacloban)', center=(125.03, 11.08), half=18000, src='PHL', kind='volcanic',
                  base=15, rise=3000, veg=0.85, vtype='jungle', reef=150, lagoon=0,
                  peaks=[(124.88, 11.10, 900, 15000), (124.90, 10.95, 1000, 15000), (125.10, 11.30, 250, 8000)],
                  fields=[(125.026, 11.227, 172, 1500, 70), (124.995, 10.945, 90, 1300, 70)],
                  towns=[(125.003, 11.243, 900)], beach=(125.040, 11.140)),
    'iwo': dict(name='Iwo Jima', center=(141.315, 24.78), half=5500, src='JPN1', kind='ash',
                base=25, rise=250, veg=0.45, vtype='scrub', reef=60, lagoon=0,
                peaks=[(141.2894, 24.7510, 169, 650), (141.325, 24.790, 110, 3500), (141.335, 24.805, 95, 2000)],
                fields=[(141.300, 24.772, 60, 1400, 70), (141.322, 24.787, 20, 1500, 70), (141.322, 24.787, 110, 1300, 70)],
                towns=[], beach=(141.305, 24.765)),
    'okinawa': dict(name='Okinawa (Hagushi)', center=(127.77, 26.36), half=18000, src='JPN1', kind='coral',
                    base=30, rise=800, veg=0.7, vtype='cane', reef=500, lagoon=0,
                    peaks=[(127.80, 26.32, 150, 5000), (127.82, 26.40, 200, 6000), (127.85, 26.47, 300, 7000)],
                    fields=[(127.750, 26.395, 5, 1500, 70), (127.770, 26.355, 50, 1500, 70)],
                    towns=[(127.80, 26.24, 900)], beach=(127.740, 26.370)),
    'espiritu': dict(name='Espiritu Santo', center=(167.17, -15.52), half=14000, src='VUT', kind='volcanic',
                     base=40, rise=2500, veg=0.95, vtype='jungle', reef=250, lagoon=0,
                     peaks=[(167.05, -15.45, 900, 15000), (167.17, -15.58, 150, 3000)],
                     fields=[(167.220, -15.505, 60, 1800, 70)], towns=[(167.17, -15.515, 600)], beach=(167.19, -15.53)),
    'noumea': dict(name='Noumea (New Caledonia)', center=(166.45, -22.27), half=14000, src='NCL', kind='volcanic',
                   base=40, rise=1500, veg=0.6, vtype='scrub', reef=300, lagoon=0,
                   peaks=[(166.58, -22.27, 772, 4000), (166.51, -22.18, 1061, 6000), (166.47, -22.25, 180, 2500)],
                   fields=[(166.470, -22.260, 120, 1100, 60)], towns=[(166.445, -22.275, 1500)], beach=(166.43, -22.29)),
}

# Hand-traced outlines (lon, lat) for the islands no dataset here has in detail, fitted to the
# Natural Earth outline: Wake's V (Wake Island with Wilkes to the south-west and Peale to the
# north-west), Midway's Sand Island and Eastern Island inside the round reef.
HAND = {
    'wake': [
        [(166.6262, 19.2797), (166.6350, 19.2775), (166.6440, 19.2752), (166.6500, 19.2775), (166.6528, 19.2835),
         (166.6512, 19.2905), (166.6480, 19.2975), (166.6420, 19.3030), (166.6355, 19.3062), (166.6318, 19.3048),
         (166.6362, 19.3002), (166.6398, 19.2950), (166.6418, 19.2893), (166.6392, 19.2852), (166.6330, 19.2838),
         (166.6268, 19.2842)],
        [(166.5985, 19.2840), (166.6080, 19.2808), (166.6190, 19.2793), (166.6248, 19.2797), (166.6250, 19.2834),
         (166.6170, 19.2840), (166.6075, 19.2860), (166.6002, 19.2882), (166.5972, 19.2866)],
        [(166.6302, 19.3058), (166.6268, 19.3108), (166.6200, 19.3150), (166.6110, 19.3172), (166.6068, 19.3160),
         (166.6098, 19.3128), (166.6178, 19.3108), (166.6238, 19.3076), (166.6276, 19.3042)],
    ],
    'midway': [
        [(-177.3577, 28.2144), (-177.3622, 28.2110), (-177.3645, 28.2076), (-177.3722, 28.2023), (-177.3807, 28.1989),
         (-177.3896, 28.1977), (-177.3900, 28.2010), (-177.3852, 28.2070), (-177.3780, 28.2128), (-177.3686, 28.2153),
         (-177.3620, 28.2158)],
        [(-177.3289, 28.2111), (-177.3229, 28.2077), (-177.3212, 28.2059), (-177.3249, 28.2050), (-177.3300, 28.2045),
         (-177.3353, 28.2043), (-177.3340, 28.2070)],
        [(-177.3468, 28.2158), (-177.3445, 28.2150), (-177.3452, 28.2138), (-177.3475, 28.2145)],     # Spit Island
    ],
}
