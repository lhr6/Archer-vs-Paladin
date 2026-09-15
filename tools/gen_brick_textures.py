# 程序化生成无缝城镇砖块地板贴图（color/normal/roughness/ao）。
# 砖面平整（没有地形起伏），只在砖缝处压凹——贴在平地上不虚假。
# 输出：assets/textures/ground/brick_{color,normal,roughness,ao}.jpg

from PIL import Image
import numpy as np
import os

W = H = 512
BRICK_W, BRICK_H = 64, 32   # 经典砖长:砖高 = 2:1
GAP = 3                      # 砖缝宽（像素）
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures", "ground")

rng = np.random.default_rng(42)

yy, xx = np.mgrid[0:H, 0:W]
row = yy // BRICK_H
row_offset = (row % 2) * (BRICK_W // 2)          # 工字铺：奇数行错半砖
lx = (xx + row_offset) % BRICK_W
ly = yy % BRICK_H
gap = (lx < GAP) | (lx >= BRICK_W - GAP) | (ly < GAP) | (ly >= BRICK_H - GAP)

# ---- height（砖面 0，砖缝压深）----
height = np.zeros((H, W), dtype=np.float32)
height[gap] = -0.55

# ---- albedo ----
# 每块砖一个随机色阶（接缝处整体暗）
brick_id_x = ((xx + row_offset) // BRICK_W).astype(np.int32)
brick_id_y = row.astype(np.int32)
brick_var = rng.uniform(0.82, 1.15, size=(brick_id_y.max() + 1, brick_id_x.max() + 1))
var = brick_var[brick_id_y, brick_id_x]
base = np.array([158, 102, 74], dtype=np.float32)   # 暖砖红褐
albedo = base[None, None, :] * var[:, :, None]
# 砖面再加一点噪点，避免塑料感
noise = rng.normal(0, 7, (H, W, 1))
albedo = np.clip(albedo + noise, 0, 255)
albedo[gap] = np.array([58, 53, 48])                # 砖缝深灰
Image.fromarray(albedo.astype(np.uint8)).save(os.path.join(OUT, "brick_color.jpg"), quality=92)

# ---- normal（OpenGL 惯例，砖缝压凹）----
gx = np.zeros_like(height)
gy = np.zeros_like(height)
gx[:, 1:] = height[:, 1:] - height[:, :-1]
gy[1:, :] = height[1:, :] - height[:-1, :]
nx = -gx
ny = -gy
nz = np.ones_like(height)
norm = np.sqrt(nx * nx + ny * ny + nz * nz)
nx /= norm; ny /= norm; nz /= norm
nrgb = ((np.stack([nx, ny, nz], axis=-1) * 0.5 + 0.5) * 255.0)
Image.fromarray(nrgb.astype(np.uint8)).save(os.path.join(OUT, "brick_normal.jpg"), quality=92)

# ---- roughness：砖面 0.85，砖缝更糙 1.0 ----
rough = np.full((H, W), int(0.85 * 255), dtype=np.uint8)
rough[gap] = 255
Image.fromarray(rough).save(os.path.join(OUT, "brick_roughness.jpg"), quality=92)

# ---- ao：砖缝暗角 ----
ao = np.full((H, W), 255, dtype=np.uint8)
ao[gap] = 150
Image.fromarray(ao).save(os.path.join(OUT, "brick_ao.jpg"), quality=92)

print("生成完成：brick_color/normal/roughness/ao.jpg ->", os.path.normpath(OUT))
