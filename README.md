# Jazyky – procvičování slovíček

Skripty pro procvičování slovíček (němčina, angličtina, italština a golfová terminologie ve všech třech jazycích). Slovíčka se zobrazují v plovoucím okně kitty, čtou se nahlas (TTS) a ke každému je vzorová věta s českým překladem.

Dva režimy:

- **pasivní poslech** (`jaz`) – slovíčka, překlady a fráze běží sama s pauzou, lze pozastavit a opakovat,
- **interaktivní procvičování** (`jazi`) – u každého slovíčka odpovíš „znám / neznám“, neznámá se ukládají a dají se procvičit zvlášť.

Oba režimy mají i **průhlednou variantu** (`jazt`, `jazit`, volba `--pruhledne`): místo okna kitty se slovíčko zobrazí jako poloprůhledná „poznámka“ ve stejném stylu jako `pozt` z `~/Projects/Pango-view` (viz [Průhledné okno](#průhledné-okno---pruhledne)).

## Rychlé použití

```sh
jaz                 # pasivní poslech, jazyk a pořadí se vyberou z nabídky
jaz de              # rovnou němčina
jaz en --swap       # angličtina, nejdříve česky
jazi it             # interaktivní procvičování italštiny
jazi it --neznama   # jen dříve neznámá slovíčka
jazt de             # pasivní poslech v průhledném okně
jazit en            # interaktivní procvičování v průhledném okně
```

Po výběru jazyka a pořadí se otevře plovoucí okno a vše běží v něm. Terminál se hned uvolní (okno je od něj odpojené).

### Ovládání v okně

| Klávesa | Pasivní (`jaz`) | Interaktivní (`jazi`) |
|---|---|---|
| `mezera` | pauza / pokračovat – zastaví i rozpracované čtení | – |
| `Enter` | – | znám |
| `n` | – | neznám (uloží se) |
| `z` | zopakovat slovíčko od začátku (kdykoli, i v pauze) | zopakovat slovíčko (pak odpověz) |
| `x` | označit chybnou frázi | označit chybnou frázi (pak odpověz) |
| `q` | konec | konec |
| zavření okna | konec | konec |

V interaktivním režimu se odpověď potvrzuje Enterem (`n⏎`, `z⏎`, `x⏎`), v pasivním stačí stisk klávesy. V průhledném okně stačí v obou režimech jen stisk klávesy (bez Enteru); `Esc` = `q`.

### Aliasy a rofi

Aliasy jsou v `~/dotfiles/zsh/.funkce/aliasy`:

```sh
alias jaz="~/Projects/Jazyky/slovicka-pasivni.sh --pauza 3"
alias jazi="~/Projects/Jazyky/slovicka-interaktivni.sh"
alias jazt="~/Projects/Jazyky/slovicka-pasivni.sh --pauza 3 --pruhledne"
alias jazit="~/Projects/Jazyky/slovicka-interaktivni.sh --pruhledne"
```

Skripty mají symlinky v `~/.local/bin` (je v `PATH`), takže jdou spustit i z rofi (`Ctrl+Space`, režim `run`): `slovicka-pasivni`, `slovicka-interaktivni`. Bez terminálu se nabídky zobrazí přes `rofi -dmenu`, chyby jako notifikace (`notify-send`). Esc v nabídce = zrušit.

```sh
ln -s ~/Projects/Jazyky/slovicka-interaktivni.sh ~/.local/bin/slovicka-interaktivni
ln -s ~/Projects/Jazyky/slovicka-pasivni.sh ~/.local/bin/slovicka-pasivni
```

## Volby

| Volba | Význam | Režim |
|---|---|---|
| `de`, `en`, `it`, `de_golf`, `en_golf`, `it_golf` | jazyk / slovník (bez zadání nabídka) | oba |
| `--swap`, `-s` | nejdříve česky, pak originál | oba |
| `--orig`, `-o` | nejdříve originál, pak česky | oba |
| `--neznama`, `-u` | jen uložená neznámá slovíčka | oba |
| `--bez-frazi` | nezobrazovat a nečíst vzorové fráze | oba |
| `--bez-sumu` | bez tichého šumu na pozadí (viz [Zvuk na pozadí](#zvuk-na-pozadí)) | oba |
| `--pruhledne`, `-t` | průhledné okno ve stylu poznámek místo kitty (totéž `SLOVICKA_PRUHLEDNE=1`) | oba |
| `--vsechna`, `-a` | projít celý slovník | pasivní |
| `--pocet N`, `-n N` | počet slovíček (výchozí 30) | pasivní |
| `--pauza N`, `-p N` | pauza mezi slovíčky v sekundách, i desetinná (výchozí 3) | pasivní |
| `-h`, `--help` | nápověda | oba |

Bez `--swap` / `--orig` se skript na pořadí zeptá (Enter = originál první). Interaktivní kolo má vždy 30 slovíček.

## Soubory

| Soubor | Popis |
|---|---|
| `slovicka-pasivni.sh` | pasivní poslech |
| `slovicka-interaktivni.sh` | interaktivní procvičování |
| `slovicka-view.py` | průhledné okno (GTK4 + Pango) pro volbu `--pruhledne` |
| `spolecne.sh` | sdílený kód (slovníky, TTS, fráze, okno, nabídky, neznámá slovíčka); načítá se přes `source`, nespouští se |
| `*_slova.txt`, `golf_*.txt` | slovníky |
| `fraze/<slovník>.tsv` | vzorové fráze |
| `fraze/chybne.tsv` | fráze označené klávesou `x` (vzniká sám) |
| `fraze/lokalni/` | záloha starých frází z lokálního modelu (nepoužívá se) |
| `neznama_<jazyk>.txt` | uložená neznámá slovíčka (vznikají samy) |
| `generuj-fraze-claude.py` | generátor frází přes Claude Batch API |
| `generuj-fraze.py` | generátor frází lokálním modelem (gpt-oss-20b) |
| `rozbor-skriptu.html` | studijní materiál – výklad skriptů pro učení bashe |

## Slovníky

Jeden řádek = `originál — překlad`, oddělovač je ` — ` (dlouhá pomlčka s mezerami). Více variant lze oddělit `/`, čtou se zvlášť:

```
il controllo / l'ispezione — inspekce / prohlídka
```

Prázdné řádky a řádky bez oddělovače se přeskakují.

## Vzorové fráze

Ke každému slovíčku je vzorová věta v cizím jazyce s českým překladem. V okně je pod slovíčkem (věta tyrkysově kurzívou, překlad šedě). Po slovíčku a překladu se přečte i cizojazyčná věta.

**Stav (21. 11. 2026):** frázi má všech 11 826 slovíček ze všech šesti slovníků. Vygeneroval je Claude přes Batch API – 240 Claude Opus 5.5 (zkouška), zbytek Claude Sonnet 5.5 – za celkem 4,91 USD.

Formát `fraze/<slovník>.tsv` (oddělovač tabulátor):

```
<řádek slovníku>	<fráze>	<český překlad>
la chiave — klíč	Non trovo più la chiave della macchina.	Nemůžu najít klíč od auta.
```

Fráze se přiřazují podle **celého řádku slovníku**. Když řádek ve slovníku změníš, jeho fráze se přestane zobrazovat; nová se vytvoří dalším spuštěním generátoru. Fráze lze opravovat ručně přímo v `.tsv`.

### Chybné fráze (`x`)

Klávesa `x` připíše frázi aktuálního slovíčka do `fraze/chybne.tsv` (bez duplicit) a v nápovědě se ukáže **✗ fráze označena**:

```
<soubor frází>	<řádek slovníku>	<fráze>	<překlad>
```

Opravu udělej ručně v `fraze/<soubor frází>`, nebo nech opravit Claude („oprav fráze z fraze/chybne.tsv“). Po opravě řádky z `chybne.tsv` smaž.

### Generování přes Claude (`generuj-fraze-claude.py`)

Používá Claude **Batch API** (zpracování na pozadí, obvykle do hodiny, sleva 50 %). Skutečná cena byla 0,40 USD za 1000 slovíček se Sonnetem 5.5 a 0,78 USD s Opusem 5.5.

Přihlášení – jedno z:

```sh
ant auth login                        # profil Console, uloží se do ~/.config/anthropic/ (výchozí)
read -rs "?Vlož API klíč: " k && printf '%s' "$k" > ~/.config/anthropic/api-key && unset k
```

API klíč nedávej do `.zshrc` – Claude Code by ho začal používat místo předplatného. Kredit se nabíjí v Console → Settings → Billing.

```sh
./generuj-fraze-claude.py --nanecisto                    # plán a odhad ceny, nic neodešle
./generuj-fraze-claude.py --model claude-sonnet-5-5      # doplní všechna slovíčka bez fráze
./generuj-fraze-claude.py --limit 40                     # zkouška: 40 slovíček z každého slovníku
./generuj-fraze-claude.py --stav                         # stav odeslané dávky
```

- Generuje jen slovíčka, která frázi ještě nemají – po přidání slov do slovníku stačí spustit znovu.
- Před odesláním ukáže počet slovíček a odhad ceny a zeptá se (`--ano` = neptat se). Po stažení vypíše skutečnou cenu podle spotřebovaných tokenů.
- Čeká na dokončení dávky a každou minutu hlásí stav. Ctrl+C dávku nezruší – dalším spuštěním se jen stáhnou výsledky (rozpracovaná dávka je v `fraze/.claude-batch.json`).
- Odpověď je vynucená jako JSON podle schématu; věty, které neprojdou kontrolou kvality, se odešlou při dalším spuštění.
- Volby: `--model claude-opus-5-5 | claude-sonnet-5-5 | claude-haiku-5-5` (výchozí Opus), `--effort low | medium | high` (výchozí `low`), `--davka 25`, názvy slovníků jako argumenty.
- Spouští se přes `uv run --script`; knihovnu `anthropic` si `uv` stáhne sám.

### Generování lokálním modelem (`generuj-fraze.py`)

Alternativa zdarma a offline přes llama.cpp server s gpt-oss-20b (`llama-gpt-oss.service`, OpenAI API na `http://127.0.0.1:8080`). **Kvalita je výrazně nižší** – české překlady mají zhruba ve třetině případů gramatické chyby. Celý slovník trvá asi 10 hodin.

```sh
systemctl --user start llama-gpt-oss.service
systemd-run --user --unit=slovicka-fraze ~/Projects/Jazyky/generuj-fraze.py --uvazovani low
journalctl --user -u slovicka-fraze -f        # průběh
systemctl --user stop slovicka-fraze          # zastavit (lze pokračovat)
```

Volby: `--limit N`, `--davka 20`, `--uvazovani low | medium | high` (výchozí `medium`), `--pruchody 2`. Oba generátory zapisují do stejných souborů – nespouštěj je současně.

## Neznámá slovíčka

Slovíčka označená v interaktivním režimu `n` se ukládají do `neznama_<jazyk>.txt` (stejný formát jako slovník, bez duplicit), i při ukončení klávesou `q`.

- Procvičíš je volbou `--neznama` nebo v nabídce jazyka položkou **Neznámá: … (počet)** – ta se ukáže jen u jazyků, které nějaká neznámá slovíčka mají.
- V režimu `--neznama` se slovíčko, které v **1. kole** označíš jako známé, ze souboru odebere (opakovací kola soubor nemění). Prázdný soubor se smaže.
- Pasivní režim umí `--neznama` také (jen poslech, soubor nemění).

## Průhledné okno (`--pruhledne`)

Slovíčko, překlad a fráze se vykreslí přes Pango do průhledného okna bez rámečku – stejně jako poznámky `pozt` (`~/Projects/Pango-view`). Okno má pevnou šířku, výška se přizpůsobí délce fráze. Bez grafické relace nebo bez `python-gobject`/GTK4 se použije běžné okno kitty.

| Proměnná | Význam | Výchozí |
|---|---|---|
| `SLOVICKA_STYL` | barvy a font podle stylů poznámek 0–9 (0 tmavě zelená, 2 vínová, 3 tmavě modrá, 4 Nord, 9 velké čitelné…) | `0` |
| `SLOVICKA_ALFA` | krytí pozadí, hex `00`–`ff` | `POZNAMKA_ALFA`, jinak `b3` (≈ 70 %) |
| `SLOVICKA_ZOOM` | zvětšení celého okna | `1` |
| `SLOVICKA_SIRKA` | šířka okna v px (před zoomem) | `760` |
| `SLOVICKA_PRUHLEDNE` | `1` = průhledné okno i bez volby (např. pro rofi) | `0` |

```sh
SLOVICKA_STYL=3 SLOVICKA_ZOOM=1.2 jazt it
```

Klávesy navíc: `=` / `-` / `0` zoom, tažení myší přesun okna. Zavření okna ukončí procvičování (jako zavření kitty – rozpracované kolo se neuloží, `q` ano). App-id pro pravidla niri je `cz.slovicka.view`.

**Jak to funguje:** spouštěč pustí odpojeně `slovicka-view.py --rezim znaky|radky -- <skript> …`. Prohlížeč spustí skript s `SLOVICKA_V_OKNE=2` ve vlastní skupině procesů. Skript mu posílá příkazy (`KARTA`, `NAPOVEDA`, `ZPRAVA`, pole oddělená tabulátorem) na deskriptor `$SLOVICKA_FD` funkcí `_view` ze `spolecne.sh`, a stisknuté klávesy dostává na stdin (pasivní jako znak pro `read -n1`, interaktivní jako řádek pro `read -r`). Terminálový výstup skriptu jde do `/dev/null`. Konec skriptu zavře okno, zavření okna pošle skupině `SIGTERM` (ukončí i `piper`/`mpv`).

## Zvuk na pozadí

Po celou dobu procvičování hraje velmi tichý bílý šum. Díky němu se Bluetooth reproduktor neuspí mezi slovíčky a neuřízne začátek krátkých slov. Hraje i během pauzy a skončí spolu se skriptem (konec, `q`, zavření okna). V mixéru (pavucontrol) je vidět jako `slovicka-pozadi`.

| Proměnná | Význam | Výchozí |
|---|---|---|
| `SLOVICKA_POZADI` | `sum` = šum, `ne` = vypnuto, nebo cesta ke zvukovému souboru (hraje ve smyčce) | `sum` |
| `SLOVICKA_SUM_BARVA` | barva šumu: `white`, `pink`, `brown` (hlubší, příjemnější) | `white` |
| `SLOVICKA_SUM_UROVEN` | amplituda šumu (0–1); `0.003` je skoro neslyšné | `0.003` |
| `SLOVICKA_POZADI_HLASITOST` | hlasitost souboru v `mpv` (0–100) | `25` |

```sh
SLOVICKA_SUM_BARVA=brown SLOVICKA_SUM_UROVEN=0.01 jazt de   # slyšitelný hnědý šum
SLOVICKA_POZADI=~/Music/dest.mp3 jazi it                     # vlastní zvuk podle nálady
jaz de --bez-sumu                                            # bez šumu
```

Trvalé nastavení dej do `~/.zshrc` (`export SLOVICKA_SUM_BARVA=pink`). Šum generuje `mpv` přes filtr `anoisesrc` z ffmpeg, žádný soubor není potřeba.

## Jak to funguje

- **Cesty:** `CESTA_SLOVNIKU` se odvozuje z umístění skriptu (`readlink -f`), takže fungují symlinky i přesun složky – stačí upravit aliasy.
- **Okno:** po výběru spustí skript sám sebe v kitty (s `--pruhledne` v `slovicka-view.py`, viz výše) s proměnnou `SLOVICKA_V_OKNE=1` přes `setsid` (odpojeně od terminálu). Bez `kitty` nebo grafické relace běží přímo v terminálu.
- **Rozměry okna** `OKNO_SIRKA=820`, `OKNO_VYSKA=380` (`spolecne.sh`) musí odpovídat pravidlu `kitty-float` v `~/dotfiles/niri/.config/niri/config.kdl`. Okno má jen 58 × 10 znaků. Kartu proto skládá `_vypis_kartu` podle skutečné velikosti terminálu: věty zalomí (`fold -s`), prázdné řádky vloží jen když je místo a v krajním případě zkrátí frázi (`…`). Titulek s vlajkami a pořadím tak nikdy neodroluje. Nápovědy kláves v terminálu jsou proto zkrácené (`[x] chyba`, `[⏎] znám`), aby se vešly na jeden řádek.
- **Pasivní ovládání:** čtení běží na pozadí a skript mezitím čte klávesy (`read -t`). Mezera pošle čtení `SIGSTOP` / `SIGCONT` (zastaví `piper`, `ffmpeg` i `mpv` uprostřed slova), `z` ho ukončí (`SIGTERM`) a slovíčko začne znovu. Čekání mezi slovíčky měří čas přes `$EPOCHREALTIME`.
- **TTS:** cizí jazyky Piper (`~/.local/share/piper`, vzorkovací frekvence se čte z `<model>.onnx.json`), čeština `edge-tts` (potřebuje internet), záložně `espeak-ng`. `mpv` běží s `--no-input-terminal`, aby nebral klávesy.
- **Úklid:** při ukončení (`q`, Ctrl+C, zavření okna, chyba) se zastaví čtení, zavře okno a smaže rozpracovaný mp3 v `/tmp`.

## Závislosti

- Průhledné okno: `python-gobject`, `gtk4`, `pango` a kompozitor s průhledností (niri).
- Skripty: `bash` 5+, `kitty`, `niri` (pozice okna; jinde se jen nevycentruje), `rofi`, `notify-send`, `setsid`, `mpv`, `ffmpeg`, `piper-tts` (`~/.local/share/uv/tools/piper-tts/bin/piper`), `edge-tts`, volitelně `espeak-ng`.
- Generování frází: `uv` a přístup ke Claude API, nebo `python3` a llama.cpp server s gpt-oss-20b.

## Studijní materiál

`rozbor-skriptu.html` – výklad skriptů pro učení bashe ve třech částech: původní verze s technikami a cvičeními, opravy slabých míst (kód před/po) a rozšíření o fráze, ovládání klávesami a generátory frází. Otevři `xdg-open rozbor-skriptu.html`, online verze: https://claude.ai/artifact/NrzGvG6r9z5a5sfphknAXR

## Git

Soukromý repozitář: https://github.com/navik61/jazyky (větev `master`). Uložení změn:

```sh
git add -A && git commit -m "popis změny" && git push
```

Aliasy a pravidlo okna niri jsou mimo projekt, v `~/dotfiles`.

## Řešení problémů

- **Fráze se nezobrazuje** – zkontroluj, že je slovíčko v `fraze/<slovník>.tsv` (`grep -F 'slovo — ' fraze/*.tsv`); po změně slovníku spusť generátor.
- **Klávesy nereagují** – okno musí mít fokus; klávesy se čtou jen v okně se slovíčky, ne v původním terminálu.
- **Fráze je zkrácená (`…`) nebo chybí titulek** – obsah se nevejde do okna; zvětši pravidlo `kitty-float` v niri a stejně i `OKNO_SIRKA` / `OKNO_VYSKA` v `spolecne.sh`.
- **Ticho místo hlasu** – chybí Piper model nebo `edge-tts` (čeština potřebuje internet); cesty jsou v `spolecne.sh`.
- **„Chybí …/spolecne.sh“** – `spolecne.sh` musí ležet vedle skriptů.
- **Generátor Claude: „Přihlášení neplatí nebo vypršelo“** – `ant auth login`, pak spusť znovu (dávka mezitím běží dál).
- **Generátor lokální: `Connection refused`** – neběží server: `systemctl --user start llama-gpt-oss.service`.
- **BT reproduktor pořád uřízne začátek slova** – zvyš `SLOVICKA_SUM_UROVEN` (např. `0.01`). Některé reproduktory se uspí, i když jim chodí jen velmi tichý signál.
- **Průhledné okno se neotevře** – spusť ručně `./slovicka-view.py --rezim znaky -- ./slovicka-pasivni.sh de --orig` a podívej se na chyby; chybí-li GTK4/`python-gobject`, skript tiše použije kitty.
- **`jaz` po změně aliasu nefunguje** – `source ~/.zshrc` nebo nový terminál.
