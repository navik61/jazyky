#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["anthropic"]
# ///
"""
generuj-claude.py — doplní slovník pojmů a vzorové věty přes Claude Batch API.

Kroky (spouštěj v tomto pořadí, každý doplňuje jen to, co chybí):
  ./generuj-claude.py slova    # chybějící slova v slovnik/<sada>.tsv (sloupce cs de en it fr es ru)
  ./generuj-claude.py vety     # věta ke každému pojmu v každém jazyce + překlady do ostatních 6

Volby:
  --sady obecne golf          které sady (výchozí obě)
  --jazyky de es …            jen tyto cílové jazyky (vety) / doplňované jazyky (slova)
  --limit N                   max. pojmů na sadu a jazyk (zkouška)
  --model, --effort, --davka  model (výchozí Sonnet), úroveň uvažování, položek v jednom dotazu
  --nanecisto                 jen plán a odhad ceny, nic neodešle
  --ano                       neptat se před odesláním
  --stav                      stav odeslané dávky

Dávka se zpracuje na pozadí (obvykle do hodiny). Ctrl+C dávku nezruší — dalším spuštěním
se jen stáhnou výsledky. Neplatné nebo chybějící výsledky odešle další spuštění.

Přihlášení: profil z `ant auth login` (výchozí), nebo API klíč v ANTHROPIC_API_KEY
či v souboru ~/.config/anthropic/api-key (chmod 600).
"""

import argparse
import json
import os
import random
import sys
import time
from pathlib import Path

import anthropic
from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
from anthropic.types.messages.batch_create_params import Request

ADRESAR = Path(__file__).resolve().parent
SLOVNIK = ADRESAR / "slovnik"
FRAZE = ADRESAR / "fraze"
STAV = FRAZE / ".claude-batch.json"
SOUBOR_KLICE = Path.home() / ".config" / "anthropic" / "api-key"

JAZYKY = ["cs", "de", "en", "it", "fr", "es", "ru"]
NAZEV = {"cs": "Czech", "de": "German", "en": "English", "it": "Italian",
         "fr": "French", "es": "Spanish", "ru": "Russian"}
SADY = ["obecne", "golf"]

# Ceny Batch API v USD za milion tokenů (vstup, výstup)
CENY_BATCH = {
    "claude-opus-5-5": (2.0, 10.0),
    "claude-sonnet-5-5": (1.0, 5.0),
    "claude-haiku-5-5": (0.05, 0.25),
}


# ── Tabulky ──────────────────────────────────────────────────────
def nacti(cesta: Path) -> list[dict]:
    if not cesta.exists():
        return []
    radky = cesta.read_text(encoding="utf-8").splitlines()
    hlavicka = radky[0].split("\t")
    vysledek = []
    for r in radky[1:]:
        pole = r.split("\t")
        pole += [""] * (len(hlavicka) - len(pole))
        vysledek.append(dict(zip(hlavicka, pole)))
    return vysledek


def uloz(cesta: Path, zaznamy: list[dict]) -> None:
    docasny = cesta.with_suffix(".tmp")
    with docasny.open("w", encoding="utf-8") as f:
        f.write("\t".join(["id"] + JAZYKY) + "\n")
        for z in sorted(zaznamy, key=lambda z: z["id"]):
            f.write("\t".join(cisty(z.get(k, "")) for k in ["id"] + JAZYKY) + "\n")
    docasny.replace(cesta)


def cisty(text) -> str:
    return " ".join(str(text or "").replace("\t", " ").split()).strip().strip('"„“')


def soubor_vet(sada: str, cil: str) -> Path:
    return FRAZE / f"{sada}-{cil}.tsv"


# ── Zadání pro model ─────────────────────────────────────────────
SCHEMA_SLOVA = {
    "type": "object",
    "properties": {"items": {"type": "array", "items": {
        "type": "object",
        "properties": {"i": {"type": "integer"}, **{j: {"type": "string"} for j in JAZYKY[1:]}},
        "required": ["i"] + JAZYKY[1:], "additionalProperties": False}}},
    "required": ["items"], "additionalProperties": False,
}
SCHEMA_VETY = {
    "type": "object",
    "properties": {"items": {"type": "array", "items": {
        "type": "object",
        "properties": {"i": {"type": "integer"}, **{j: {"type": "string"} for j in JAZYKY}},
        "required": ["i"] + JAZYKY, "additionalProperties": False}}},
    "required": ["items"], "additionalProperties": False,
}

GOLF = (" All entries are golf terminology: use the term a golfer would use on the course, "
        "in a lesson or at a tournament.")
GOLF_VETY = (" The vocabulary is golf terminology, so set every sentence in a realistic golf situation "
             "(on the course, in a lesson, at the clubhouse, in a tournament).")


def ukazky_stylu(pojmy: list[dict], jazyk: str, pocet: int = 8) -> str:
    """Pár existujících hesel jako vzor zápisu (členy, tvar sloves, poznámky)."""
    s_jazykem = [p for p in pojmy if p.get(jazyk)]
    nahodne = random.Random(jazyk).sample(s_jazykem, min(pocet, len(s_jazykem)))
    return "; ".join(f"{p['cs']} → {p[jazyk]}" for p in nahodne)


def zadani_slova(sada: str, pojmy_vse: list[dict], polozky: list[dict]) -> str:
    styl = "\n".join(f"- {NAZEV[j]}: {ukazky_stylu(pojmy_vse, j)}" for j in JAZYKY[1:])
    radky = []
    for i, p in enumerate(polozky, 1):
        znama = "; ".join(f"{j}: {p[j]}" for j in JAZYKY[1:] if p.get(j))
        chybi = ", ".join(j for j in JAZYKY[1:] if not p.get(j))
        radky.append(f"{i}. Czech: {p['cs']}" + (f" | known: {znama}" if znama else "") + f" | NEED: {chybi}")
    return (
        "You are a lexicographer building a multilingual vocabulary list for language learners."
        + (GOLF if sada == "golf" else "") + "\n\n"
        "Each numbered entry is one concept given by its Czech meaning (alternatives and notes in "
        "parentheses clarify the sense), sometimes with known translations. For every language code "
        "listed after NEED, give the standard dictionary form of the word or phrase in that language "
        "with exactly the same meaning. Return an empty string for every language NOT listed after NEED.\n\n"
        "Follow the conventions of the existing list exactly (articles with nouns, infinitives for verbs, "
        "same kind of phrase). Examples of existing entries (Czech → translation):\n" + styl + "\n\n"
        "Rules:\n"
        "- if the Czech meaning lists several senses separated by '/', you may give up to two words "
        "separated by ' / ' (e.g. 'llamar / nombrar'); otherwise give one\n"
        "- no explanations, no '—', at most 6 words\n"
        "- keep grammatical gender notes such as (m.) / (f.) only if the Czech meaning has them\n\n"
        'Return JSON {"items": [{"i": <number>, "de": "...", "en": "...", "it": "...", "fr": "...", '
        '"es": "...", "ru": "..."}, ...]} with exactly one item per entry, same numbering.\n\nEntries:\n'
        + "\n".join(radky)
    )


def zadani_vety(sada: str, cil: str, polozky: list[dict]) -> str:
    jazyk = NAZEV[cil]
    radky = []
    for i, p in enumerate(polozky, 1):
        if p["veta"]:
            radky.append(f"{i}. word: {p['slovo']} (meaning: {p['cs']}) | SENTENCE GIVEN: {p['veta']} "
                         f"| TRANSLATE INTO: {', '.join(p['chybi'])}")
        else:
            radky.append(f"{i}. word: {p['slovo']} (meaning: {p['cs']}) | WRITE NEW SENTENCE "
                         f"| TRANSLATE INTO: {', '.join(p['chybi'])}")
    return (
        f"You are an experienced {jazyk} teacher writing flashcards for adult learners of {jazyk}."
        + (GOLF_VETY if sada == "golf" else "") + "\n\n"
        f"Each numbered entry is a {jazyk} word with its Czech meaning.\n\n"
        f"If the entry says WRITE NEW SENTENCE, write one example sentence in {jazyk}:\n"
        f"- a complete sentence of 6 to 14 words, natural everyday {jazyk}, level A2–B1\n"
        f"- it must contain the {jazyk} word (any inflected form) in the meaning given\n"
        f"- a typical, useful context (who, where, why), not a trivial definition\n"
        f"- if the word lists alternatives separated by '/', use the first one; ignore notes in parentheses\n"
        f"- do not copy the entry itself\n"
        f"If the entry says SENTENCE GIVEN, return that sentence unchanged.\n"
        f"Put the {jazyk} sentence into the field \"{cil}\".\n\n"
        "Then translate the sentence into every language listed after TRANSLATE INTO, as a native "
        "speaker would naturally say it (idiomatic, correct spelling and diacritics, verbs agreeing in "
        "person, number and gender; in Czech, Italian, Spanish and Russian omit unstressed subject "
        "pronouns). Return an empty string for every other field.\n\n"
        'Return JSON {"items": [{"i": <number>, "cs": "...", "de": "...", "en": "...", "it": "...", '
        '"fr": "...", "es": "...", "ru": "..."}, ...]} with exactly one item per entry, same numbering.'
        "\n\nEntries:\n" + "\n".join(radky)
    )


def platne_slovo(text: str) -> bool:
    return bool(text) and "—" not in text and len(text) <= 80 and len(text.split()) <= 8


def platna_veta(text: str, heslo: str) -> bool:
    slov = len(text.split())
    return 3 <= slov <= 30 and heslo not in text and "\t" not in text


# ── Plán práce ───────────────────────────────────────────────────
def prace_slova(args) -> list[dict]:
    """Položky: {sada, id, cs, …, chybi}"""
    vysledek = []
    for sada in args.sady:
        pojmy = nacti(SLOVNIK / f"{sada}.tsv")
        jazyky = [j for j in (args.jazyky or JAZYKY[1:]) if j != "cs"]
        zbyva = [p for p in pojmy if any(not p[j] for j in jazyky)]
        if args.limit:
            zbyva = zbyva[:args.limit]
        for p in zbyva:
            # chybějící mimo vybrané jazyky se nedoplní — zadání je dostane jako „známé prázdné“
            vysledek.append({"sada": sada, **{k: p[k] for k in ["id"] + JAZYKY},
                             "_jazyky": [j for j in jazyky if not p[j]]})
    return vysledek


def prace_vety(args) -> dict[tuple[str, str], list[dict]]:
    vysledek = {}
    for sada in args.sady:
        pojmy = nacti(SLOVNIK / f"{sada}.tsv")
        for cil in args.jazyky or JAZYKY:
            vety = {z["id"]: z for z in nacti(soubor_vet(sada, cil))}
            polozky = []
            for p in pojmy:
                if not p[cil]:
                    continue                       # slovo v cílovém jazyce chybí → nejdřív `slova`
                z = vety.get(p["id"], {})
                veta = z.get(cil, "")
                chybi = [j for j in JAZYKY if j != cil and not z.get(j)]
                if veta and not chybi:
                    continue
                polozky.append({"id": p["id"], "slovo": p[cil], "cs": p["cs"], "veta": veta,
                                "chybi": chybi, "heslo": f"{p[cil]} — {p['cs']}"})
            if args.limit:
                polozky = polozky[:args.limit]
            if polozky:
                vysledek[(sada, cil)] = polozky
    return vysledek


def odhad(druh: str, polozky: int, vet_novych: int, prekladu: int, dotazu: int, model: str) -> float:
    vstup, vystup = CENY_BATCH[model]
    if druh == "slova":
        tok_in, tok_out = polozky * 45 + dotazu * 900, polozky * 30
    else:
        tok_in, tok_out = polozky * 55 + dotazu * 700, vet_novych * 30 + prekladu * 32 + polozky * 20
    return (tok_in * vstup + tok_out * vystup) / 1e6


# ── Odeslání ─────────────────────────────────────────────────────
def pozadavek(cid: str, text: str, schema: dict, args) -> Request:
    return Request(custom_id=cid, params=MessageCreateParamsNonStreaming(
        model=args.model, max_tokens=16000,
        output_config={"effort": args.effort, "format": {"type": "json_schema", "schema": schema}},
        messages=[{"role": "user", "content": text}],
    ))


def odesli(c, args) -> None:
    pozadavky, mapa = [], {}
    if args.krok == "slova":
        prace = prace_slova(args)
        if not prace:
            print("✓ Všechny pojmy mají slova ve všech jazycích.")
            return
        pojmy_sad = {s: nacti(SLOVNIK / f"{s}.tsv") for s in args.sady}
        for sada in args.sady:
            polozky = [p for p in prace if p["sada"] == sada]
            for od in range(0, len(polozky), args.davka):
                davka = polozky[od:od + args.davka]
                cid = f"{sada}-{od:05d}"
                mapa[cid] = davka
                pozadavky.append(pozadavek(cid, zadani_slova(sada, pojmy_sad[sada], davka), SCHEMA_SLOVA, args))
        cena = odhad("slova", len(prace), 0, 0, len(pozadavky), args.model)
        print(f"\nDoplnit slova: {len(prace)} pojmů, {sum(len(p['_jazyky']) for p in prace)} slov, "
              f"{len(pozadavky)} dotazů, model {args.model}")
        for sada in args.sady:
            n = [p for p in prace if p["sada"] == sada]
            if n:
                print(f"  {sada}: {len(n)} pojmů")
    else:
        prace = prace_vety(args)
        if not prace:
            print("✓ Všechny pojmy mají věty i překlady.")
            return
        nove = preklady = polozek = 0
        print(f"\nVěty a překlady, model {args.model}:")
        for (sada, cil), polozky in prace.items():
            n_nove = sum(1 for p in polozky if not p["veta"])
            n_prekl = sum(len(p["chybi"]) for p in polozky)
            nove, preklady, polozek = nove + n_nove, preklady + n_prekl, polozek + len(polozky)
            print(f"  {sada}-{cil}: {len(polozky)} pojmů ({n_nove} nových vět, {n_prekl} překladů)")
            for od in range(0, len(polozky), args.davka):
                davka = polozky[od:od + args.davka]
                cid = f"{sada}-{cil}-{od:05d}"
                mapa[cid] = {"sada": sada, "cil": cil, "polozky": davka}
                pozadavky.append(pozadavek(cid, zadani_vety(sada, cil, davka), SCHEMA_VETY, args))
        cena = odhad("vety", polozek, nove, preklady, len(pozadavky), args.model)
        print(f"Celkem {polozek} pojmů: {nove} nových vět, {preklady} překladů, {len(pozadavky)} dotazů")

    print(f"Odhad ceny (Batch API, effort {args.effort}): ~{cena:.2f} USD — uvažování modelu cenu zvýší")
    if args.nanecisto:
        print("Nanečisto — nic se neodeslalo.")
        return
    if len(pozadavky) > 100_000:
        sys.exit("Víc než 100 000 dotazů v jedné dávce — použij --sady / --jazyky / --limit.")
    if not args.ano and input("Odeslat? [a/N] ").strip().lower() not in ("a", "ano", "y", "yes"):
        print("Neodesláno.")
        return
    davka = c.messages.batches.create(requests=pozadavky)
    STAV.write_text(json.dumps({"batch_id": davka.id, "krok": args.krok, "model": args.model, "mapa": mapa},
                               ensure_ascii=False))
    print(f"Odesláno: {davka.id}")
    cekej_a_stahni(c)


def cekej_a_stahni(c) -> None:
    stav = json.loads(STAV.read_text())
    while True:
        b = c.messages.batches.retrieve(stav["batch_id"])
        n = b.request_counts
        print(f"  {time.strftime('%H:%M:%S')}  {b.processing_status}: hotovo "
              f"{n.succeeded + n.errored + n.expired + n.canceled}, zpracovává se {n.processing}", flush=True)
        if b.processing_status == "ended":
            break
        time.sleep(60)
    stahni(c, stav)


def vysledky(c, stav):
    """Generátor (custom_id, položky z JSON) + sčítání tokenů a chyb."""
    pocty = {"in": 0, "out": 0, "chyby": 0}
    for v in c.messages.batches.results(stav["batch_id"]):
        if v.result.type != "succeeded":
            pocty["chyby"] += 1
            continue
        zprava = v.result.message
        pocty["in"] += zprava.usage.input_tokens
        pocty["out"] += zprava.usage.output_tokens
        text = next((b.text for b in zprava.content if b.type == "text"), "")
        try:
            polozky = json.loads(text)["items"]
        except (json.JSONDecodeError, KeyError):
            pocty["chyby"] += 1
            continue
        yield v.custom_id, {p.get("i"): p for p in polozky if isinstance(p, dict)}, pocty
    yield None, None, pocty


def stahni(c, stav: dict) -> None:
    ulozeno = odmitnuto = 0
    pocty = {"in": 0, "out": 0, "chyby": 0}
    if stav["krok"] == "slova":
        tabulky = {}
        for cid, podle_cisla, pocty in vysledky(c, stav):
            if cid is None:
                break
            for i, p in enumerate(stav["mapa"][cid], 1):
                odpoved = podle_cisla.get(i, {})
                sada = p["sada"]
                if sada not in tabulky:
                    tabulky[sada] = {z["id"]: z for z in nacti(SLOVNIK / f"{sada}.tsv")}
                zaznam = tabulky[sada].get(p["id"])
                for j in p["_jazyky"]:
                    slovo = cisty(odpoved.get(j, ""))
                    if zaznam is not None and not zaznam[j] and platne_slovo(slovo):
                        zaznam[j] = slovo
                        ulozeno += 1
                    else:
                        odmitnuto += 1
        for sada, zaznamy in tabulky.items():
            uloz(SLOVNIK / f"{sada}.tsv", list(zaznamy.values()))
        jednotka = "slov"
    else:
        soubory = {}
        for cid, podle_cisla, pocty in vysledky(c, stav):
            if cid is None:
                break
            info = stav["mapa"][cid]
            klic = (info["sada"], info["cil"])
            if klic not in soubory:
                soubory[klic] = {z["id"]: z for z in nacti(soubor_vet(*klic))}
            vety = soubory[klic]
            cil = info["cil"]
            for i, p in enumerate(info["polozky"], 1):
                odpoved = podle_cisla.get(i, {})
                zaznam = vety.setdefault(p["id"], {"id": p["id"]})
                veta = p["veta"] or cisty(odpoved.get(cil, ""))
                if not platna_veta(veta, p["heslo"]):
                    odmitnuto += 1
                    if len(zaznam) == 1:          # nová věta neprošla a nic jiného v řádku není
                        del vety[p["id"]]
                    continue
                zaznam[cil] = veta
                for j in p["chybi"]:
                    preklad = cisty(odpoved.get(j, ""))
                    if preklad and platna_veta(preklad, p["heslo"]):
                        zaznam[j] = preklad
                        ulozeno += 1
                    else:
                        odmitnuto += 1
        for (sada, cil), vety in soubory.items():
            uloz(soubor_vet(sada, cil), list(vety.values()))
        jednotka = "překladů"
    STAV.unlink()

    vstup, vystup = CENY_BATCH.get(stav["model"], (0, 0))
    cena = (pocty["in"] * vstup + pocty["out"] * vystup) / 1e6
    print(f"\n✓ Uloženo {ulozeno} {jednotka}, odmítnuto {odmitnuto}, chybných dotazů {pocty['chyby']}")
    print(f"  Tokeny: vstup {pocty['in']:,}, výstup {pocty['out']:,} (včetně uvažování)")
    print(f"  Skutečná cena: {cena:.2f} USD")
    if odmitnuto or pocty["chyby"]:
        print("  Chybějící položky odešle další spuštění.")


def klient() -> anthropic.Anthropic:
    klic = os.environ.get("ANTHROPIC_API_KEY")
    if not klic and SOUBOR_KLICE.exists():
        klic = SOUBOR_KLICE.read_text().strip()
    if klic:
        return anthropic.Anthropic(api_key=klic)
    try:
        return anthropic.Anthropic()
    except anthropic.AnthropicError:
        sys.exit("Chybí přihlášení: spusť `ant auth login`, nebo ulož API klíč do "
                 f"{SOUBOR_KLICE} (chmod 600).")


def main() -> None:
    p = argparse.ArgumentParser(description="Slovník pojmů a vzorové věty přes Claude Batch API")
    p.add_argument("krok", nargs="?", choices=["slova", "vety"], help="co doplnit")
    p.add_argument("--sady", nargs="+", default=SADY, choices=SADY)
    p.add_argument("--jazyky", nargs="+", choices=JAZYKY)
    p.add_argument("--limit", type=int, default=0, help="max. pojmů na sadu (a jazyk)")
    p.add_argument("--davka", type=int, default=0, help="položek v jednom dotazu (výchozí 40 slova / 15 vety)")
    p.add_argument("--model", default="claude-sonnet-5-5", choices=list(CENY_BATCH))
    p.add_argument("--effort", default="low", choices=["low", "medium", "high"])
    p.add_argument("--ano", action="store_true", help="neptat se před odesláním")
    p.add_argument("--stav", action="store_true", help="jen ukázat stav odeslané dávky")
    p.add_argument("--nanecisto", action="store_true", help="jen plán a odhad ceny")
    args = p.parse_args()
    args.davka = args.davka or (40 if args.krok == "slova" else 15)

    if STAV.exists() and not args.nanecisto:
        c = klient()
        if args.stav:
            b = c.messages.batches.retrieve(json.loads(STAV.read_text())["batch_id"])
            print(b.processing_status, b.request_counts)
            return
        print("Navazuji na odeslanou dávku…")
        try:
            cekej_a_stahni(c)
        except KeyboardInterrupt:
            print("\nPřerušeno — dávka běží dál, výsledky stáhne další spuštění.")
        return
    if args.stav:
        print("Žádná dávka neběží.")
        return
    if not args.krok:
        p.error("zadej krok: slova nebo vety")
    try:
        odesli(None if args.nanecisto else klient(), args)
    except KeyboardInterrupt:
        print("\nPřerušeno — dávka běží dál, výsledky stáhne další spuštění.")
    except anthropic.AuthenticationError:
        sys.exit("Přihlášení neplatí nebo vypršelo: spusť `ant auth login`.")
    except anthropic.APIConnectionError:
        sys.exit("Nelze se připojit k API. Dávka (pokud byla odeslána) běží dál.")
    except anthropic.BadRequestError as e:
        zprava = getattr(e, "message", str(e))
        if "credit balance" in zprava:
            sys.exit("Došel kredit na účtu API (Console → Settings → Billing). Nic se neodeslalo; "
                     "po dobití spusť znovu — doplní se jen to, co chybí.")
        sys.exit(f"API odmítlo požadavek: {zprava}")


if __name__ == "__main__":
    main()
