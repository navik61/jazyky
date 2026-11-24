#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""
intro-obrazek.py — složí úvodní obrázek pro volbu --intro.

Vezme fotografii, ořízne ji na 1920×1080, nahoru vloží vlajky jazyků a dolů
text z intro.txt (každý neprázdný řádek = jeden odstavec). Pod vlajkami a textem
je tmavý přechod, aby byly čitelné na jakékoli fotce.

Použití:
  ./intro-obrazek.py --obrazek intro/louka.jpg --text intro.txt \\
                     --vystup intro/.vygenerovano/intro.jpg --vlajky "🇩🇪 🇬🇧 🇮🇹"

Spouští ho spolecne.sh (_intro_priprav) jen když se změnil text, fotka, vlajky
nebo tento skript. Ručně ho není potřeba volat.
"""

import argparse
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

SIRKA, VYSKA = 1920, 1080
def fc_match(vzor: str, musi_obsahovat: str = "") -> str | None:
    """Cesta k fontu přes fontconfig (cesty se mezi distribucemi liší)."""
    try:
        cesta = subprocess.run(["fc-match", "-f", "%{file}", vzor],
                               capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    if cesta and Path(cesta).exists() and musi_obsahovat.lower() in Path(cesta).name.lower():
        return cesta
    return None


# fc-match vrátí vždy nějaký font — u emoji ověřit, že je to opravdu barevný emoji font
FONT_EMOJI = fc_match("Noto Color Emoji", "emoji")
FONTY_TEXT = [c for c in (fc_match("Noto Sans:semibold", "noto"), fc_match("Noto Sans:bold", "noto"),
                          fc_match("DejaVu Sans:bold"), fc_match("sans-serif:bold")) if c]
VYSKA_VLAJKY = 96          # px po zmenšení
OKRAJ = 140                # vodorovný okraj textu
MAX_VYSKA_TEXTU = 400      # text se zmenšuje, dokud se nevejde


def font_textu(velikost: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for cesta in FONTY_TEXT:
        if Path(cesta).exists():
            return ImageFont.truetype(cesta, velikost)
    return ImageFont.load_default(velikost)


def prechod(vyska: int, odshora: bool, max_alfa: int) -> Image.Image:
    """Černý pruh s průhledností klesající od okraje obrázku ke středu."""
    maska = Image.new("L", (1, vyska))
    for y in range(vyska):
        t = y / max(vyska - 1, 1)
        alfa = (1 - t) if odshora else t
        maska.putpixel((0, y), int(max_alfa * alfa ** 1.4))
    maska = maska.resize((SIRKA, vyska))
    pruh = Image.new("RGBA", (SIRKA, vyska), (0, 0, 0, 0))
    pruh.putalpha(maska)
    return pruh


def vlajky_obrazek(vlajky: list[str]) -> Image.Image | None:
    if not vlajky or not FONT_EMOJI:
        return None
    font = ImageFont.truetype(FONT_EMOJI, 109)   # Noto Color Emoji má jen velikost 109
    kusy = []
    for v in vlajky:
        im = Image.new("RGBA", (160, 140), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((4, 4), v, font=font, embedded_color=True)
        im = im.crop(im.getbbox() or (0, 0, 1, 1))
        sirka = round(im.width * VYSKA_VLAJKY / im.height)
        kusy.append(im.resize((sirka, VYSKA_VLAJKY), Image.Resampling.LANCZOS))
    mezera = 36
    celkem = sum(k.width for k in kusy) + mezera * (len(kusy) - 1)
    pas = Image.new("RGBA", (celkem, VYSKA_VLAJKY), (0, 0, 0, 0))
    x = 0
    for k in kusy:
        pas.alpha_composite(k, (x, 0))
        x += k.width + mezera
    return pas


def zalom(text: str, font, sirka: int) -> list[str]:
    radky, akt = [], ""
    for slovo in text.split():
        zkus = f"{akt} {slovo}".strip()
        if font.getlength(zkus) <= sirka or not akt:
            akt = zkus
        else:
            radky.append(akt)
            akt = slovo
    if akt:
        radky.append(akt)
    return radky


def rozvrhni_text(odstavce: list[str]):
    """Najde největší písmo, se kterým se text vejde do MAX_VYSKA_TEXTU.
    Do velikosti 40 px dává přednost tomu, aby se žádná věta nezalomila."""
    vysledek = None
    for velikost in range(52, 23, -2):
        font = font_textu(velikost)
        radkovani = round(velikost * 1.28)
        mezera = round(velikost * 0.55)
        bloky = [zalom(o, font, SIRKA - 2 * OKRAJ) for o in odstavce]
        vyska = sum(len(b) for b in bloky) * radkovani + mezera * (len(bloky) - 1)
        vysledek = (font, bloky, radkovani, mezera)
        bez_zalomeni = all(len(b) == 1 for b in bloky)
        if vyska <= MAX_VYSKA_TEXTU and (bez_zalomeni or velikost <= 40):
            break
    assert vysledek is not None
    return vysledek


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--obrazek", required=True, type=Path)
    ap.add_argument("--text", required=True, type=Path)
    ap.add_argument("--vystup", required=True, type=Path)
    ap.add_argument("--vlajky", default="", help="vlajky (emoji) oddělené mezerou")
    args = ap.parse_args()

    foto = ImageOps.exif_transpose(Image.open(args.obrazek)).convert("RGB")
    foto = ImageOps.fit(foto, (SIRKA, VYSKA), Image.Resampling.LANCZOS, centering=(0.5, 0.5))
    obr = foto.convert("RGBA")

    # Tmavé přechody nahoře a dole kvůli čitelnosti
    obr.alpha_composite(prechod(260, True, 150), (0, 0))
    obr.alpha_composite(prechod(560, False, 215), (0, VYSKA - 560))

    pas = vlajky_obrazek(args.vlajky.split())
    if pas is not None:
        stin = Image.new("RGBA", pas.size, (0, 0, 0, 0))
        stin.putalpha(pas.getchannel("A").point(lambda a: a * 0.55))
        stin = stin.filter(ImageFilter.GaussianBlur(6))
        x = (SIRKA - pas.width) // 2
        obr.alpha_composite(stin, (x + 4, 58))
        obr.alpha_composite(pas, (x, 52))

    odstavce = [r.strip() for r in args.text.read_text(encoding="utf-8").splitlines() if r.strip()]
    if odstavce:
        font, bloky, radkovani, mezera = rozvrhni_text(odstavce)
        vyska = sum(len(b) for b in bloky) * radkovani + mezera * (len(bloky) - 1)
        y = VYSKA - 70 - vyska
        vrstva = Image.new("RGBA", obr.size, (0, 0, 0, 0))
        kresli = ImageDraw.Draw(vrstva)
        for blok in bloky:
            for radek in blok:
                x = (SIRKA - font.getlength(radek)) / 2
                kresli.text((x + 2, y + 3), radek, font=font, fill=(0, 0, 0, 200))
                kresli.text((x, y), radek, font=font, fill=(255, 255, 255, 255))
                y += radkovani
            y += mezera
        obr.alpha_composite(vrstva)

    args.vystup.parent.mkdir(parents=True, exist_ok=True)
    docasny = args.vystup.with_suffix(".tmp.jpg")
    obr.convert("RGB").save(docasny, "JPEG", quality=92)
    docasny.replace(args.vystup)


if __name__ == "__main__":
    main()
