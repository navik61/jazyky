#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["anthropic"]
# ///
"""
generuj-fraze-claude.py — vzorové fráze ke slovíčkům přes Claude Batch API (Opus 5.5).

Výstup: fraze/<slovnik>.tsv (stejný formát jako generuj-fraze.py).
Při prvním spuštění se dosavadní fráze z lokálního modelu přesunou do fraze/lokalni/.

Postup:
  ./generuj-fraze-claude.py --limit 40      # zkouška: 40 slovíček, ukáže skutečnou cenu
  ./generuj-fraze-claude.py                 # všechno, co ještě nemá frázi od Claude
  ./generuj-fraze-claude.py --stav          # stav odeslané dávky

Dávka se zpracuje na pozadí (obvykle do hodiny, max. 24 h). Skript čeká a průběžně
hlásí stav. Když ho přerušíš (Ctrl+C), dávka běží dál a dalším spuštěním se jen
stáhnou výsledky. Neúspěšná nebo odmítnutá slovíčka se odešlou při dalším spuštění.

Přihlášení: profil z `ant auth login` (výchozí), nebo API klíč v ANTHROPIC_API_KEY
 či v souboru ~/.config/anthropic/api-key (chmod 600).
"""

import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import anthropic
from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
from anthropic.types.messages.batch_create_params import Request

ADRESAR = Path(__file__).resolve().parent
ADRESAR_FRAZI = ADRESAR / "fraze"
ZALOHA_LOKALNICH = ADRESAR_FRAZI / "lokalni"
STAV = ADRESAR_FRAZI / ".claude-batch.json"
SOUBOR_KLICE = Path.home() / ".config" / "anthropic" / "api-key"

# Ceny Batch API v USD za milion tokenů (docs: about-claude/pricing, 2026-11)
CENY_BATCH = {
    "claude-opus-5-5": (2.0, 10.0),
    "claude-sonnet-5-5": (1.0, 5.0),
    "claude-haiku-5-5": (0.05, 0.25),
}

# Zadání, slovníky a kontrola kvality jsou společné s lokálním generátorem
_spec = importlib.util.spec_from_file_location("generuj_fraze", ADRESAR / "generuj-fraze.py")
assert _spec is not None and _spec.loader is not None, "chybí generuj-fraze.py"
gf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gf)

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
                "additionalProperties": False,
            },
        }
    },
    "required": ["items"],
    "additionalProperties": False,
}


def klient() -> anthropic.Anthropic:
    """Klíč z ANTHROPIC_API_KEY nebo ~/.config/anthropic/api-key; jinak profil z `ant auth login`."""
    klic = os.environ.get("ANTHROPIC_API_KEY")
    if not klic and SOUBOR_KLICE.exists():
        klic = SOUBOR_KLICE.read_text().strip()
    if klic:
        return anthropic.Anthropic(api_key=klic)
    try:
        return anthropic.Anthropic()        # přihlašovací profil `ant` (~/.config/anthropic/)
    except anthropic.AnthropicError:
        sys.exit("Chybí přihlášení: spusť `ant auth login`, nebo ulož API klíč do "
                 f"{SOUBOR_KLICE} (chmod 600).")


def lokalni_generovani_bezi() -> bool:
    r = subprocess.run(["systemctl", "--user", "is-active", "slovicka-fraze"],
                       capture_output=True, text=True)
    return r.stdout.strip() == "active"


def zalohuj_lokalni() -> None:
    """Fráze z lokálního modelu přesune do fraze/lokalni/ (Claude je nahradí).
    Jen při úplně prvním spuštění — značka .hotovo zabrání přesunu frází od Claude."""
    znacka = ZALOHA_LOKALNICH / ".hotovo"
    if znacka.exists():
        return
    ZALOHA_LOKALNICH.mkdir(parents=True, exist_ok=True)
    for nazev in gf.SLOVNIKY:
        tsv = ADRESAR_FRAZI / nazev.replace(".txt", ".tsv")
        zaloha = ZALOHA_LOKALNICH / tsv.name
        if tsv.exists() and not zaloha.exists():
            shutil.move(tsv, zaloha)
            print(f"  lokální fráze zálohovány: {zaloha.relative_to(ADRESAR)}")
    znacka.touch()


def chybejici(nazvy: list[str], limit: int, nanecisto: bool = False) -> dict[str, list[str]]:
    vysledek = {}
    for nazev in nazvy:
        radky = list(dict.fromkeys(
            r.strip() for r in (ADRESAR / nazev).read_text(encoding="utf-8").splitlines()
            if gf.ODDELOVAC in r
        ))
        tsv = ADRESAR_FRAZI / nazev.replace(".txt", ".tsv")
        # Nanečisto před prvním během: v tsv jsou ještě lokální fráze, ty se nepočítají
        if nanecisto and not (ZALOHA_LOKALNICH / tsv.name).exists():
            hotove = set()
        else:
            hotove = gf.nacti_hotove(tsv)
        zbyva = [r for r in radky if r not in hotove]
        if limit:
            zbyva = zbyva[:limit]
        if zbyva:
            vysledek[nazev] = zbyva
    return vysledek


def odesli(c, args) -> None:
    if args.nanecisto:
        prace = chybejici(args.slovniky or list(gf.SLOVNIKY), args.limit, nanecisto=True)
        vypis_plan(prace, args)
        print("Nanečisto — nic se neodeslalo.")
        return
    if lokalni_generovani_bezi():
        sys.exit("Běží lokální generování (slovicka-fraze), zapisuje do stejných souborů.\n"
                 "Nejdřív ho zastav:  systemctl --user stop slovicka-fraze")
    ADRESAR_FRAZI.mkdir(exist_ok=True)
    zalohuj_lokalni()

    nazvy = args.slovniky or list(gf.SLOVNIKY)
    prace = chybejici(nazvy, args.limit)
    if not prace:
        print("✓ Všechna slovíčka už mají frázi od Claude.")
        return

    pozadavky, mapa = [], {}
    for si, (nazev, radky) in enumerate(prace.items()):
        jazyk, golf = gf.SLOVNIKY[nazev]
        for od in range(0, len(radky), args.davka):
            davka = radky[od: od + args.davka]
            cid = f"s{si}-{od:05d}"
            mapa[cid] = [nazev, davka]
            pozadavky.append(Request(
                custom_id=cid,
                params=MessageCreateParamsNonStreaming(
                    model=args.model,
                    max_tokens=16000,
                    output_config={
                        "effort": args.effort,
                        "format": {"type": "json_schema", "schema": SCHEMA},
                    },
                    messages=[{"role": "user", "content": gf.prompt(jazyk, golf, davka)}],
                ),
            ))

    vypis_plan(prace, args)
    if not args.ano and input("Odeslat? [a/N] ").strip().lower() not in ("a", "ano", "y"):
        print("Neodesláno.")
        return

    davka = c.messages.batches.create(requests=pozadavky)
    STAV.write_text(json.dumps({"batch_id": davka.id, "model": args.model, "mapa": mapa}, ensure_ascii=False))
    print(f"Odesláno: {davka.id}")
    cekej_a_stahni(c)


def vypis_plan(prace: dict[str, list[str]], args) -> None:
    pocet = sum(len(v) for v in prace.values())
    dotazu = sum(-(-len(v) // args.davka) for v in prace.values())
    vstup, vystup = CENY_BATCH.get(args.model, (0, 0))
    odhad = pocet * (9 * vstup + 45 * vystup) / 1e6 + dotazu * 560 * vstup / 1e6
    print(f"\n{pocet} slovíček v {dotazu} dotazech, model {args.model}, effort {args.effort}")
    for nazev, radky in prace.items():
        print(f"  {nazev}: {len(radky)}")
    print(f"Odhad ceny (Batch API, bez uvažování): ~{odhad:.2f} USD — uvažování modelu cenu zvýší")


def cekej_a_stahni(c: anthropic.Anthropic) -> None:
    stav = json.loads(STAV.read_text())
    bid = stav["batch_id"]
    while True:
        b = c.messages.batches.retrieve(bid)
        n = b.request_counts
        print(f"  {time.strftime('%H:%M:%S')}  {b.processing_status}: hotovo {n.succeeded + n.errored + n.expired + n.canceled}"
              f", zpracovává se {n.processing}", flush=True)
        if b.processing_status == "ended":
            break
        time.sleep(60)
    stahni(c, stav)


def stahni(c: anthropic.Anthropic, stav: dict) -> None:
    mapa = stav["mapa"]
    vstup_cena, vystup_cena = CENY_BATCH.get(stav["model"], (0, 0))
    tokeny_in = tokeny_out = ulozeno = odmitnuto = chyby = 0
    vystupy: dict[str, list[str]] = {}

    for vysledek in c.messages.batches.results(stav["batch_id"]):
        nazev, davka = mapa[vysledek.custom_id]
        if vysledek.result.type != "succeeded":
            chyby += 1
            continue
        zprava = vysledek.result.message
        tokeny_in += zprava.usage.input_tokens
        tokeny_out += zprava.usage.output_tokens
        if zprava.stop_reason != "end_turn":
            chyby += 1
            continue
        text = next((b.text for b in zprava.content if b.type == "text"), "")
        try:
            polozky = json.loads(text)["items"]
        except (json.JSONDecodeError, KeyError):
            chyby += 1
            continue
        podle_cisla = {p.get("i"): p for p in polozky if isinstance(p, dict)}
        for i, radek in enumerate(davka, 1):
            p = podle_cisla.get(i)
            if not p:
                odmitnuto += 1
                continue
            fraze, cs = gf.cisty(p.get("phrase", "")), gf.cisty(p.get("cs", ""))
            if not gf.platna(radek, fraze, cs):
                odmitnuto += 1
                continue
            vystupy.setdefault(nazev, []).append(f"{radek}\t{fraze}\t{cs}\n")
            ulozeno += 1

    for nazev, radky in vystupy.items():
        with (ADRESAR_FRAZI / nazev.replace(".txt", ".tsv")).open("a", encoding="utf-8") as f:
            f.writelines(radky)
    STAV.unlink()

    cena = tokeny_in * vstup_cena / 1e6 + tokeny_out * vystup_cena / 1e6
    print(f"\n✓ Uloženo {ulozeno} frází, odmítnuto {odmitnuto}, chybných dotazů {chyby}")
    print(f"  Tokeny: vstup {tokeny_in:,}, výstup {tokeny_out:,} (včetně uvažování)")
    print(f"  Skutečná cena této dávky: {cena:.2f} USD")
    if ulozeno:
        print(f"  Na jedno slovíčko: {cena / ulozeno * 1000:.2f} USD za 1000 slovíček")
    if odmitnuto or chyby:
        print("  Chybějící slovíčka odešle další spuštění.")


def main() -> None:
    p = argparse.ArgumentParser(description="Vzorové fráze přes Claude Batch API")
    p.add_argument("slovniky", nargs="*", help="názvy slovníků (výchozí: všechny)")
    p.add_argument("--limit", type=int, default=0, help="max. slovíček na slovník (zkouška)")
    p.add_argument("--davka", type=int, default=25, help="slovíček v jednom dotazu (výchozí 25)")
    p.add_argument("--model", default="claude-opus-5-5", choices=list(CENY_BATCH))
    p.add_argument("--effort", default="low", choices=["low", "medium", "high"],
                   help="úroveň uvažování (výchozí low = nejlevnější)")
    p.add_argument("--ano", action="store_true", help="neptat se před odesláním")
    p.add_argument("--stav", action="store_true", help="jen ukázat stav odeslané dávky")
    p.add_argument("--nanecisto", action="store_true", help="jen ukázat plán a odhad ceny, nic neodeslat")
    args = p.parse_args()

    for n in args.slovniky:
        if n not in gf.SLOVNIKY:
            sys.exit(f"Neznámý slovník: {n} (možnosti: {', '.join(gf.SLOVNIKY)})")

    if args.nanecisto:
        odesli(None, args)
        return
    c = klient()
    try:
        if STAV.exists():
            if args.stav:
                b = c.messages.batches.retrieve(json.loads(STAV.read_text())["batch_id"])
                print(b.processing_status, b.request_counts)
                return
            print("Navazuji na odeslanou dávku…")
            cekej_a_stahni(c)
        elif args.stav:
            print("Žádná dávka neběží.")
        else:
            odesli(c, args)
    except KeyboardInterrupt:
        print("\nPřerušeno — dávka běží dál, výsledky stáhne další spuštění.")
    except anthropic.AuthenticationError:
        sys.exit("Přihlášení neplatí nebo vypršelo: spusť `ant auth login` (nebo zkontroluj API klíč).")
    except anthropic.PermissionDeniedError:
        sys.exit("Klíč nemá oprávnění (zkontroluj kredit v Console).")
    except anthropic.APIConnectionError:
        sys.exit("Nelze se připojit k API. Zkontroluj internet. Dávka (pokud byla odeslána) běží dál.")


if __name__ == "__main__":
    main()
