from pathlib import Path
import math
import subprocess
import textwrap

from PIL import Image, ImageDraw, ImageFont


OUT = Path(__file__).resolve().parent
W, H = 1920, 1080
FPS = 30


def font(size, bold=False):
    candidates = [
        r"C:\Windows\Fonts\seguisb.ttf" if bold else r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


F_TITLE = font(62, True)
F_SUB = font(34, False)
F_BODY = font(38, False)
F_BODY_BOLD = font(40, True)
F_SMALL = font(26, False)
F_TINY = font(22, False)


SLIDES = [
    {
        "title": "Uzima VM access for researchers",
        "subtitle": "Login, RDP access, and token refresh workflow",
        "bullets": [
            "Use the portal before opening Remote Desktop.",
            "Use Fix My RDP Access when the VM is running but RDP fails.",
            "Use Refresh Token when Fabric or data access returns 401.",
        ],
        "caption": "This short guide shows the normal path from portal login to RDP access, plus what to do when a 401 token error appears.",
        "duration": 7,
    },
    {
        "title": "1. Open the portal and sign in",
        "subtitle": "Use your approved AKU account",
        "bullets": [
            "Click Sign in.",
            "Enter your approved email and password.",
            "If your account is pending, contact the CDIO team before continuing.",
        ],
        "caption": "First, open the Uzima VM Control Portal and sign in with your approved AKU account.",
        "duration": 7,
    },
    {
        "title": "2. Check VM status",
        "subtitle": "The VM must be running before RDP will work",
        "bullets": [
            "Click Check Status.",
            "If the VM is stopped, click Start VM.",
            "Wait for the status to show running before fixing RDP access.",
        ],
        "caption": "After signing in, check the VM status. If it is stopped, start it and wait until it shows running.",
        "duration": 8,
    },
    {
        "title": "3. Fix My RDP Access",
        "subtitle": "One click handles the common network blockers",
        "bullets": [
            "Click Fix My RDP Access.",
            "The portal checks your public IP and VM power state.",
            "It removes custom Deny rules, allows your IP for RDP, checks RDP health, and requests JIT.",
        ],
        "caption": "When the VM is running, click Fix My RDP Access. The portal will repair the most common RDP blockers automatically.",
        "duration": 9,
    },
    {
        "title": "4. Read the access result",
        "subtitle": "Green means ready, amber means review",
        "bullets": [
            "VM power: confirms the VM is running.",
            "Deny rules: confirms blocking rules were removed.",
            "RDP allow rule: confirms your IP is allowed.",
            "Windows RDP service and JIT: confirms the final access checks.",
        ],
        "caption": "Review the result panel. Green steps are complete. Amber warnings explain what still needs attention.",
        "duration": 8,
    },
    {
        "title": "5. Connect with Remote Desktop",
        "subtitle": "Use the downloaded RDP file or copy the host",
        "bullets": [
            "Click RDP File, or click Copy Host.",
            "Open the file in Microsoft Remote Desktop.",
            "Sign in with your VM username and password.",
        ],
        "caption": "When access is updated, download the RDP file or copy the host, then connect with Microsoft Remote Desktop.",
        "duration": 8,
    },
    {
        "title": "6. Keep your session active",
        "subtitle": "Avoid unexpected auto-shutdown",
        "bullets": [
            "Click Working if you are still using the VM.",
            "Use +30 Min or +1 Hour when running longer analyses.",
            "Only keep the VM running while work is active.",
        ],
        "caption": "While working, use the session controls so the auto-shutdown guard knows the VM is still in use.",
        "duration": 7,
    },
    {
        "title": "7. If you see a 401 error",
        "subtitle": "Refresh the Fabric token from the portal",
        "bullets": [
            "A 401 usually means the access token expired.",
            "Return to the portal while the VM is running.",
            "Click Refresh Token, wait for success, then retry your notebook, R, or Python command.",
        ],
        "caption": "If Fabric or data access returns 401 unauthorized, go back to the portal and click Refresh Token, then retry your work.",
        "duration": 9,
    },
    {
        "title": "8. If RDP still fails",
        "subtitle": "Use the result panel to report the exact failed step",
        "bullets": [
            "Run Fix My RDP Access again if your public IP changed.",
            "If the VM is stopped, start it first.",
            "If the RDP service check warns, send the result to CDIO.",
            "Do not share passwords or tokens in screenshots.",
        ],
        "caption": "If RDP still fails, run the fix again if your network changed. Otherwise, send the failed step to CDIO without sharing passwords or tokens.",
        "duration": 9,
    },
    {
        "title": "Quick checklist",
        "subtitle": "The safe order every time",
        "bullets": [
            "Sign in.",
            "Check or start the VM.",
            "Click Fix My RDP Access.",
            "Open the RDP file.",
            "Click Refresh Token only when you see a 401 error.",
        ],
        "caption": "The checklist is simple: sign in, check or start the VM, fix RDP access, connect, and refresh the token only when a 401 appears.",
        "duration": 8,
    },
]


def wrap(draw, text, fnt, max_width):
    words = text.split()
    lines, current = [], ""
    for word in words:
        test = f"{current} {word}".strip()
        if draw.textbbox((0, 0), test, font=fnt)[2] <= max_width:
            current = test
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def rounded(draw, xy, fill, outline=None, radius=26, width=2):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def draw_portal_card(draw, x, y, w, h, active_index):
    rounded(draw, (x, y, x + w, y + h), "#ffffff", "#cbd5e1", 22, 2)
    draw.rectangle((x, y, x + w, y + 74), fill="#081827")
    draw.text((x + 28, y + 18), "Uzima VM Control Portal", fill="#ffffff", font=font(28, True))
    labels = ["Sign in", "Check Status", "Fix RDP", "RDP File", "Refresh Token"]
    row_y = y + 118
    for i, label in enumerate(labels):
        cy = row_y + i * 82
        color = "#0f766e" if i <= active_index else "#e2e8f0"
        text_color = "#ffffff" if i <= active_index else "#334155"
        draw.ellipse((x + 34, cy, x + 78, cy + 44), fill=color)
        draw.text((x + 49, cy + 6), str(i + 1), fill=text_color, font=font(22, True))
        draw.text((x + 98, cy + 4), label, fill="#0f172a", font=font(28, True if i == active_index else False))
        if i < len(labels) - 1:
            draw.line((x + 56, cy + 44, x + 56, cy + 82), fill="#94a3b8", width=3)


def make_slide(slide, idx):
    img = Image.new("RGB", (W, H), "#f8fafc")
    draw = ImageDraw.Draw(img)

    draw.rectangle((0, 0, W, 122), fill="#081827")
    draw.text((70, 36), "UZIMA VM CONTROL", fill="#ffffff", font=font(32, True))
    draw.text((W - 340, 42), "Researcher guide", fill="#dbeafe", font=font(26, False))

    draw.text((80, 172), slide["title"], fill="#081827", font=F_TITLE)
    draw.text((84, 252), slide["subtitle"], fill="#0f766e", font=F_SUB)

    y = 350
    for bullet in slide["bullets"]:
        rounded(draw, (88, y, 104, y + 16), "#0f766e", None, 8, 0)
        lines = wrap(draw, bullet, F_BODY, 890)
        for line in lines:
            draw.text((130, y - 16), line, fill="#1e293b", font=F_BODY)
            y += 50
        y += 28

    active = min(idx, 4)
    draw_portal_card(draw, 1180, 225, 610, 575, active)

    caption = slide["caption"]
    rounded(draw, (80, 870, 1840, 1010), "#e0f2fe", "#bae6fd", 20, 2)
    cap_lines = wrap(draw, caption, F_SMALL, 1660)
    cy = 900
    draw.text((112, cy), "Narration:", fill="#155e75", font=font(26, True))
    cy += 38
    for line in cap_lines:
        draw.text((112, cy), line, fill="#0f172a", font=F_SMALL)
        cy += 32

    progress_w = 1760
    draw.rectangle((80, 1034, 1840, 1044), fill="#cbd5e1")
    draw.rectangle((80, 1034, 80 + int(progress_w * ((idx + 1) / len(SLIDES))), 1044), fill="#0f766e")

    path = OUT / f"slide_{idx + 1:02d}.png"
    img.save(path)
    return path


def srt_time(seconds):
    ms = int(round((seconds - math.floor(seconds)) * 1000))
    total = int(math.floor(seconds))
    h = total // 3600
    m = (total % 3600) // 60
    s = total % 60
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def write_support_files(slide_paths):
    concat_lines = []
    srt = []
    md = ["# Uzima VM researcher training narration", ""]
    t = 0
    for i, (slide, path) in enumerate(zip(SLIDES, slide_paths), start=1):
        concat_lines.append(f"file '{path.as_posix()}'")
        concat_lines.append(f"duration {slide['duration']}")
        srt.append(str(i))
        srt.append(f"{srt_time(t)} --> {srt_time(t + slide['duration'])}")
        srt.append(slide["caption"])
        srt.append("")
        md.append(f"## Slide {i}: {slide['title']}")
        md.append(slide["caption"])
        md.append("")
        t += slide["duration"]
    concat_lines.append(f"file '{slide_paths[-1].as_posix()}'")
    (OUT / "slides.ffconcat").write_text("\n".join(concat_lines), encoding="utf-8")
    (OUT / "uzima_vm_researcher_training.srt").write_text("\n".join(srt), encoding="utf-8")
    (OUT / "narration_script.md").write_text("\n".join(md), encoding="utf-8")


def build_video():
    video = OUT / "uzima_vm_researcher_training.mp4"
    cmd = [
        "ffmpeg",
        "-y",
        "-safe",
        "0",
        "-f",
        "concat",
        "-i",
        str(OUT / "slides.ffconcat"),
        "-vf",
        f"fps={FPS},format=yuv420p",
        "-c:v",
        "libx264",
        "-preset",
        "medium",
        "-crf",
        "18",
        "-movflags",
        "+faststart",
        str(video),
    ]
    subprocess.run(cmd, check=True)
    return video


def main():
    slide_paths = [make_slide(slide, idx) for idx, slide in enumerate(SLIDES)]
    write_support_files(slide_paths)
    video = build_video()
    print(video)


if __name__ == "__main__":
    main()
