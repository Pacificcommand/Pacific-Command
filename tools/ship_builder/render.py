"""Small software renderer (orthographic, flat shading, sun shadow map) and glTF exporter."""
import json, struct
import numpy as np
from PIL import Image, ImageFilter

def hex_rgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float) / 255

def collect(M):
    tris, cols = [], []
    for g in M.groups.values():
        tris.extend(g['tris'])
        cols.extend(hex_rgb(m) for m in g['mats'])
    return np.array(tris), np.array(cols)

def basis(view_dir, up=None):
    d = np.array(view_dir, float); d /= np.linalg.norm(d)
    if up is None:
        up = np.array([0, 1, 0.0]) if abs(d[1]) < .95 else np.array([0, 0, -1.0])
    up = np.array(up, float)
    r = np.cross(d, up); r /= np.linalg.norm(r)
    u = np.cross(r, d)
    return r, u, d

def raster(tris, r, u, d, origin, scale, W, H):
    """Orthographic z-buffer. Returns depth, face-id buffers."""
    rel = tris - origin
    sx = (rel @ r) * scale + W / 2
    sy = -(rel @ u) * scale + H / 2
    sz = rel @ d
    zb = np.full((H, W), np.inf, np.float32)
    fid = np.full((H, W), -1, np.int32)
    for i in range(len(tris)):
        x0, x1, x2 = sx[i]; y0, y1, y2 = sy[i]
        minx = max(int(np.floor(min(x0, x1, x2))), 0); maxx = min(int(np.ceil(max(x0, x1, x2))), W - 1)
        miny = max(int(np.floor(min(y0, y1, y2))), 0); maxy = min(int(np.ceil(max(y0, y1, y2))), H - 1)
        if minx > maxx or miny > maxy:
            continue
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-9:
            continue
        px = np.arange(minx, maxx + 1) + .5
        py = np.arange(miny, maxy + 1) + .5
        PX, PY = np.meshgrid(px, py)
        a = ((y1 - y2) * (PX - x2) + (x2 - x1) * (PY - y2)) / den
        b = ((y2 - y0) * (PX - x2) + (x0 - x2) * (PY - y2)) / den
        c = 1 - a - b
        m = (a >= -1e-4) & (b >= -1e-4) & (c >= -1e-4)
        if not m.any():
            continue
        z = a * sz[i, 0] + b * sz[i, 1] + c * sz[i, 2]
        sub = zb[miny:maxy + 1, minx:maxx + 1]
        upd = m & (z < sub)
        sub[upd] = z[upd]
        fid[miny:maxy + 1, minx:maxx + 1][upd] = i
    return zb, fid

def render(M, view_dir, center, extent_w, extent_h, px_per_m, sun_to, water_cols, ss=2, foam=True, wake_dir=None):
    tris, cols = collect(M)
    # water plane as two big triangles
    g = np.linspace(-200, 200, 21)
    wp = []
    for i in range(20):
        for j in range(20):
            a, b, c, e = [g[i], 0, g[j]], [g[i + 1], 0, g[j]], [g[i + 1], 0, g[j + 1]], [g[i], 0, g[j + 1]]
            wp += [[a, b, c], [a, c, e]]
    wp = np.array(wp, float) + np.array([center[0], 0, center[2]])
    WATER = len(tris)
    tris = np.concatenate([tris, wp]); cols = np.concatenate([cols, np.zeros((len(wp), 3))])
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
    r, u, d = basis(view_dir)
    n[np.sum(n * d, axis=1) > 0] *= -1                       # face the camera (two-sided)
    W = int(extent_w * px_per_m * ss); H = int(extent_h * px_per_m * ss)
    zb, fid = raster(tris, r, u, d, np.array(center, float), px_per_m * ss, W, H)
    # world positions per pixel
    ys, xs = np.mgrid[0:H, 0:W]
    pu = (xs + .5 - W / 2) / (px_per_m * ss); pv = -(ys + .5 - H / 2) / (px_per_m * ss)
    hit = fid >= 0
    world = np.array(center) + pu[..., None] * r + pv[..., None] * u + np.where(hit, zb, 0)[..., None] * d
    # shadow map from the sun
    sd = -np.array(sun_to, float); sd /= np.linalg.norm(sd)
    sr, su, sdd = basis(sd)
    SM = 2600
    sscale = SM / 150.0
    szb, sfid = raster(tris[:WATER], sr, su, sdd, np.array(center, float), sscale, SM, SM)
    rel = world - np.array(center)
    smx = ((rel @ sr) * sscale + SM / 2).astype(int).clip(0, SM - 1)
    smy = (-(rel @ su) * sscale + SM / 2).astype(int).clip(0, SM - 1)
    sz = rel @ sdd
    occ = szb[smy, smx]
    shadow = (sz - occ > 0.12) & hit
    shadow = np.array(Image.fromarray((shadow * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2 * ss))) / 255.0
    # shading
    L = np.array(sun_to, float); L /= np.linalg.norm(L)
    fid = np.where(fid >= WATER, WATER, fid)
    fidc = np.where(hit, fid, WATER)
    nn = n[fidc]
    lam = np.clip(np.sum(nn * L, axis=-1), 0, 1)
    sky = 0.5 + 0.5 * nn[..., 1]
    albedo = cols[fidc]
    lit = 0.30 + 0.20 * sky[..., None] + 0.85 * lam[..., None] * (1 - 0.82 * shadow[..., None])
    img = albedo * lit
    # ambient occlusion from the depth buffer: surfaces sitting below their surroundings get darker
    from scipy.ndimage import gaussian_filter, maximum_filter, minimum_filter
    zf = np.where(hit, zb, np.nan)
    zfill = np.where(hit, zb, np.nanmax(zb[hit]) if hit.any() else 0)
    around = gaussian_filter(zfill, 3.0 * ss)
    ao = np.clip((zfill - around) * 0.9, 0, 0.45)
    img = img * (1 - ao[..., None])
    # crisp outlines where depth jumps (edges of decks, mounts, funnels)
    zmax = maximum_filter(zfill, size=3); zmin = minimum_filter(zfill, size=3)
    edge = np.clip((zmax - zmin - 0.25) * 1.6, 0, 1) * 0.45
    img = img * (1 - edge[..., None])
    # water colour with gentle noise, waterline foam, shadow on the water
    water = fidc == WATER
    rng = np.random.default_rng(3)
    noise = np.array(Image.fromarray((rng.random((H // 8 + 2, W // 8 + 2)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)) / 255.0
    noise2 = np.array(Image.fromarray((rng.random((H // 2 + 2, W // 2 + 2)) * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)) / 255.0
    deep, shallow = hex_rgb(water_cols[0]), hex_rgb(water_cols[1])
    wcol = deep + (shallow - deep) * (0.35 * noise + 0.25 * noise2)[..., None]
    wcol = wcol * (1 - 0.55 * shadow[..., None])
    if foam:
        from scipy.ndimage import distance_transform_edt
        hull_wl = (~water) & hit
        dist = distance_transform_edt(~hull_wl) / (px_per_m * ss)
        # bow wave wider forward: use world x
        wx = world[..., 0]
        width = 0.6 + 2.2 * np.clip((wx - 30) / 27, 0, 1) + 1.6 * np.clip((-wx - 50) / 7, 0, 1)
        f = np.clip(1 - dist / width, 0, 1) ** 1.5 * (0.6 + 0.5 * noise2)
        # stern wash behind the ship
        behind = np.clip((-wx - 57) / 1, 0, 1) * np.clip(1 - (-wx - 57) / 55, 0, 1)
        wz = np.abs(world[..., 2])
        wash = behind * np.clip(1 - wz / (4.5 + 0.12 * (-wx - 57)), 0, 1) * (0.35 + 0.6 * noise2) * 0.9
        f = np.clip(f + wash, 0, 1)
        wcol = wcol + (np.array([0.9, 0.95, 0.96]) - wcol) * (f * water)[..., None]
    img = np.where(water[..., None], wcol, img)
    img = np.clip(img, 0, 1) ** (1 / 1.12)
    out = Image.fromarray((img * 255).astype(np.uint8))
    return out.resize((W // ss, H // ss), Image.LANCZOS)

# ---------------- glTF export ----------------
def export_glb(M, path, axis_fix=True):
    def conv(v):
        # internal (x fwd, y up, z stbd) -> glTF (X right/stbd, Y up, Z aft): forward is -Z
        return np.stack([v[..., 2], v[..., 1], -v[..., 0]], -1)
    mats, mat_index = [], {}
    nodes, meshes, accessors, views = [], [], [], []
    blob = bytearray()
    def add_view(data, target=34962):
        while len(blob) % 4: blob.append(0)
        off = len(blob); blob.extend(data)
        views.append({'buffer': 0, 'byteOffset': off, 'byteLength': len(data), 'target': target})
        return len(views) - 1
    children = []
    for gname, g in M.groups.items():
        if not g['tris']:
            continue
        tris = np.array(g['tris']) - g['pivot']
        prims = []
        by_mat = {}
        for t, m in zip(tris, g['mats']):
            by_mat.setdefault(m, []).append(t)
        for m, ts in by_mat.items():
            if m not in mat_index:
                c = hex_rgb(m)
                lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
                mat_index[m] = len(mats)
                mats.append({'name': 'paint_' + m.strip('#'), 'doubleSided': True,
                             'pbrMetallicRoughness': {'baseColorFactor': [float(lin[0]), float(lin[1]), float(lin[2]), 1.0], 'metallicFactor': 0.1, 'roughnessFactor': 0.75}})
            v = conv(np.array(ts, np.float32)).reshape(-1, 3).astype(np.float32)
            nrm = np.cross(v[1::3] - v[0::3], v[2::3] - v[0::3])
            nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
            nrm = np.repeat(nrm, 3, axis=0).astype(np.float32)
            pv = add_view(v.tobytes()); accessors.append({'bufferView': pv, 'componentType': 5126, 'count': len(v), 'type': 'VEC3',
                                                         'min': v.min(0).tolist(), 'max': v.max(0).tolist()})
            pa = len(accessors) - 1
            nv = add_view(nrm.tobytes()); accessors.append({'bufferView': nv, 'componentType': 5126, 'count': len(nrm), 'type': 'VEC3'})
            na = len(accessors) - 1
            prims.append({'attributes': {'POSITION': pa, 'NORMAL': na}, 'material': mat_index[m]})
        meshes.append({'name': gname, 'primitives': prims})
        piv = conv(g['pivot'].astype(np.float32))
        nodes.append({'name': gname, 'mesh': len(meshes) - 1, 'translation': [float(piv[0]), float(piv[1]), float(piv[2])]})
        children.append(len(nodes) - 1)
    nodes.append({'name': getattr(M, 'rootname', 'Ship'), 'children': children})
    gltf = {'asset': {'version': '2.0', 'generator': 'Pacific Command ship builder'}, 'scene': 0,
            'scenes': [{'nodes': [len(nodes) - 1]}], 'nodes': nodes, 'meshes': meshes, 'materials': mats,
            'accessors': accessors, 'bufferViews': views, 'buffers': [{'byteLength': len(blob)}]}
    js = json.dumps(gltf, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    while len(blob) % 4: blob.append(0)
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack('<II', len(blob), 0x004E4942)); f.write(bytes(blob))
