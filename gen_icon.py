from PIL import Image, ImageDraw, ImageEnhance
import math

SIZE = 1024
img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))

# Background gradient — soft purple to warm pink to orange
for y in range(SIZE):
    t = y / SIZE
    if t < 0.6:
        tt = t / 0.6
        r = int(124 + (255 - 124) * tt)
        g = int(92 + (107 - 92) * tt)
        b = int(252 + (157 - 252) * tt)
    else:
        tt = (t - 0.6) / 0.4
        r = int(255 + (255 - 255) * tt)
        g = int(107 + (164 - 107) * tt)
        b = int(157 + (91 - 157) * tt)
    for x in range(SIZE):
        img.putpixel((x, y), (r, g, b, 255))

# Subtle radial highlight
center_x, center_y = SIZE // 2, SIZE // 3
for y in range(SIZE):
    for x in range(SIZE):
        dist = math.sqrt((x - center_x)**2 + (y - center_y)**2)
        if dist < 350:
            alpha = max(0, 1 - dist / 350) * 0.15
            px = img.getpixel((x, y))
            r = min(255, int(px[0] + 255 * alpha))
            g = min(255, int(px[1] + 255 * alpha))
            b = min(255, int(px[2] + 255 * alpha))
            img.putpixel((x, y), (r, g, b, 255))

draw = ImageDraw.Draw(img)

crown_cx, crown_cy = SIZE // 2, SIZE // 2 - 20
crown_w = 420

# Crown base
base_y = crown_cy + 80
draw.rounded_rectangle(
    [crown_cx - crown_w//2 + 20, base_y, crown_cx + crown_w//2 - 20, base_y + 90],
    radius=30, fill=(255, 255, 255, 230)
)

# Crown polygon — 3 peaks
peak_height = 240
points_base_y = base_y + 5
crown_points = [
    (crown_cx - crown_w//2 + 30, points_base_y),
    (crown_cx - crown_w//3, points_base_y - peak_height * 0.7),
    (crown_cx - crown_w//6, points_base_y - peak_height * 0.35),
    (crown_cx, points_base_y - peak_height),
    (crown_cx + crown_w//6, points_base_y - peak_height * 0.35),
    (crown_cx + crown_w//3, points_base_y - peak_height * 0.7),
    (crown_cx + crown_w//2 - 30, points_base_y),
]
draw.polygon(crown_points, fill=(255, 255, 255, 220))

# Gold jewels on peaks
jewel_color = (245, 166, 35, 255)
jewel_r = 22
for jx, jy in [
    (crown_cx - crown_w//3, points_base_y - peak_height * 0.7),
    (crown_cx, points_base_y - peak_height),
    (crown_cx + crown_w//3, points_base_y - peak_height * 0.7),
]:
    draw.ellipse([jx - jewel_r, jy - jewel_r, jx + jewel_r, jy + jewel_r], fill=jewel_color)

# Sparkle dots
for sx, sy, sr in [
    (crown_cx - 200, crown_cy - 190, 8),
    (crown_cx + 210, crown_cy - 150, 10),
    (crown_cx - 250, crown_cy + 60, 6),
    (crown_cx + 260, crown_cy + 90, 7),
    (crown_cx + 100, crown_cy - 240, 5),
    (crown_cx - 120, crown_cy - 260, 6),
]:
    draw.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=(255, 255, 255, 140))

out = "BirthdayQuest/BirthdayQuest/Assets.xcassets/AppIcon.appiconset"
img.save(f"{out}/AppIcon.png", 'PNG')
print("Light icon saved!")

dark = ImageEnhance.Brightness(img).enhance(0.7)
dark.save(f"{out}/AppIcon-dark.png", 'PNG')
print("Dark icon saved!")
