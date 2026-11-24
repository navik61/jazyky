#!/usr/bin/env python3
"""
generuj-fraze.py — vygeneruje vzorové fráze ke slovíčkům lokálním LLM
(llama.cpp server s OpenAI API, výchozí http://127.0.0.1:8080).

Výstup: fraze/<slovnik>.tsv, řádek = <řádek slovníku> TAB <fráze> TAB <český překlad fráze>
Lze kdykoli přerušit (Ctrl+C) a spustit znovu — hotová slovíčka se přeskočí.

Použití:
  ./generuj-fraze.py                       # všechny slovníky
  ./generuj-fraze.py anglictina_slova.txt  # jen vybrané
  ./generuj-fraze.py --limit 20            # zkouška: jen 20 slovíček z každého
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ADRESAR = Path(__file__).resolve().parent
ADRESAR_FRAZI = ADRESAR / "fraze"
ODDELOVAC = " — "

SLOVNIKY = {
    "nemcina_slova.txt":    ("German", False),
    "anglictina_slova.txt": ("English", False),
    "italstina_slova.txt":  ("Italian", False),
    "francouzstina_slova.txt": ("French", False),
    "spanelstina_slova.txt": ("Spanish", False),
    "rustina_slova.txt":    ("Russian", False),
    "golf_nemcina.txt":     ("German", True),
    "golf_anglictina.txt":  ("English", True),
    "golf_italstina.txt":   ("Italian", True),
}

SCHEMA = {
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "i": {"type": "integer"},
                    "phrase": {"type": "string"},
                    "cs": {"type": "string"},
                },
                "required": ["i", "phrase", "cs"],
            },
        }
    },
    "required": ["items"],
}


PRIKLADY = {
    "German": ("das Fenster — okno", "Kannst du bitte das Fenster im Wohnzimmer aufmachen?",
               "Můžeš prosím otevřít okno v obýváku?"),
    "English": ("to borrow — půjčit si", "Can I borrow your umbrella until tomorrow morning?",
                "Můžu si půjčit tvůj deštník do zítřejšího rána?"),
    "Italian": ("la chiave — klíč", "Non trovo più la chiave della macchina.",
                "Nemůžu najít klíč od auta."),
    "French": ("la clé — klíč", "Je ne trouve plus la clé de la voiture.",
               "Nemůžu najít klíč od auta."),
    "Spanish": ("la llave — klíč", "No encuentro la llave del coche.",
                "Nemůžu najít klíč od auta."),
    "Russian": ("ключ — klíč", "Я не могу найти ключ от машины.",
                "Nemůžu najít klíč od auta."),
}
PRIKLADY_GOLF = {
    "German": ("das Grün — green", "Der Ball ist direkt neben der Fahne auf dem Grün gelandet.",
               "Míček dopadl na green přímo vedle praporku."),
    "English": ("the fairway — fairway", "My drive went straight down the middle of the fairway.",
                "Můj drive letěl přímo doprostřed fairwaye."),
    "Italian": ("il bunker — bunkr", "Purtroppo la mia palla è finita nel bunker vicino al green.",
                "Můj míček bohužel skončil v bunkru u greenu."),
}


def prompt(jazyk: str, golf: bool, polozky: list[str]) -> str:
    kontext = (
        " The vocabulary is golf terminology, so set every sentence in a realistic golf situation"
        " (on the course, in a lesson, at the clubhouse, in a tournament)."
        if golf else ""
    )
    vzor = (PRIKLADY_GOLF if golf else PRIKLADY)[jazyk]
    radky = "\n".join(f"{i}. {p}" for i, p in enumerate(polozky, 1))
    return (
        f"You are an experienced {jazyk} teacher writing flashcards for a Czech adult learner.\n"
        f"Each numbered entry is '<{jazyk} word> — <Czech meaning>'.{kontext}\n\n"
        f"For EVERY entry write one example sentence in {jazyk}:\n"
        f"- a complete sentence of 6 to 14 words, natural everyday {jazyk}, level A2–B1\n"
        f"- it must contain the {jazyk} word (any inflected form) in the meaning given by the Czech text\n"
        f"- show a typical, useful context (who, where, why), not a trivial definition like 'X is nice'\n"
        f"- if the entry lists alternatives separated by '/', use the first one\n"
        f"- the sentence must NOT repeat the entry and must not contain '—'\n\n"
        f"Then translate the sentence into natural, idiomatic Czech, as a native speaker would say it:\n"
        f"- omit subject pronouns (já, ty, on, ona, ono, my, vy, oni) unless they are stressed\n"
        f"- never copy notes in parentheses from the entry\n"
        f"- the Czech verb must agree in person, number and gender with the subject (she = ona → 'dala', you = ty → 'udělal jsi')\n"
        f"- correct Czech spelling and diacritics\n\n"
        f"Example entry: {vzor[0]}\n"
        f"Example result: {{\"i\": 1, \"phrase\": \"{vzor[1]}\", \"cs\": \"{vzor[2]}\"}}\n\n"
        f"Return JSON: {{\"items\": [{{\"i\": <number>, \"phrase\": \"...\", \"cs\": \"...\"}}, ...]}} "
        f"with exactly one item per entry, same numbering.\n\nEntries:\n{radky}"
    )


def zavolej(url: str, text: str, timeout: int, uvazovani: str) -> list[dict]:
    telo = {
        "messages": [{"role": "user", "content": text}],
        "temperature": 0.4,
        "max_tokens": 8192,
        "chat_template_kwargs": {"reasoning_effort": uvazovani},
        "response_format": {"type": "json_schema", "json_schema": {"name": "fraze", "schema": SCHEMA}},
    }
    pozadavek = urllib.request.Request(
        f"{url}/v1/chat/completions",
        data=json.dumps(telo).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(pozadavek, timeout=timeout) as odpoved:
        data = json.load(odpoved)
    obsah = data["choices"][0]["message"]["content"]
    return json.loads(obsah)["items"]


def cisty(text: str) -> str:
    # TAB a konce řádků by rozbily formát souboru
    return " ".join(str(text).replace("\t", " ").split()).strip().strip('"„“')


def platna(radek: str, fraze: str, cs: str) -> bool:
    """Základní kontrola kvality — odmítnuté se zkusí znovu při dalším průchodu."""
    # Zkopírované heslo „slovo — překlad“. Samotná pomlčka ve větě nevadí
    # (ruština ji píše běžně: „Счастье — это…“), fráze se ukládají oddělené tabulátorem.
    if fraze == radek or radek in fraze or radek in cs:
        return False
    if not 5 <= len(fraze.split()) <= 22 or len(cs.split()) < 3:
        return False
    if "(" in cs and "(" not in fraze:   # zkopírovaná poznámka z hesla
        return False
    return True


def nacti_hotove(soubor: Path) -> set[str]:
    if not soubor.exists():
        return set()
    return {r.split("\t", 1)[0] for r in soubor.read_text(encoding="utf-8").splitlines() if "\t" in r}


def zpracuj(nazev: str, args) -> None:
    jazyk, golf = SLOVNIKY[nazev]
    zdroj = ADRESAR / nazev
    cil = ADRESAR_FRAZI / nazev.replace(".txt", ".tsv")

    radky = list(dict.fromkeys(
        r.strip() for r in zdroj.read_text(encoding="utf-8").splitlines() if ODDELOVAC in r
    ))
    hotove = nacti_hotove(cil)
    zbyva = [r for r in radky if r not in hotove]
    if args.limit:
        zbyva = zbyva[: max(0, args.limit - len(hotove & set(radky)))]

    print(f"\n▶ {nazev}: hotovo {len(hotove)}/{len(radky)}, zbývá {len(zbyva)}", flush=True)
    if not zbyva:
        return

    start = time.time()
    zpracovano = 0
    with cil.open("a", encoding="utf-8") as vystup:
        for od in range(0, len(zbyva), args.davka):
            davka = zbyva[od: od + args.davka]
            for pokus in range(1, 4):
                try:
                    polozky = zavolej(args.url, prompt(jazyk, golf, davka), args.timeout, args.uvazovani)
                    break
                except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, KeyError) as chyba:
                    print(f"  ! pokus {pokus}/3 selhal: {chyba}", file=sys.stderr, flush=True)
                    time.sleep(3 * pokus)
            else:
                print("  ! dávka přeskočena, zkusí se při dalším spuštění", file=sys.stderr)
                continue

            podle_cisla = {p.get("i"): p for p in polozky if isinstance(p, dict)}
            ulozeno = 0
            odmitnuto = 0
            for i, radek in enumerate(davka, 1):
                p = podle_cisla.get(i)
                if not p:
                    continue
                fraze, cs = cisty(p.get("phrase", "")), cisty(p.get("cs", ""))
                if not platna(radek, fraze, cs):
                    odmitnuto += 1
                    continue
                vystup.write(f"{radek}\t{fraze}\t{cs}\n")
                ulozeno += 1
            vystup.flush()

            zpracovano += len(davka)
            rychlost = zpracovano / (time.time() - start)
            zbyva_s = (len(zbyva) - zpracovano) / rychlost if rychlost else 0
            print(f"  {zpracovano}/{len(zbyva)}  (+{ulozeno}, odmítnuto {odmitnuto})  ~{zbyva_s / 60:.0f} min zbývá", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generování vzorových frází ke slovíčkům")
    parser.add_argument("slovniky", nargs="*", help="názvy slovníků (výchozí: všechny)")
    parser.add_argument("--url", default="http://127.0.0.1:8080", help="adresa llama.cpp serveru")
    parser.add_argument("--davka", type=int, default=20, help="slovíček v jednom dotazu (výchozí 20)")
    parser.add_argument("--limit", type=int, default=0, help="max. slovíček na slovník (zkouška)")
    parser.add_argument("--uvazovani", default="medium", choices=["low", "medium", "high"],
                        help="úroveň uvažování gpt-oss (výchozí medium)")
    parser.add_argument("--pruchody", type=int, default=2,
                        help="kolikrát zkusit odmítnuté/chybějící znovu (výchozí 2)")
    parser.add_argument("--timeout", type=int, default=600, help="timeout dotazu v sekundách")
    args = parser.parse_args()

    nazvy = args.slovniky or list(SLOVNIKY)
    for n in nazvy:
        if n not in SLOVNIKY:
            sys.exit(f"Neznámý slovník: {n} (možnosti: {', '.join(SLOVNIKY)})")
    ADRESAR_FRAZI.mkdir(exist_ok=True)

    try:
        for n in nazvy:
            for _ in range(args.pruchody):
                zpracuj(n, args)
    except KeyboardInterrupt:
        print("\nPřerušeno — při dalším spuštění se pokračuje.", file=sys.stderr)
        sys.exit(130)
    print("\n✓ Hotovo.")


if __name__ == "__main__":
    main()
