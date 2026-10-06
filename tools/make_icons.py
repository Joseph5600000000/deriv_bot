#!/usr/bin/env python3
"""Builds the DeltaDesk launcher icons from assets/branding/source_reference.jpg.
Needs: pip install opencv-python-headless numpy.  Output is already committed in the kit; re-run only to tweak."""
import os, cv2, numpy as np
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets/branding/source_reference.jpg")
RES = os.path.join(ROOT, "android_overlay/res")
img = cv2.imread(SRC); H, W = img.shape[:2]

# ---- 1. silhouette of the 3D tile (front face via GrabCut + explicit right-hand side edge) ----
gc = np.full((H, W), cv2.GC_PR_BGD, np.uint8)
cv2.rectangle(gc, (80, 60), (700, 730), cv2.GC_PR_FGD, -1); cv2.rectangle(gc, (150, 150), (600, 620), cv2.GC_FGD, -1)
gc[:10, :] = cv2.GC_BGD; gc[:, :20] = cv2.GC_BGD; gc[-3:, :] = cv2.GC_BGD; gc[:260, 725:] = cv2.GC_BGD; gc[300:700, 735:] = cv2.GC_BGD; gc[:, 750:] = cv2.GC_BGD
cv2.grabCut(img, gc, None, np.zeros((1, 65)), np.zeros((1, 65)), 8, cv2.GC_INIT_WITH_MASK)
m = np.where((gc == cv2.GC_FGD) | (gc == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
side = np.array([(560, 30), (650, 38), (695, 70), (716, 130), (719, 330), (717, 560), (703, 670), (668, 722), (610, 748), (540, 752)], np.int32)
cv2.fillPoly(m, [side], 255)
n, lab, st, _ = cv2.connectedComponentsWithStats(m); k = 1 + np.argmax(st[1:, cv2.CC_STAT_AREA]); m = np.where(lab == k, 255, 0).astype(np.uint8)
cnt, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE); m[:] = 0; cv2.drawContours(m, cnt, -1, 255, -1)
m = cv2.GaussianBlur(m, (0, 0), 6.0); m = np.where(m > 127, 255, 0).astype(np.uint8)
m = cv2.erode(m, np.ones((3, 3), np.uint8), iterations=2)                    # drop white halo pixels at the edge

# ---- 2. clean colour at 2x: denoise, Lanczos upscale, gentle unsharp, small saturation lift ----
den = cv2.fastNlMeansDenoisingColored(img, None, 4, 4, 7, 21)
S = 2
up = cv2.resize(den, (W * S, H * S), interpolation=cv2.INTER_LANCZOS4)
blur = cv2.GaussianBlur(up, (0, 0), 1.6); up = cv2.addWeighted(up, 1.55, blur, -0.55, 0)
hsv = cv2.cvtColor(up, cv2.COLOR_BGR2HSV).astype(np.float32); hsv[..., 1] = np.clip(hsv[..., 1] * 1.07, 0, 255)
up = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)
alpha = cv2.resize(m, (W * S, H * S), interpolation=cv2.INTER_CUBIC); alpha = cv2.GaussianBlur(alpha, (0, 0), 1.3)
ys, xs = np.where(alpha > 127); x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
tile = np.dstack([up, alpha])[y0:y1, x0:x1]                                 # BGRA, tight crop
# the copper "d" (for the monochrome / themed icon)
b, g, r = [up[..., i].astype(int) for i in range(3)]
cu = ((r - g > 14) & (r - b > 28) & (r > 110)).astype(np.uint8) * 255
cu = cv2.morphologyEx(cu, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
cc, _ = cv2.findContours(cu, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
outer = np.zeros_like(cu); cv2.drawContours(outer, [max(cc, key=cv2.contourArea)], -1, 255, -1)
# counter (hole) = green showing through inside the glyph outline
hole = ((outer > 0) & (g > r + 2)).astype(np.uint8) * 255
hole = cv2.morphologyEx(hole, cv2.MORPH_OPEN, np.ones((21, 21), np.uint8))
hn, hl, hs, _ = cv2.connectedComponentsWithStats(hole)
if hn > 1: hole = np.where(hl == 1 + np.argmax(hs[1:, cv2.CC_STAT_AREA]), 255, 0).astype(np.uint8)
hole = cv2.dilate(hole, np.ones((9, 9), np.uint8))
d = cv2.subtract(outer, hole); d = cv2.GaussianBlur(d, (0, 0), 2.2); d = np.where(d > 127, 255, 0).astype(np.uint8); d = cv2.GaussianBlur(d, (0, 0), 1.2)
d = np.minimum(d, alpha)[y0:y1, x0:x1]
th, tw = tile.shape[:2]

def render(layer, canvas, scale):
    nh, nw = max(1, round(th * scale)), max(1, round(tw * scale))
    interp = cv2.INTER_AREA if scale < 1 else cv2.INTER_CUBIC
    l = cv2.resize(layer, (nw, nh), interpolation=interp)
    out = np.zeros((canvas, canvas, 4), np.uint8); oy, ox = (canvas - nh) // 2, (canvas - nw) // 2
    out[oy:oy + nh, ox:ox + nw] = l if l.ndim == 3 else np.dstack([np.full_like(l, 255)] * 3 + [l])
    return out

def save(path, arr):
    os.makedirs(os.path.dirname(path), exist_ok=True); cv2.imwrite(path, arr)

# ---- 3. adaptive icon (108dp @ xxxhdpi = 432px). Whole silhouette kept inside the 66dp safe circle ----
yy, xx = np.where(tile[..., 3] > 127); cy, cx = th / 2, tw / 2
R0 = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2).max()
sc = 142.0 / R0   # fits inside the 72dp visible circle (r=144px) of every launcher mask
save(f"{RES}/drawable-nodpi/ic_launcher_foreground.png", render(tile, 432, sc))
save(f"{RES}/drawable-nodpi/ic_launcher_monochrome.png", render(d, 432, sc))
# ---- 4. legacy launcher PNGs + splash/in-app logo + 512 store preview ----
for dens, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    s = min(0.94 * px / tw, 0.94 * px / th)
    leg = render(tile, px, s)
    save(f"{RES}/mipmap-{dens}/ic_launcher.png", leg)
save(f"{RES}/drawable-nodpi/splash_logo.png", render(tile, 360, min(0.95 * 360 / tw, 0.95 * 360 / th)))
save(os.path.join(ROOT, "assets/branding/logo.png"), render(tile, 256, min(0.95 * 256 / tw, 0.95 * 256 / th)))
store = np.full((512, 512, 3), (234, 242, 233), np.uint8); t512 = render(tile, 512, min(0.86 * 512 / tw, 0.86 * 512 / th))
a = t512[..., 3:4] / 255.0; store = (store * (1 - a) + t512[..., :3] * a).astype(np.uint8)
save(os.path.join(ROOT, "docs/icon_512_preview.png"), store)
print("tile", tw, th, "scale", round(sc, 3), "ok")
