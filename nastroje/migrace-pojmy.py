#!/usr/bin/env python3
"""
migrace-pojmy.py — jednorázový převod starých slovníků „cizí — česky“ na tabulky pojmů.

Vstup (staré soubory v kořeni projektu):
  <jazyk>_slova.txt, golf_<jazyk>.txt        řádek: cizí slovo — český význam
  fraze/<starý slovník>.tsv                  řádek slovníku TAB věta TAB český překlad

Výstup:
  slovnik/obecne.tsv, slovnik/golf.tsv       id TAB cs TAB de TAB en TAB it TAB fr TAB es TAB ru
  fraze/<sada>-<jazyk>.tsv                   id TAB cs … ru  (paralelní věty: sloupec <jazyk>
                                             je věta v cílovém jazyce, ostatní její překlady)

Pojem = jeden český význam (porovnává se bez ohledu na velikost písmen). Když má jeden
slovník pro stejný význam víc slov, spojí se lomítkem („a / b“ — čtou se zvlášť).
Čeština jako cílový jazyk dostane věty zdarma: český překlad věty z jiného jazyka
je česká věta a původní věta je její překlad.
"""
import sys
from pathlib import Path

KOREN = Path(__file__).resolve().parent.parent
JAZYKY = ["cs", "de", "en", "it", "fr", "es", "ru"]
# Pořadí určuje číslování pojmů: it/fr/es/ru vznikly podle stejné osnovy, pak de, en
# Staré soubory už v projektu nejsou (jsou v historii gitu, commit před převodem na pojmy).
SADY = {
    "obecne": {"it": "italstina_slova.txt", "fr": "francouzstina_slova.txt", "es": "spanelstina_slova.txt",
               "ru": "rustina_slova.txt", "de": "nemcina_slova.txt", "en": "anglictina_slova.txt"},
    "golf": {"de": "golf_nemcina.txt", "en": "golf_anglictina.txt", "it": "golf_italstina.txt"},
}
# Preferované zdroje české věty (pro cs jako cílový jazyk)
PORADI_CS_VET = ["it", "fr", "es", "de", "en", "ru"]


def klic(cs: str) -> str:
    return " ".join(cs.split()).lower()


def zapis_tsv(cesta: Path, hlavicka: list[str], radky: list[list[str]]) -> None:
    cesta.parent.mkdir(parents=True, exist_ok=True)
    # Prosté TSV bez uvozování: tabulátor a konec řádku se v polích nahradí mezerou
    with cesta.open("w", encoding="utf-8") as f:
        f.write("\t".join(hlavicka) + "\n")
        for r in radky:
            f.write("\t".join(" ".join(x.split()) for x in r) + "\n")


def migruj_sadu(sada: str, soubory: dict[str, str], prefix: str) -> None:
    pojmy: dict[str, dict] = {}          # klíč → {"cs": text, jazyk: [slova]}
    radek_na_klic: dict[tuple[str, str], str] = {}   # (jazyk, řádek slovníku) → klíč

    for jazyk, nazev in soubory.items():
        for radek in (KOREN / nazev).read_text(encoding="utf-8").splitlines():
            if " — " not in radek:
                continue
            cizi, cs = (x.strip() for x in radek.split(" — ", 1))
            if not cizi or not cs:
                continue
            k = klic(cs)
            p = pojmy.setdefault(k, {"cs": cs})
            slova = p.setdefault(jazyk, [])
            if cizi not in slova:
                slova.append(cizi)
            radek_na_klic[(jazyk, radek.strip())] = k

    ids = {k: f"{prefix}{i:05d}" for i, k in enumerate(pojmy, 1)}
    tabulka = [[ids[k], p["cs"]] + [" / ".join(p.get(j, [])) for j in JAZYKY[1:]] for k, p in pojmy.items()]
    zapis_tsv(KOREN / "slovnik" / f"{sada}.tsv", ["id"] + JAZYKY, tabulka)

    # Věty: pro každý pojem a cílový jazyk první věta (u spojených slov jen jedna)
    vety: dict[str, dict[str, tuple[str, str]]] = {j: {} for j in JAZYKY}
    for jazyk, nazev in soubory.items():
        stary = KOREN / "fraze" / nazev.replace(".txt", ".tsv")
        if not stary.exists():
            continue
        for r in stary.read_text(encoding="utf-8").splitlines():
            pole = r.split("\t")
            if len(pole) < 3 or not pole[1].strip():
                continue
            k = radek_na_klic.get((jazyk, pole[0].strip()))
            if k is not None:
                vety[jazyk].setdefault(ids[k], (pole[1].strip(), pole[2].strip()))

    # Čeština jako cíl: česká věta + původní věta jako její překlad
    for j in PORADI_CS_VET:
        for pid, (veta, cs_veta) in vety[j].items():
            if cs_veta:
                vety["cs"].setdefault(pid, (cs_veta, f"{j}\t{veta}"))

    for cil in JAZYKY:
        radky = []
        for pid, (veta, preklad) in sorted(vety[cil].items()):
            sloupce = {j: "" for j in JAZYKY}
            sloupce[cil] = veta
            if cil == "cs":
                jazyk_prekladu, text = preklad.split("\t", 1)
                sloupce[jazyk_prekladu] = text
            else:
                sloupce["cs"] = preklad
            radky.append([pid] + [sloupce[j] for j in JAZYKY])
        if radky:
            zapis_tsv(KOREN / "fraze" / f"{sada}-{cil}.tsv", ["id"] + JAZYKY, radky)

    print(f"{sada}: {len(pojmy)} pojmů, věty: " +
          ", ".join(f"{j} {len(vety[j])}" for j in JAZYKY))


def main() -> int:
    if (KOREN / "slovnik" / "obecne.tsv").exists() and "--prepsat" not in sys.argv:
        print("slovnik/obecne.tsv už existuje (--prepsat = přepsat)", file=sys.stderr)
        return 1
    migruj_sadu("obecne", SADY["obecne"], "o")
    migruj_sadu("golf", SADY["golf"], "g")
    return 0


if __name__ == "__main__":
    sys.exit(main())
