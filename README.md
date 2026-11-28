# Jazyky – procvičování slovíček

**Česky** · [English](README.en.md)

Procvičování slovíček **mezi libovolnými dvěma ze sedmi jazyků**: čeština, němčina, angličtina, italština, francouzština, španělština a ruština, plus golfová terminologie. Zvolíš si svůj (mateřský) jazyk a jazyk, který se učíš – Čech se učí španělsky, Němec česky, Rus anglicky… Rozhraní je ve všech sedmi jazycích. Slovíčka se zobrazují v průhledném okně ve stylu poznámek, čtou se nahlas (TTS) a ke každému je vzorová věta s překladem do tvého jazyka.

Dva režimy:

- **interaktivní procvičování** (`jaz` – výchozí) – u každého slovíčka odpovíš „znám / neznám“, neznámá se ukládají a dají se procvičit zvlášť,
- **pasivní poslech** (`jaz --pasivni`) – slovíčka, překlady a věty běží sama s pauzou, lze pozastavit a opakovat.

Slovíčko se v obou režimech zobrazí jako poloprůhledná „poznámka“ (viz [Průhledné okno](#průhledné-okno)); bez grafické relace běží procvičování přímo v terminálu.

**Stav testování:** vyvíjeno a vyzkoušeno na Arch Linuxu s kompozitorem **niri** (Wayland). Okna jsou běžná GTK4 a nic není vázané na niri, ale **GNOME, KDE, Hyprland, sway ani X11 zatím otestované nejsou** – hlášení o chybách jsou vítaná.

## Instalace

```sh
git clone https://github.com/navik61/jazyky.git ~/Projects/Jazyky
cd ~/Projects/Jazyky

# závislosti (Arch; jinde obdobné balíčky – viz Závislosti)
sudo pacman -S --needed uv mpv ffmpeg gtk4 gobject-introspection cairo pkgconf meson gcc noto-fonts-emoji libnotify
uv tool install piper-tts                 # hlas pro cizí jazyky
uv tool install edge-tts                  # český hlas (online)

# hlasy Piper → ~/.local/share/piper (viz tabulka ve Slovnících), např.:
mkdir -p ~/.local/share/piper && cd ~/.local/share/piper
curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx
curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx.json
cd -

./nainstaluj-spoustece.sh                 # položky „Slovíčka“ v nabídce aplikací
ln -s "$PWD/slovicka.sh" ~/.local/bin/slovicka
```

První spuštění okna trvá asi 20 s (`uv` sestaví PyGObject), další už jsou rychlá. Jazyk rozhraní a tvůj jazyk se napoprvé vezmou z `LANG`; změníš je v nabídce (**💬 Můj jazyk**, **🌐 Jazyk rozhraní**) nebo volbami `--z` / `--locale`.

### Windows (WSL2) – netestováno

> ⚠️ **Netestováno.** Postup vychází z toho, co skripty potřebují (bash, GTK4, mpv, Piper), ale na Windows jsem ho nevyzkoušel. Přímo ve Windows (PowerShell, `cmd`) skripty nepoběží – jsou v `bash` a okna používají GTK4 pod Waylandem/X11. Cesta je **WSL2 s Ubuntu a WSLg** (grafické aplikace a zvuk z Linuxu přímo ve Windows 11, případně Windows 10 22H2).

1. V PowerShellu jako správce: `wsl --install -d Ubuntu`, restart, vytvoř uživatele. Aktuální WSL: `wsl --update`.
2. V Ubuntu:

```sh
sudo apt update
sudo apt install -y git curl mpv ffmpeg build-essential pkg-config meson \
    libgtk-4-dev gir1.2-gtk-4.0 libgirepository1.0-dev libcairo2-dev \
    libnotify-bin fonts-noto-color-emoji fonts-noto-core
# kdyby sestavení PyGObject hlásilo chybějící girepository-2.0: apt install libgirepository-2.0-dev
curl -LsSf https://astral.sh/uv/install.sh | sh && exec $SHELL
uv tool install piper-tts && uv tool install edge-tts

git clone https://github.com/navik61/jazyky.git ~/Projects/Jazyky
cd ~/Projects/Jazyky
mkdir -p ~/.local/bin && ln -s "$PWD/slovicka.sh" ~/.local/bin/slovicka
# hlasy Piper → ~/.local/share/piper (stejně jako výše v Instalaci)
slovicka            # nebo: slovicka de, slovicka gr
```

3. Spouštěj z terminálu Ubuntu (Windows Terminal). `nainstaluj-spoustece.sh` (rofi/fuzzel) ve WSL nedává smysl; výběr jazyka se ukáže jako GTK nabídka.

**Co může dělat potíže** (nezkoušeno): zvuk jde přes PulseAudio z WSLg (`mpv` musí slyšet výstup – ověř `mpv --no-video soubor.mp3`); okno pod WSLg se může chovat jinak než ve skutečném kompozitoru (průhlednost pozadí, plovoucí okno, fokus); první start trvá déle, protože `uv` sestavuje PyGObject. Pokud to nepůjde, použij `SLOVICKA_V_TERMINALU=1` (jen textový režim). Zkušenosti a chyby prosím jako issue na GitHubu.

## Rychlé použití

```sh
jaz                 # interaktivní procvičování, jazyk a pořadí se vyberou z nabídky
jaz de              # rovnou němčina (z tvého jazyka, u autora čeština)
jaz en --swap       # angličtina, nejdříve tvůj jazyk
jaz it --neznama    # jen dříve neznámá slovíčka
jaz es --z de       # španělština pro mluvčí němčiny
jaz cs --z en --locale en   # čeština pro angličtináře, rozhraní anglicky
jaz de --intro      # nejdřív 60 s úvodní obrázek s hudbou, 5 s pauza, pak procvičování
jaz --pasivni de    # pasivní poslech (stačí i jen „pasivni“ nebo „--passive“)
jaz pasivni it -n 50 --intro   # pasivní poslech 50 slovíček s intrem
```

Po výběru jazyka a pořadí se otevře plovoucí okno a vše běží v něm. Terminál se hned uvolní (okno je od něj odpojené).

### Ovládání v okně

| Klávesa | Pasivní (`jaz --pasivni`) | Interaktivní (`jaz`) |
|---|---|---|
| `mezera` | pauza / pokračovat – zastaví i rozpracované čtení | play / pauza – během čtení pozastaví a pustí dál, po dočtení přehraje slovíčko znovu |
| `Enter` | – | znám (i během čtení – čtení se přeruší) |
| `n` | – | neznám (uloží se) |
| `z` | zopakovat slovíčko od začátku (kdykoli, i v pauze) | zopakovat slovíčko (pak odpověz) |
| `x` | označit chybnou frázi | označit chybnou frázi (pak odpověz) |
| `q` | konec | konec |
| zavření okna | konec | konec |

V interaktivním režimu se odpověď potvrzuje Enterem (`n⏎`, `z⏎`, `x⏎`), v pasivním stačí stisk klávesy. To platí jen v záložním režimu v terminálu – v okně stačí v obou režimech stisk klávesy (bez Enteru); `Esc` = `q`.

### Aliasy a spuštění bez terminálu

Aliasy (autor je má v `~/dotfiles/zsh/.funkce/aliasy`):

```sh
alias jaz="~/Projects/Jazyky/slovicka.sh"          # výchozí interaktivní, --pasivni = poslech
alias jazi="~/Projects/Jazyky/slovicka-interaktivni.sh"
```

`slovicka.sh` je společný spouštěč: bez volby spustí `slovicka-interaktivni.sh`, s `--pasivni` / `pasivni` / `-P` spustí `slovicka-pasivni.sh`; ostatní argumenty předá beze změny (pořadí nehraje roli). `--interaktivni` / `-I` vynutí interaktivní režim. Volby pasivního režimu (`--pocet`, `--pauza`, `--vsechna`) fungují jen s `--pasivni`.

Staré aliasy `jazt` / `jazit` s volbou `--pruhledne` dál fungují – volba se jen ignoruje, průhledné okno je teď výchozí.

Skripty mají symlinky v `~/.local/bin` (je v `PATH`), takže jdou spustit i ze spouštěče aplikací (rofi `Ctrl+Space` režim `run`, fuzzel…): `slovicka` (výchozí interaktivní), `slovicka-pasivni`, `slovicka-interaktivni`. Bez terminálu se výběr jazyka a pořadí zobrazí jako **nabídka v GTK** ve stejném stylu jako karta (`slovicka-view.py --vyber`; šipky / `j` `k` / číslice / myš, `Enter` vybrat, `Esc` zrušit). Bez `uv` záložně přes `rofi`, `fuzzel`, `wofi` nebo `zenity` (co je nainstalované). Chyby se ukážou jako notifikace (`notify-send`).

**Nabídka aplikací (fuzzel, rofi `-show drun`, GNOME, KDE):** spouštěče aplikací ukazují jen programy s `.desktop` souborem, ne skripty z `PATH`. Vytvoří je:

```sh
./nainstaluj-spoustece.sh               # → ~/.local/share/applications/cz.slovicka*.desktop
./nainstaluj-spoustece.sh --odinstaluj
```

V nabídce pak jsou **Slovíčka** (interaktivní) a **Slovíčka – poslech** (pasivní); najdou se i podle slov „jazyky“, „slovicka“ nebo názvu jazyka. Cesta k projektu je v souborech napevno – po přesunu složky spusť skript znovu.

Symlinky do `PATH` (pro rofi v režimu `run` a terminál):

```sh
ln -s ~/Projects/Jazyky/slovicka.sh ~/.local/bin/slovicka
ln -s ~/Projects/Jazyky/slovicka-interaktivni.sh ~/.local/bin/slovicka-interaktivni
ln -s ~/Projects/Jazyky/slovicka-pasivni.sh ~/.local/bin/slovicka-pasivni
```

## Volby

| Volba | Význam | Režim |
|---|---|---|
| `cs`, `de`, `en`, `it`, `fr`, `es`, `ru`, `<kód>_golf` | co se učíš (bez zadání nabídka); nesmí být stejné jako tvůj jazyk | oba |
| `--z X`, `--from X`, `-f X` | tvůj (mateřský) jazyk, viz [Jazyky a rozhraní](#jazyky-a-rozhraní) | oba |
| `--locale X`, `-l X` | jazyk rozhraní | oba |
| `--pasivni`, `--passive`, `-P` | pasivní poslech místo interaktivního (jen přes `jaz` / `slovicka.sh`) | – |
| `--swap`, `-s` | nejdříve tvůj jazyk, pak cizí | oba |
| `--orig`, `-o` | nejdříve cizí jazyk, pak tvůj | oba |
| `--neznama`, `--unknown`, `-u` | jen uložená neznámá slovíčka | oba |
| `--bez-frazi`, `--no-phrases` | nezobrazovat a nečíst vzorové věty | oba |
| `--bez-sumu`, `--no-noise` | bez tichého šumu na pozadí (viz [Zvuk na pozadí](#zvuk-na-pozadí)) | oba |
| `--intro`, `intro` | před procvičováním úvodní obrázek s hudbou (viz [Intro](#intro---intro)) | oba |
| `--gr`, `gr`, `--gramatika`, `-g` | gramatika místo slovíček, viz [Gramatika](#gramatika---gr) (cs → 6 jazyků, en → cs/de/fr/it/es, ru-cs, de-cs…) | interaktivní |
| `--vsechna`, `--all`, `-a` | projít celý slovník | pasivní |
| `--pocet N`, `--count N`, `-n N` | počet slovíček (výchozí 30) | pasivní |
| `--pauza N`, `--pause N`, `-p N` | pauza mezi slovíčky v sekundách, i desetinná (výchozí 3) | pasivní |
| `-h`, `--help` | nápověda (v jazyce rozhraní) | oba |

Bez `--swap` / `--orig` se skript na pořadí zeptá (Enter = cizí jazyk první). Interaktivní kolo má vždy 30 slovíček.

## Jazyky a rozhraní

Každý ze sedmi jazyků může být **tvůj jazyk** (z něj se učíš, do něj se překládá) i **cílový jazyk** (ten se učíš). Nabídka ukazuje všechny cílové jazyky kromě tvého a na konci dvě nastavení:

- **💬 Můj jazyk** – tvůj (mateřský) jazyk,
- **🌐 Jazyk rozhraní** – jazyk nabídek, nápověd a hlášek (7 jazyků).

Volba v nabídce se uloží do `~/.config/slovicka/nastaveni` (`zdroj=cs`, `locale=cs`) a platí i příště. Pořadí, odkud se jazyky berou:

| | 1. | 2. | 3. | 4. |
|---|---|---|---|---|
| tvůj jazyk | `--z` | `SLOVICKA_ZDROJ` | uložené nastavení | jazyk rozhraní |
| rozhraní | `--locale` | `SLOVICKA_LOCALE` | uložené nastavení | `LC_ALL` / `LC_MESSAGES` / `LANG` (jinak angličtina) |

Texty rozhraní jsou v `locale/<kód>.tsv` (klíč TAB text). Upravují se v `nastroje/texty-rozhrani.py`, který je vygeneruje pro všech 7 jazyků najednou (stejné klíče všude). Chybějící klíč se vezme z angličtiny.

Hlasy: čeština `edge-tts` (online), ostatní jazyky Piper (offline). Čte se slovo v cílovém jazyce, překlad v tvém jazyce a věta v cílovém jazyce.

## Soubory

| Soubor | Popis |
|---|---|
| `slovicka.sh` | spouštěč (alias `jaz`): výchozí interaktivní, `--pasivni` = poslech |
| `slovicka-interaktivni.sh` | interaktivní procvičování |
| `slovicka-pasivni.sh` | pasivní poslech |
| `spolecne.sh` | sdílený kód (jazyky, slovník, TTS, věty, okno, nabídky, neznámá slovíčka); načítá se přes `source` |
| `slovicka-view.py` | průhledné okno, nabídka a dialog intra (GTK4 + Pango), spouští se přes `uv run --script` |
| `slovnik/obecne.tsv`, `slovnik/golf.tsv` | slovník pojmů – viz [Slovník pojmů](#slovník-pojmů) |
| `fraze/<sada>-<jazyk>.tsv` | vzorové věty v cílovém jazyce a jejich překlady |
| `gramatika/<cíl>-<zdroj>.tsv` | gramatické tvary: věty a doslovný překlad (`en-cs.tsv`, `cs-en.tsv`, `de-cs.tsv`, `fr-cs.tsv`, `it-cs.tsv`, `es-cs.tsv`, `ru-cs.tsv`, `de-en.tsv`, `fr-en.tsv`, `it-en.tsv`, `es-en.tsv`) |
| `fraze/chybne.tsv` | věty označené klávesou `x` (vzniká sám) |
| `locale/<kód>.tsv` | texty rozhraní (generuje `nastroje/texty-rozhrani.py`) |
| `intro.txt`, `intro.<kód>.txt` | text úvodního obrázku (česky / v jazyce rozhraní) – každý řádek = jedna věta |
| `intro/` | fotka a hudba pro intro; `intro/.vygenerovano/` = složené obrázky (vznikají samy) |
| `intro-obrazek.py` | skládá úvodní obrázek (Pillow přes `uv run --script`) |
| `neznama/<tvůj>-<cíl>.txt` | uložená neznámá slovíčka (vznikají samy, nejsou v gitu); u gramatiky `<tvůj>-<cíl>-gr.txt` |
| `generuj-claude.py` | doplňuje slova a věty přes Claude Batch API |
| `nainstaluj-spoustece.sh` | vytvoří položky v nabídce aplikací (`.desktop`, přeložené) |
| `nastroje/texty-rozhrani.py` | zdroj textů rozhraní ve všech jazycích |
| `nastroje/migrace-pojmy.py` | jednorázový převod starých slovníků „cizí — česky“ na pojmy (historie) |
| `rozbor-skriptu.md` | studijní materiál – výklad skriptů pro učení bashe |

## Slovník pojmů

Slovník je tabulka **pojmů**: jeden řádek = jeden význam, sloupce = slovo v každém jazyce. Díky tomu jde procvičovat libovolnou dvojici jazyků.

```
id	cs	de	en	it	fr	es	ru
o00177	klíč	der Schlüssel	the key	la chiave	la clé	la llave	ключ
```

- Dvě sady: `obecne` (~5 000 pojmů: základní slovesa, dům, město, jídlo, tělo, práce, ekonomika, technika, příroda, pocity, ustálená spojení) a `golf` (~1 500 pojmů golfové terminologie). Golfová sada se vybírá klíčem `<kód>_golf`.
- Varianty se oddělují `/` a čtou se zvlášť (`la clé / la clef`). Poznámky v závorce upřesňují význam.
- Pojem, kterému chybí slovo v tvém nebo cílovém jazyce, se při procvičování přeskočí.
- Pojmy vznikly sloučením původních slovníků „cizí slovo — česky“ podle českého významu (`nastroje/migrace-pojmy.py`); chybějící jazyky doplnil Claude (`generuj-claude.py slova`).

| Kód | Jazyk | Hlas |
|---|---|---|
| `cs` | čeština | `edge-tts` cs-CZ-AntoninNeural (online) |
| `de` | němčina | Piper `de_DE-thorsten-medium` |
| `en` | angličtina | Piper `en_US-lessac-medium` |
| `it` | italština | Piper `it_IT-riccardo-x_low` |
| `fr` | francouzština | Piper `fr_FR-siwis-medium` |
| `es` | španělština | Piper `es_ES-davefx-medium` |
| `ru` | ruština | Piper `ru_RU-irina-medium` |

Hlas Piper stáhni z https://huggingface.co/rhasspy/piper-voices (`.onnx` i `.onnx.json`) do `~/.local/share/piper/`. Nový jazyk se přidá v `spolecne.sh` (`JAZYKY`, `VLAJKY`, `TTS_MODELY`), novým sloupcem ve `slovnik/*.tsv` a `fraze/*.tsv`, v `generuj-claude.py` (`JAZYKY`, `NAZEV`) a v `nastroje/texty-rozhrani.py` (nový sloupec textů).

## Vzorové věty

Ke každému pojmu je v každém cílovém jazyce vzorová věta s překladem do ostatních jazyků. V okně je pod slovíčkem (věta tyrkysově kurzívou, překlad do tvého jazyka šedě). Po slovíčku a překladu se přečte i věta.

Formát `fraze/<sada>-<cílový jazyk>.tsv` – paralelní věty: sloupec cílového jazyka je věta, ostatní její překlady:

```
id	cs	de	en	it	fr	es	ru
o00177	Nemůžu najít klíč od auta.	Ich finde den Autoschlüssel nicht.	I can't find the car key.	Non trovo più la chiave della macchina.	…
```

Věty se přiřazují podle `id` pojmu, takže úprava slova ve slovníku větu nerozbije. Věty i překlady lze opravovat ručně přímo v `.tsv`. Chybí-li překlad do tvého jazyka, ukáže se věta bez něj.

### Chybné věty (`x`)

Klávesa `x` připíše větu aktuálního slovíčka do `fraze/chybne.tsv` (bez duplicit) a v nápovědě se ukáže **✗ věta označena**:

```
<sada>-<cíl>	<id>	<tvůj jazyk>	<věta>	<překlad>
```

Opravu udělej ručně v `fraze/<sada>-<cíl>.tsv`, nebo nech opravit Claude („oprav věty z fraze/chybne.tsv“). Po opravě řádky z `chybne.tsv` smaž.

### Generování přes Claude (`generuj-claude.py`)

Doplňuje jen to, co chybí – po přidání pojmů stačí spustit znovu. Používá Claude **Batch API** (zpracování na pozadí, obvykle do hodiny, sleva 50 %).

```sh
./generuj-claude.py slova --nanecisto     # plán a odhad ceny, nic neodešle
./generuj-claude.py slova                 # 1. chybějící slova v pojmech
./generuj-claude.py vety                  # 2. věty a jejich překlady do všech jazyků
./generuj-claude.py vety --jazyky es --sady golf --limit 20   # jen část (zkouška)
./generuj-claude.py --stav                # stav odeslané dávky
```

- Krok `slova` dostane do zadání ukázky existujících hesel, aby dodržel zvyklosti (členy u podstatných jmen, infinitiv sloves, vidové dvojice v ruštině…).
- Krok `vety` napíše větu jen tam, kde chybí, a přeloží ji do jazyků, kde chybí překlad.
- Před odesláním ukáže počet položek a odhad ceny a zeptá se (`--ano` = neptat se). Po stažení vypíše skutečnou cenu.
- Ctrl+C dávku nezruší – dalším spuštěním se jen stáhnou výsledky (rozpracovaná dávka je v `fraze/.claude-batch.json`). Neplatné výsledky (příliš krátké, opsané heslo) odešle další spuštění.
- Volby: `--model claude-sonnet-5-5 | claude-opus-5-5 | claude-haiku-5-5` (výchozí Sonnet), `--effort low | medium | high`, `--davka N` (výchozí 40 slov / 8 vět – při větších dávkách model část položek vynechával), `--sady`, `--jazyky`, `--limit`.
- Přihlášení – jedno z: `ant auth login` (profil Console, výchozí), nebo API klíč v `~/.config/anthropic/api-key` (chmod 600). API klíč nedávej do `.zshrc` – Claude Code by ho začal používat místo předplatného.

**Stav (24. 11. 2026):** původní české slovníky a věty (20 847 slovíček, 8,47 USD) převedeny na pojmy; doplnění na všech 7 jazyků vygeneroval Claude Sonnet 5.5 za 59,04 USD (18 497 slov, ~21 000 nových vět, ~248 000 překladů). Všech 6 555 pojmů má slovo, větu i překlady ve všech sedmi jazycích.

## Gramatika (`--gr`)

```bash
jaz gr              # cs → angličtina (podle tvého jazyka; cíl se vybere sám)
jaz gr --z en       # mateřština angličtina → čeština, němčina, francouzština, italština nebo španělština
# mateřština čeština má víc cílů (angličtina, němčina, francouzština, italština, španělština, ruština) – nabídne se výběr
jaz gr --neznama    # jen uložené neznámé tvary
```

Procvičují se **gramatické tvary** cílového jazyka. Každá karta má tři části, vždy v tomto pořadí:

1. věta v **tvém jazyce**,
2. věta v **cílovém jazyce**,
3. **doslovný překlad slovo od slova** (`≈`, kurzívou) do tvého jazyka – ukazuje, jak se v cílovém jazyce *myslí* (např. `I have lived here for five years` → `Já mám žil tady po pět rok`).

V záhlaví je název tvaru (Present Perfect – for, Conditional 2, Lokál – o …). Čtou se všechny tři části. Ovládání je stejné jako u slovíček (`Enter` znám, `n` neznám, mezera pauza, `z` znovu, `q` konec); pořadí je pevné, `--swap` se ignoruje. Kolo má 30 tvarů, neznámé se opakují a ukládají do `neznama/<tvůj>-<cíl>-gr.txt`.

**Co je v datech** (`gramatika/<cíl>-<zdroj>.tsv`, sloupce `id`, `tvar`, věta v mateřském jazyce, věta v cílovém, doslovný překlad):

- `fr-en.tsv` (137), `it-en.tsv` (135), `es-en.tsv` (141) – francouzština, italština a španělština pro anglicky mluvící: tvary, které angličtinu zaskočí – rod a shoda, přivlastňovací zájmeno shodné s vlastněnou věcí (*sa mère*), člen u obecných tvrzení, dělivý člen, zájmena před slovesem, *avoir/être*, *avere/essere*, vynechaný podmět, *ser × estar*, osobní *a*, *piacere/gustar* (podmět a předmět se prohazují), *depuis/da/desde hace* a *llevar + gerundio* (= „už dělám“), *por × para*, subjuntivo, *se*… Doslovný překlad je do angličtiny (`(I)-speak`, `to-the`, `.pp .f .pl .subj .impf .fut .cond .formal`, `.ser/.estar`).
- `de-en.tsv` – němčina pro anglicky mluvící (108 vět): slovosled (sloveso na 2. místě, na konci vedlejší věty), odlučitelná a zvratná slovesa, Perfekt (*haben* × *sein*) a Präteritum, modální slovesa, **pády** a předložky, 3./4. pád, skloňování přídavných jmen, Konjunktiv I/II, pasivum, *man*, *es gibt*… (doslovný překlad do angličtiny, značky `.acc .dat .gen`, `.subj`, `-t`)
- `en-cs.tsv` – angličtina pro Čechy (100 vět): všechny časy (prostý, průběhový, předpřítomný, předminulý, budoucí vč. průběhových a perfekta), trpný rod, modální slovesa, podmínkové věty 0–3 a smíšené, *wish*, nepřímá řeč, otázky (podmět, předmět, dovětek, nepřímé), rozkaz, gerundium × infinitiv, stupňování, vztažné věty, členy a počitatelnost, kauzativ, frázová slovesa…
- `ru-cs.tsv` – ruština pro Čechy (120 vět): přítomný čas, **vynechané sloveso být** (`[je]`), *u меня есть*, minulý čas podle rodu, **vid** (nedokonavý × dokonavý), slovesa pohybu (určitá × neurčitá, `.det` / `.indet`), zápory a dvojitý zápor, **všech šest pádů** (genitiv po číslovkách, akuzativ životných, instrumentál, lokál), dativní konstrukce (*мне нравится, мне надо*), přídavná jména a zájmena, komparativ a superlativ, *бы* a *чтобы*, modální a neosobní konstrukce, čas, datum, vztažné věty (*который*), pasivum…
- `it-cs.tsv` – italština pro Čechy (117 vět): přítomný čas, vynechané podmětové zájmeno, členy vč. dělivého a splývání předložek, zápory (*non … niente/mai/nessuno/più*), *passato prossimo* (*avere* × *essere*, shoda), *imperfetto*, *passato remoto*, budoucí čas, *stare + gerundio*, kondicionál, rozkaz se zájmeny, zájmena (*ci*, *ne*, dvě zájmena), *piacere*, *c'è*, *da*, *congiuntivo*, pasivum (*essere* × *venire*), *si* (trpné a neosobní), vztažné věty…
- `es-cs.tsv` – španělština pro Čechy (130 vět): přítomný čas a změny kmene (*e→ie, o→ue, e→i*), **ser × estar**, členy, zkrácené tvary (*buen, gran*), zápory, osobní *a*, *pretérito perfecto* × *indefinido* × *imperfecto*, budoucí čas, *estar/seguir/llevar + gerundio*, kondicionál, rozkaz, zájmena (*le → se*), *por × para*, *gustar/doler*, *hay*, *desde hace*, *tener que × hay que*, *subjuntivo*, pasivum, *se* (zvratné, neosobní, nechtěná událost)…
- `fr-cs.tsv` – francouzština pro Čechy (119 vět): přítomný čas (-er/-ir/-re, nepravidelná), členy vč. dělivého, shoda přídavných jmen, zápory (*ne … pas/jamais/rien/plus/que*), otázky (intonace, *est-ce que*, inverze), *passé composé* (*avoir* × *être*, shoda příčestí), *imparfait*, budoucí čas, kondicionál, rozkaz, **zájmena** (*le/lui/y/en*, dvě zájmena), předložky, *il y a*, *depuis*, *venir de*, vztažné věty (*qui/que/où/dont*), *subjonctif*, pasivum, *on*, čas, datum, číslovky 70–99…
- `de-cs.tsv` – němčina pro Čechy (105 vět): přítomný čas a změna kmenové samohlásky, odlučitelná a zvratná slovesa, slovosled (sloveso na 2. místě, vedlejší věty se slovesem na konci, *weil/dass/wenn/obwohl/ob/denn*), Perfekt (*haben* × *sein*) a Präteritum, Plusquamperfekt, Futur, modální slovesa, rozkaz, **pády** (akuzativ, dativ, genitiv, předložky se 3./4. pádem), skloňování přídavných jmen, stupňování, vztažné věty, Konjunktiv I a II, pasivum, *man*, *es gibt*, zájmenná příslovce, čas a datum…
- `cs-en.tsv` – čeština pro anglicky mluvící (68 vět): časy, vid (dokonavý × nedokonavý), kondicionál, rozkaz, zvratná slovesa, slovesa pohybu, modální a neosobní konstrukce, **všech sedm pádů** (po několika příkladech), číslovky, shoda přídavných jmen, stupňování, vedlejší věty (*že, aby, jestli*)…

**Značky v doslovném překladu:**

| Značka | Význam |
|---|---|
| `[the]`, `[a]`, `[do]`, `[did]`, `[does]` | slovo, které v tvém jazyce nemá protějšek (členy, pomocné sloveso) |
| `pracovat-s` | koncovka 3. osoby (`works`); `ne-je` = spojené slovo |
| `mít_rád` | jedno slovo přeložené více slovy (podtržítko) |
| `(I)-work`, `.loc`, `.acc` … | česky: vynechané osobní zájmeno v závorce, pád a vid jako přípona (`.nom .gen .dat .acc .voc .loc .ins`, `.pf` / `.impf`, `.m .f .n`, `.pl`) |

U en-párů (fr/it/es) navíc: `.pp` = příčestí, `.formal` = vykání, `.we` = 1. os. mn. č., `.pret` = pretérito indefinido (i `.remote` = passato remoto), `.isc` = -isc- (it), `.ie/.ue/.i/.u` = změna kmene (es). U ruštiny navíc: `[je]` = vynechané sloveso *být* v přítomném čase, `.det` / `.indet` = slovesa pohybu určitá / neurčitá, `.fut`, `.cond`, `.subj` = budoucí čas, kondicionál, spojovací způsob (u it/es/fr/de i `.ser` / `.estar`, `.impf`, `.pr`).

Při čtení se vynechá každá značka tvaru `.přípona` (`.acc`, `.pp`, `.ser` …), závorky, spojovníky a lomítka (`_gr_dosl_tts`).

**Přidání dalšího jazyka:** vytvoř `gramatika/<cíl>-<zdroj>.tsv` se stejnými sloupci (hlavička + řádky oddělené tabulátorem); volba `--gr` ho najde sama, žádný kód se nemění.

## Neznámá slovíčka

Slovíčka označená v interaktivním režimu `n` se ukládají do `neznama/<tvůj jazyk>-<cíl>.txt` (id pojmů, bez duplicit), i při ukončení klávesou `q`. Každá dvojice jazyků má vlastní soubor.

- Procvičíš je volbou `--neznama` nebo v nabídce položkou **Neznámá: … (počet)** – ta se ukáže jen u jazyků, které nějaká neznámá slovíčka mají.
- V režimu `--neznama` se slovíčko, které v **1. kole** označíš jako známé, ze souboru odebere (opakovací kola soubor nemění). Prázdný soubor se smaže.
- Pasivní režim umí `--neznama` také (jen poslech, soubor nemění).

## Průhledné okno

Slovíčko, překlad a fráze se vykreslí přes Pango do průhledného okna bez rámečku (styl převzatý z autorových poznámek `pozt`). Okno má pevnou šířku, výška se přizpůsobí délce fráze. Okno běží přes `uv run --script` – knihovnu PyGObject si `uv` při prvním spuštění sestaví sám (asi 20 s, pak z cache). Bez grafické relace nebo bez `uv` běží procvičování přímo v terminálu.

| Proměnná | Význam | Výchozí |
|---|---|---|
| `SLOVICKA_STYL` | barvy a font podle stylů poznámek 0–9 (0 tmavě zelená, 2 vínová, 3 tmavě modrá, 4 Nord, 9 velké čitelné…) | `0` |
| `SLOVICKA_ALFA` | krytí pozadí, hex `00`–`ff` | `POZNAMKA_ALFA`, jinak `b3` (≈ 70 %) |
| `SLOVICKA_ZOOM` | zvětšení celého okna | `1` |
| `SLOVICKA_SIRKA` | šířka okna v px (před zoomem) | `760` |

```sh
SLOVICKA_STYL=3 SLOVICKA_ZOOM=1.2 jaz it
```

Klávesy navíc: `=` / `-` / `0` zoom, tažení myší přesun okna. Zavření okna ukončí procvičování (rozpracované kolo se neuloží, `q` ano). App-id: `cz.slovicka.view` (karta i intro), `cz.slovicka.vyber` (nabídka) – viz [Jiná prostředí](#jiná-prostředí-wayland-x11).

**Jak to funguje:** spouštěč pustí odpojeně `slovicka-view.py --rezim znaky|radky -- <skript> …`. Prohlížeč spustí skript s `SLOVICKA_V_OKNE=2` ve vlastní skupině procesů. Skript mu posílá příkazy (`KARTA`, `NAPOVEDA`, `ZPRAVA`, `INTRO`, `INTRO_KONEC`, pole oddělená tabulátorem) na deskriptor `$SLOVICKA_FD` funkcí `_view` ze `spolecne.sh`, a stisknuté klávesy dostává na stdin (pasivní jako znak pro `read -n1`, interaktivní jako řádek pro `read -r`). Terminálový výstup skriptu jde do `/dev/null`. Konec skriptu zavře okno, zavření okna pošle skupině `SIGTERM` (ukončí i `piper`/`mpv`).

## Intro (`--intro`)

S volbou `--intro` (nebo jen `intro`) se po výběru jazyka nejdřív v okně nad kartou ukáže úvodní obrázek (1280 × 720) a hraje hudba (60 s), pak je 5 s pauza s odpočtem a začne procvičování. `q`, `Esc`, mezera nebo `Enter` v okně s obrázkem intro přeskočí; `q` v kartě procvičování ukončí.

```sh
jaz de --intro      # interaktivní procvičování s intrem
jaz pasivni it intro   # pasivní poslech s intrem
```

**Obsah, který můžeš měnit:**

| Co | Kde | Poznámka |
|---|---|---|
| text | `intro.txt` (česky), `intro.<kód>.txt` (ostatní jazyky rozhraní) | každý neprázdný řádek = jedna věta, písmo se zmenší, aby se vešlo; chybí-li text pro jazyk rozhraní, použije se anglický |
| fotka | `intro/*.jpg`, `*.png`, `*.webp` | použije se **nejnovější** soubor; ořízne se na 16 : 9 (střed) |
| hudba | `intro/*.ogg`, `*.mp3`, `*.opus`, `*.flac`, `*.wav`, `*.m4a` | nejnovější soubor; hraje se max. 60 s, kratší skladba nevadí |

Stačí soubor přidat nebo přepsat. Při každém spuštění s `--intro` skript spočítá otisk (sha256) textu, fotky, seznamu vlajek a `intro-obrazek.py` a porovná ho s `intro/.vygenerovano/intro-<kód>.otisk`. Když se něco změnilo, složí nový obrázek `intro/.vygenerovano/intro-<kód>.jpg` (pro každý jazyk rozhraní zvlášť): nahoře vlajky všech sedmi jazyků (Noto Color Emoji), dole text z `intro.txt`, pod obojím tmavý přechod kvůli čitelnosti. Beze změny se nic negeneruje (kontrola trvá pár ms).

| Proměnná | Význam | Výchozí |
|---|---|---|
| `SLOVICKA_INTRO_DELKA` | délka intra v sekundách | `60` |
| `SLOVICKA_INTRO_PAUZA` | pauza před procvičováním | `5` |
| `SLOVICKA_INTRO_SIRKA` | šířka okna s obrázkem v px (výška 16 : 9) | `1280` |

Obrázek ukazuje `slovicka-view.py` jako dialog nad kartou (příkaz `INTRO`), hudba hraje přes `mpv`. Dialog s rodičovským oknem otevře každý kompozitor jako plovoucí – i dlaždicové (niri, sway, Hyprland) – bez jakýchkoli pravidel v konfiguraci. Bez okna (terminálový režim) hraje jen hudba.

**Výchozí obsah:** fotka *Rainier Meadow (July 2005)*, autor Jancarhart, volné dílo (Wikimedia Commons); hudba W. A. Mozart – *Malá noční hudba* (Serenáda G dur, K. 525), 1. věta Allegro, prvních 60 s nahrávky Musopen, volné dílo (Wikimedia Commons).

## Jiná prostředí (Wayland, X11)

Všechna okna jsou GTK4, takže by měla fungovat v libovolném Wayland kompozitoru (GNOME, KDE, niri, sway, Hyprland…) i na X11. Nic není vázané na niri. **Otestováno je zatím jen niri; GNOME, KDE, Hyprland, sway a X11 netestovány.**

- **Terminál mimo relaci (tty, ssh, `tmux`):** když chybí `WAYLAND_DISPLAY` i `DISPLAY`, skript sám najde socket `$XDG_RUNTIME_DIR/wayland-N` a okno se otevře. Textový režim vynutíš `SLOVICKA_V_TERMINALU=1`.
- **Plovoucí okna:** karta a nabídka mají pevnou velikost, intro je dialog nad kartou. GNOME a KDE je zobrazí normálně, niri je otevře jako plovoucí samo. Pro jiné dlaždicové kompozitory, které okno s pevnou velikostí dají do dlaždic, stačí jedno pravidlo:

  ```sh
  # sway (~/.config/sway/config)
  for_window [app_id="^cz\.slovicka\."] floating enable, border none

  # Hyprland (hyprland.conf, syntaxe 0.53+; starší: windowrule = float, class:^(cz\.slovicka\..*)$)
  windowrule = match:class ^(cz\.slovicka\..*)$, float 1

  # mango (config.conf)
  windowrule=isfloating:1,appid:cz.slovicka.view
  windowrule=isfloating:1,appid:cz.slovicka.vyber
  ```

- **Fokus:** Wayland nedovolí oknu vzít si fokus samo; potřebuje aktivační token (xdg-activation, na X11 `DESKTOP_STARTUP_ID`). Skript převezme token od spouštěče, předá ho první nabídce a každá nabídka po výběru vydá token pro další okno (soubor `$XDG_RUNTIME_DIR/slovicka-aktivace.<PID>`). Okna se tak otevřou navrchu i v GNOME a KDE.
- **Umístění:** o poloze okna rozhoduje kompozitor (Wayland ji aplikacím nedovolí určit). Okno jde přesunout tažením myší.
- **Grafická karta:** `slovicka-view.py` vynucuje integrovanou AMD grafiku (`VK_DRIVER_FILES`, `__EGL_VENDOR_LIBRARY_FILENAMES`) jen tehdy, když ty ovladače v systému jsou; jinde nechá výběr na GTK.
- **Fonty:** `intro-obrazek.py` hledá písma přes `fc-match`, takže nezáleží na cestách dané distribuce.

## Zvuk na pozadí

Po celou dobu procvičování hraje velmi tichý bílý šum. Díky němu se Bluetooth reproduktor neuspí mezi slovíčky a neuřízne začátek krátkých slov. Hraje i během pauzy a skončí spolu se skriptem (konec, `q`, zavření okna). V mixéru (pavucontrol) je vidět jako `slovicka-pozadi`.

| Proměnná | Význam | Výchozí |
|---|---|---|
| `SLOVICKA_POZADI` | `sum` = šum, `ne` = vypnuto, nebo cesta ke zvukovému souboru (hraje ve smyčce) | `sum` |
| `SLOVICKA_SUM_BARVA` | barva šumu: `white`, `pink`, `brown` (hlubší, příjemnější) | `white` |
| `SLOVICKA_SUM_UROVEN` | amplituda šumu (0–1); `0.003` je skoro neslyšné | `0.003` |
| `SLOVICKA_POZADI_HLASITOST` | hlasitost souboru v `mpv` (0–100) | `25` |

```sh
SLOVICKA_SUM_BARVA=brown SLOVICKA_SUM_UROVEN=0.01 jaz de    # slyšitelný hnědý šum
SLOVICKA_POZADI=~/Music/dest.mp3 jazi it                     # vlastní zvuk podle nálady
jaz de --bez-sumu                                            # bez šumu
```

Trvalé nastavení dej do `~/.zshrc` (`export SLOVICKA_SUM_BARVA=pink`). Šum generuje `mpv` přes filtr `anoisesrc` z ffmpeg, žádný soubor není potřeba.

## Jak to funguje

- **Cesty:** `CESTA_SLOVNIKU` se odvozuje z umístění skriptu (`readlink -f`), takže fungují symlinky i přesun složky – stačí upravit aliasy.
- **Gramatika (`--gr`):** `_nacti_gramatiku` naplní `RADKY` identifikátory vět a `RADEK_ID` / `ID_RADEK` jako identitu, takže neznámá, kolo a opakování fungují beze změny; karta (`_zobraz_gramatiku`) posílá oknu větu v mateřském jazyce, cílovou a doslovný překlad (do pole „fráze“).
- **Okno:** po výběru spustí skript sám sebe v `slovicka-view.py` (přes `setsid` a `uv run --script`, odpojeně od terminálu), viz [Průhledné okno](#průhledné-okno). Bez grafické relace nebo `uv` běží přímo v terminálu.
- **Terminálový režim:** kartu skládá `_vypis_kartu` podle skutečné velikosti terminálu: věty zalomí (`fold -s`), prázdné řádky vloží jen když je místo a v krajním případě zkrátí frázi (`…`). Titulek s vlajkami a pořadím tak nikdy neodroluje. Nápovědy kláves v terminálu jsou proto zkrácené (`[x] chyba`, `[⏎] znám`), aby se vešly na jeden řádek.
- **Ovládání (oba režimy):** čtení běží na pozadí a skript mezitím čte klávesy (`read -t`). Mezera pošle čtení `SIGSTOP` / `SIGCONT` (zastaví `piper`, `ffmpeg` i `mpv` uprostřed slova), `z` ho ukončí (`SIGTERM`) a slovíčko začne znovu. Čekání mezi slovíčky měří čas přes `$EPOCHREALTIME`.
- **TTS:** čeština `edge-tts` (bez něj Piper / `espeak-ng`), ostatní jazyky Piper (program: `SLOVICKA_PIPER`, jinak `~/.local/share/uv/tools/piper-tts/bin/piper`, `~/.local/bin/piper`, nebo `piper` z `PATH`; hlasy: `SLOVICKA_PIPER_MODELY`, jinak `~/.local/share/piper`, vzorkovací frekvence se čte z `<model>.onnx.json`; hlasy viz [Slovníky](#slovníky)), čeština `edge-tts` (potřebuje internet), záložně `espeak-ng`. `mpv` běží s `--no-input-terminal`, aby nebral klávesy.
- **Úklid:** při ukončení (`q`, Ctrl+C, zavření okna, chyba) se zastaví čtení, zavře okno a smaže rozpracovaný mp3 v `/tmp`.

## Závislosti

- Intro: `uv` (Pillow si stáhne sám), `mpv`, `fontconfig` (`fc-match`), font Noto Color Emoji (`noto-fonts-emoji`, Debian/Ubuntu `fonts-noto-color-emoji`) pro vlajky a Noto Sans nebo DejaVu Sans.
- Okna (karta, nabídka, intro): `uv`, `gtk4`, `pango`, `gobject-introspection`, `cairo` a překladač (`gcc`, `meson`, `pkgconf`) pro sestavení PyGObject; libovolný Wayland kompozitor nebo X11.
- Skripty: `bash` 5+, `notify-send`, volitelně `rofi` / `fuzzel` / `wofi` / `zenity` (nabídka bez `uv`), `setsid`, `mpv`, `ffmpeg`, `piper-tts` (`uv tool install piper-tts`), `edge-tts`, volitelně `espeak-ng`.
- Generování slov a vět: `uv` a přístup ke Claude API.

## Studijní materiál

[`rozbor-skriptu.md`](rozbor-skriptu.md) – výklad skriptů pro učení bashe ve čtyřech částech: původní verze s technikami a cvičeními, opravy slabých míst (kód před/po), rozšíření o fráze, ovládání klávesami a generátory frází, a současná verze (GTK okno přes `uv`, intro, play/pauza, nabídka a fokus v libovolném Wayland prostředí, jak se testovalo). Cvičení mají řešení v rozbalovacích blocích.

## Kde pokračovat (stav k 24. 11. 2026)

**Hotovo:** učení napříč 7 jazyky, rozhraní v 7 jazycích, slovník pojmů a všechny věty a překlady (commit `e19afcf`, vše pushnuto; dotfiles s aliasy `jaz` a `fex` také pushnuté).

**Další krok – propagační video na YouTube:**

- Skript: `~/Projects/PythonSkripty/intro_jazyky.py` (popis v `~/Projects/PythonSkripty/README.md`, sekce *Propagační video k Jazykům*). Prezentace v plovoucím okně (karta ve stylu aplikace): „Jazyky offline – kdy mám čas a chuť na studium“ → intro → varianty použití (s živými ukázkami) → závěr; snímek 5 s, pauza 2 s. Jedno video: nejdřív anglická verze, pak česká, nahrává monitor DP-2 přes `wf-recorder` i se zvukem.
- Postup:
  1. `./intro_jazyky.py --nahledy` – snímky a video prezentace do `$TMPDIR/intro-jazyky-nahledy` ke kontrole textů.
  2. `./intro_jazyky.py --bez-nahravani` – celá zkouška bez záznamu; během ní nesahat na klávesnici ani myš. Zkontrolovat, že všechny klávesy došly (skript vypíše `! klávesa … neodeslána`).
  3. `./intro_jazyky.py` – ostré natáčení → `~/Videos/jazyky-intro-en-cs-<datum>.mp4`.
- Ověřeno zatím: náhledy snímků (`--nahledy`), plovoucí okno se snímky a pauzou v niri, záznam DP-2 se zvukem, obnova nastavení a neznámých slovíček po ukázce. ukázka interaktivního procvičování přes nabídku (oprava první klávesy z `wtype`). **Neověřeno:** celý běh s ukázkami po této opravě.

## Git

Veřejný repozitář: https://github.com/navik61/jazyky (větev `master`). Uložení změn:

```sh
git add -A && git commit -m "popis změny" && git push
```

Aliasy jsou mimo projekt, v `~/dotfiles`. Pravidla oken pro niri nejsou potřeba.

## Licence

[MIT](LICENSE). Výchozí fotka a hudba v `intro/` jsou volné dílo (viz [Intro](#intro---intro)).

## Řešení problémů

- **Věta se nezobrazuje** – pojem nemá větu v `fraze/<sada>-<cíl>.tsv` (`grep -F 'slovo' fraze/obecne-de.tsv`); doplní ji `./generuj-claude.py vety`.
- **Pro dvojici nejsou žádná slova** – slovník pojmů ještě nemá doplněný jeden z jazyků: `./generuj-claude.py slova`.
- **Rozhraní je anglicky, i když chci česky** – systém má `LANG=en_US…`; v nabídce zvol **🌐 Jazyk rozhraní** nebo spusť s `--locale cs` (uloží se jen přes nabídku).
- **Klávesy nereagují** – okno musí mít fokus; klávesy se čtou jen v okně se slovíčky, ne v původním terminálu.
- **Fráze je zkrácená (`…`) nebo chybí titulek** – v terminálovém režimu se obsah nevejde; zvětši terminál.
- **Ticho místo hlasu** – chybí Piper, jeho hlas nebo `edge-tts` (čeština potřebuje internet). Piper a hlasy jde nasměrovat proměnnými `SLOVICKA_PIPER` a `SLOVICKA_PIPER_MODELY`; bez Piperu se použije `espeak-ng`.
- **Okno se otevře na pozadí (GNOME, KDE)** – okno dostane fokus jen s aktivačním tokenem. Ze spouštěče aplikací (rofi, fuzzel, GNOME) ho skript předává dál, při spuštění z terminálu žádný token není a GNOME ukáže jen hlášku „… je připraveno“.
- **„Chybí …/spolecne.sh“** – `spolecne.sh` musí ležet vedle skriptů.
- **Generátor: „Přihlášení neplatí nebo vypršelo“** – `ant auth login`, pak spusť znovu (dávka mezitím běží dál).
- **BT reproduktor pořád uřízne začátek slova** – zvyš `SLOVICKA_SUM_UROVEN` (např. `0.01`). Některé reproduktory se uspí, i když jim chodí jen velmi tichý signál.
- **Průhledné okno se neotevře** – spusť ručně `./slovicka-view.py --rezim znaky -- ./slovicka-pasivni.sh de --orig` a podívej se na chyby. Když se PyGObject nesestaví, chybí systémové knihovny (`gobject-introspection`, `cairo`) nebo překladač; bez `uv` skript tiše běží v terminálu.
- **Intro se nezmění po úpravě** – mění se jen nejnovější fotka/hudba v `intro/`; po `cp -p` si soubor může ponechat staré datum (`touch soubor`). Vynutit nové složení: `rm -r intro/.vygenerovano`.
- **Místo vlajek prázdná místa** – chybí `noto-fonts-emoji`.
- **`jaz` po změně aliasu nefunguje** – `source ~/.zshrc` nebo nový terminál.
