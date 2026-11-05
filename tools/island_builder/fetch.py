"""Crop the real coastlines for each battle island out of the big country outline files.

The source files (geoBoundaries gbOpen, OpenStreetMap-derived; downloaded once, not kept in the
repo) are read from SRC_DIR; the cropped rings go to coast/<id>.json (lon, lat pairs), which the
baker reads, so rebuilding the islands needs no network.

Sources (download into SRC_DIR as gb_<KEY>.json):
  https://media.githubusercontent.com/media/wmgeolab/geoBoundaries/main/releaseData/gbOpen/<ISO>/ADM0/geoBoundaries-<ISO>-ADM0.geojson
  KIR MHL FSM MNP GUM PLW PHL VUT NCL at ADM0; SLB2 = SLB/ADM2, JPN1 = JPN/ADM1, PNG2 = PNG/ADM2.
"""
import json, math, os, sys
from islands import ISLANDS, HAND

SRC_DIR = os.environ.get('SRC_DIR', 'src')
OUT = os.path.join(os.path.dirname(__file__), 'coast')


def rings(path):
    d = json.load(open(path))
    out = []
    for f in d['features']:
        g = f['geometry']
        if g is None:
            continue
        ps = g['coordinates'] if g['type'] == 'MultiPolygon' else [g['coordinates']]
        for p in ps:
            out.append(p[0])
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    cache = {}
    for iid, I in ISLANDS.items():
        lon0, lat0 = I['center']
        # atolls: a wider crop, so the lagoon can be worked out from the whole rim
        h = I['half'] * (3.2 if I['kind'] == 'atoll' else 1.25)
        dl = h / (111320.0 * math.cos(math.radians(lat0)))
        dt = h / 111320.0
        if I['src'] == 'hand':
            keep = [list(r) for r in HAND[iid]]
        else:
            key = I['src']
            if key not in cache:
                cache[key] = rings(os.path.join(SRC_DIR, 'gb_%s.json' % key))
            keep = []
            for r in cache[key]:
                xs = [((c[0] - lon0 + 180.0) % 360.0) - 180.0 for c in r]
                ys = [c[1] - lat0 for c in r]
                if max(xs) < -dl or min(xs) > dl or max(ys) < -dt or min(ys) > dt:
                    continue
                keep.append([(round(c[0], 6), round(c[1], 6)) for c in r])
        json.dump({'id': iid, 'rings': keep}, open(os.path.join(OUT, iid + '.json'), 'w'), separators=(',', ':'))
        print('%-13s %4d rings %6d points' % (iid, len(keep), sum(len(r) for r in keep)))


if __name__ == '__main__':
    main()
