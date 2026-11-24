# Jazyky – procvičování slovíček

**Česky** · [English](README.en.md)

Skripty pro procvičování slovíček (němčina, angličtina, italština, francouzština, španělština, ruština a golfová terminologie v němčině, angličtině a italštině). Slovíčka se zobrazují v průhledném okně ve stylu poznámek, čtou se nahlas (TTS) a ke každému je vzorová věta s českým překladem.

Dva režimy:

- **interaktivní procvičování** (`jaz` – výchozí) – u každého slovíčka odpovíš „znám / neznám“, neznámá se ukládají a dají se procvičit zvlášť,
- **pasivní poslech** (`jaz --pasivni`) – slovíčka, překlady a fráze běží sama s pauzou, lze pozastavit a opakovat.

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

První spuštění okna trvá asi 20 s (`uv` sestaví PyGObject), další už jsou rychlá.

## Rychlé použití

```sh
jaz                 # interaktivní procvičování, jazyk a pořadí se vyberou z nabídky
jaz de              # rovnou němčina
jaz en --swap       # angličtina, nejdříve česky
jaz it --neznama    # jen dříve neznámá slovíčka
jaz fr              # francouzština (stejně es = španělština, ru = ruština)
jaz de --intro      # nejdřív 60 s úvodní obrázek s hudbou, 5 s pauza, pak procvičování
jaz --pasivni de    # pasivní poslech (stačí i jen „pasivni“)
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
| `de`, `en`, `it`, `fr`, `es`, `ru`, `de_golf`, `en_golf`, `it_golf` | jazyk / slovník (bez zadání nabídka) | oba |
| `--pasivni`, `pasivni`, `-P` | pasivní poslech místo interaktivního (jen přes `jaz` / `slovicka.sh`) | – |
| `--swap`, `-s` | nejdříve česky, pak originál | oba |
| `--orig`, `-o` | nejdříve originál, pak česky | oba |
| `--neznama`, `-u` | jen uložená neznámá slovíčka | oba |
| `--bez-frazi` | nezobrazovat a nečíst vzorové fráze | oba |
| `--bez-sumu` | bez tichého šumu na pozadí (viz [Zvuk na pozadí](#zvuk-na-pozadí)) | oba |
| `--intro`, `intro` | před procvičováním úvodní obrázek s hudbou (viz [Intro](#intro---intro)) | oba |
| `--vsechna`, `-a` | projít celý slovník | pasivní |
| `--pocet N`, `-n N` | počet slovíček (výchozí 30) | pasivní |
| `--pauza N`, `-p N` | pauza mezi slovíčky v sekundách, i desetinná (výchozí 3) | pasivní |
| `-h`, `--help` | nápověda | oba |

Bez `--swap` / `--orig` se skript na pořadí zeptá (Enter = originál první). Interaktivní kolo má vždy 30 slovíček.

## Soubory

| Soubor | Popis |
|---|---|
| `nainstaluj-spoustece.sh` | vytvoří položky v nabídce aplikací (`.desktop`) |
| `slovicka.sh` | spouštěč (alias `jaz`): výchozí interaktivní, `--pasivni` = poslech |
| `slovicka-pasivni.sh` | pasivní poslech |
| `slovicka-interaktivni.sh` | interaktivní procvičování |
| `intro.txt` | text úvodního obrázku – každý řádek = jedna věta |
| `intro/` | fotka a hudba pro intro; `intro/.vygenerovano/` = složený obrázek (vzniká sám) |
| `intro-obrazek.py` | skládá úvodní obrázek (Pillow přes `uv run --script`) |
| `slovicka-view.py` | průhledné okno (GTK4 + Pango), spouští se přes `uv run --script` |
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

| Klíč | Slovník | Hlas Piper |
|---|---|---|
| `de` | `nemcina_slova.txt` | `de_DE-thorsten-medium` |
| `en` | `anglictina_slova.txt` | `en_US-lessac-medium` |
| `it` | `italstina_slova.txt` | `it_IT-riccardo-x_low` |
| `fr` | `francouzstina_slova.txt` | `fr_FR-siwis-medium` |
| `es` | `spanelstina_slova.txt` | `es_ES-davefx-medium` |
| `ru` | `rustina_slova.txt` | `ru_RU-irina-medium` |
| `*_golf` | `golf_<jazyk>.txt` | podle jazyka |

Slovníky fr, es a ru (každý ~3000 hesel) vznikly 24. 11. 2026 podle tematické osnovy italského slovníku: základní slovesa, dům, město, jídlo, tělo, práce, ekonomika, technika, příroda, pocity, ustálená spojení. Italská specifika (jídla, sporty) jsou nahrazena reáliemi daného jazyka (např. paella, crêpe, борщ). Ruská slova jsou bez vyznačeného přízvuku.

Nový jazyk se přidá v `spolecne.sh` (pole `JAZYKY`, `SOUBORY`, `NAZVY`, `VLAJKY`, `TTS_MODELY`, `TTS_JAZYK`) a v `generuj-fraze.py` (`SLOVNIKY`, `PRIKLADY`). Hlas Piper stáhni z https://huggingface.co/rhasspy/piper-voices (`.onnx` i `.onnx.json`) do `~/.local/share/piper/`.

## Vzorové fráze

Ke každému slovíčku je vzorová věta v cizím jazyce s českým překladem. V okně je pod slovíčkem (věta tyrkysově kurzívou, překlad šedě). Po slovíčku a překladu se přečte i cizojazyčná věta.

**Stav (24. 11. 2026):** frázi má všech 20 847 slovíček ze všech devíti slovníků. Vygeneroval je Claude přes Batch API – 240 Claude Opus 5.5 (zkouška), zbytek Claude Sonnet 5.5 – za celkem 8,47 USD (původní de/en/it/golf 4,91 USD, nové fr/es/ru 3,56 USD).

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
- Odpověď je vynucená jako JSON podle schématu; věty, které neprojdou kontrolou kvality, se odešlou při dalším spuštění. Kontrola odmítne mimo jiné větu, která opisuje celý řádek slovníku; samotná pomlčka „—“ ve větě nevadí (ruština ji běžně píše).
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
| text | `intro.txt` | každý neprázdný řádek = jedna věta, písmo se zmenší, aby se vešlo |
| fotka | `intro/*.jpg`, `*.png`, `*.webp` | použije se **nejnovější** soubor; ořízne se na 16 : 9 (střed) |
| hudba | `intro/*.ogg`, `*.mp3`, `*.opus`, `*.flac`, `*.wav`, `*.m4a` | nejnovější soubor; hraje se max. 60 s, kratší skladba nevadí |

Stačí soubor přidat nebo přepsat. Při každém spuštění s `--intro` skript spočítá otisk (sha256) textu, fotky, seznamu vlajek a `intro-obrazek.py` a porovná ho s `intro/.vygenerovano/otisk`. Když se něco změnilo, složí nový obrázek `intro/.vygenerovano/intro.jpg`: nahoře vlajky všech jazyků (Noto Color Emoji), dole text z `intro.txt`, pod obojím tmavý přechod kvůli čitelnosti. Beze změny se nic negeneruje (kontrola trvá pár ms).

| Proměnná | Význam | Výchozí |
|---|---|---|
| `SLOVICKA_INTRO_DELKA` | délka intra v sekundách | `60` |
| `SLOVICKA_INTRO_PAUZA` | pauza před procvičováním | `5` |
| `SLOVICKA_INTRO_SIRKA` | šířka okna s obrázkem v px (výška 16 : 9) | `1280` |

Obrázek ukazuje `slovicka-view.py` jako dialog nad kartou (příkaz `INTRO`), hudba hraje přes `mpv`. Dialog s rodičovským oknem otevře každý kompozitor jako plovoucí – i dlaždicové (niri, sway, Hyprland) – bez jakýchkoli pravidel v konfiguraci. Bez okna (terminálový režim) hraje jen hudba.

**Výchozí obsah:** fotka *Rainier Meadow (July 2005)*, autor Jancarhart, volné dílo (Wikimedia Commons); hudba W. A. Mozart – *Malá noční hudba* (Serenáda G dur, K. 525), 1. věta Allegro, prvních 60 s nahrávky Musopen, volné dílo (Wikimedia Commons).

## Jiná prostředí (Wayland, X11)

Všechna okna jsou GTK4, takže by měla fungovat v libovolném Wayland kompozitoru (GNOME, KDE, niri, sway, Hyprland…) i na X11. Nic není vázané na niri. **Otestováno je zatím jen niri; GNOME, KDE, Hyprland, sway a X11 netestovány.**

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
- **Okno:** po výběru spustí skript sám sebe v `slovicka-view.py` (přes `setsid` a `uv run --script`, odpojeně od terminálu), viz [Průhledné okno](#průhledné-okno). Bez grafické relace nebo `uv` běží přímo v terminálu.
- **Terminálový režim:** kartu skládá `_vypis_kartu` podle skutečné velikosti terminálu: věty zalomí (`fold -s`), prázdné řádky vloží jen když je místo a v krajním případě zkrátí frázi (`…`). Titulek s vlajkami a pořadím tak nikdy neodroluje. Nápovědy kláves v terminálu jsou proto zkrácené (`[x] chyba`, `[⏎] znám`), aby se vešly na jeden řádek.
- **Ovládání (oba režimy):** čtení běží na pozadí a skript mezitím čte klávesy (`read -t`). Mezera pošle čtení `SIGSTOP` / `SIGCONT` (zastaví `piper`, `ffmpeg` i `mpv` uprostřed slova), `z` ho ukončí (`SIGTERM`) a slovíčko začne znovu. Čekání mezi slovíčky měří čas přes `$EPOCHREALTIME`.
- **TTS:** cizí jazyky Piper (program: `SLOVICKA_PIPER`, jinak `~/.local/share/uv/tools/piper-tts/bin/piper`, `~/.local/bin/piper`, nebo `piper` z `PATH`; hlasy: `SLOVICKA_PIPER_MODELY`, jinak `~/.local/share/piper`, vzorkovací frekvence se čte z `<model>.onnx.json`; hlasy viz [Slovníky](#slovníky)), čeština `edge-tts` (potřebuje internet), záložně `espeak-ng`. `mpv` běží s `--no-input-terminal`, aby nebral klávesy.
- **Úklid:** při ukončení (`q`, Ctrl+C, zavření okna, chyba) se zastaví čtení, zavře okno a smaže rozpracovaný mp3 v `/tmp`.

## Závislosti

- Intro: `uv` (Pillow si stáhne sám), `mpv`, `fontconfig` (`fc-match`), font Noto Color Emoji (`noto-fonts-emoji`, Debian/Ubuntu `fonts-noto-color-emoji`) pro vlajky a Noto Sans nebo DejaVu Sans.
- Okna (karta, nabídka, intro): `uv`, `gtk4`, `pango`, `gobject-introspection`, `cairo` a překladač (`gcc`, `meson`, `pkgconf`) pro sestavení PyGObject; libovolný Wayland kompozitor nebo X11.
- Skripty: `bash` 5+, `notify-send`, volitelně `rofi` / `fuzzel` / `wofi` / `zenity` (nabídka bez `uv`), `setsid`, `mpv`, `ffmpeg`, `piper-tts` (`uv tool install piper-tts`), `edge-tts`, volitelně `espeak-ng`.
- Generování frází: `uv` a přístup ke Claude API, nebo `python3` a llama.cpp server s gpt-oss-20b.

## Studijní materiál

`rozbor-skriptu.html` – výklad skriptů pro učení bashe ve třech částech: původní verze s technikami a cvičeními, opravy slabých míst (kód před/po) a rozšíření o fráze, ovládání klávesami a generátory frází. Otevři `xdg-open rozbor-skriptu.html`, online verze: https://claude.ai/artifact/NrzGvG6r9z5a5sfphknAXR

## Git

Veřejný repozitář: https://github.com/navik61/jazyky (větev `master`). Uložení změn:

```sh
git add -A && git commit -m "popis změny" && git push
```

Aliasy jsou mimo projekt, v `~/dotfiles`. Pravidla oken pro niri nejsou potřeba.

## Řešení problémů

- **Fráze se nezobrazuje** – zkontroluj, že je slovíčko v `fraze/<slovník>.tsv` (`grep -F 'slovo — ' fraze/*.tsv`); po změně slovníku spusť generátor.
- **Klávesy nereagují** – okno musí mít fokus; klávesy se čtou jen v okně se slovíčky, ne v původním terminálu.
- **Fráze je zkrácená (`…`) nebo chybí titulek** – v terminálovém režimu se obsah nevejde; zvětši terminál.
- **Ticho místo hlasu** – chybí Piper, jeho hlas nebo `edge-tts` (čeština potřebuje internet). Piper a hlasy jde nasměrovat proměnnými `SLOVICKA_PIPER` a `SLOVICKA_PIPER_MODELY`; bez Piperu se použije `espeak-ng`.
- **Okno se otevře na pozadí (GNOME, KDE)** – okno dostane fokus jen s aktivačním tokenem. Ze spouštěče aplikací (rofi, fuzzel, GNOME) ho skript předává dál, při spuštění z terminálu žádný token není a GNOME ukáže jen hlášku „… je připraveno“.
- **„Chybí …/spolecne.sh“** – `spolecne.sh` musí ležet vedle skriptů.
- **Generátor Claude: „Přihlášení neplatí nebo vypršelo“** – `ant auth login`, pak spusť znovu (dávka mezitím běží dál).
- **Generátor lokální: `Connection refused`** – neběží server: `systemctl --user start llama-gpt-oss.service`.
- **BT reproduktor pořád uřízne začátek slova** – zvyš `SLOVICKA_SUM_UROVEN` (např. `0.01`). Některé reproduktory se uspí, i když jim chodí jen velmi tichý signál.
- **Průhledné okno se neotevře** – spusť ručně `./slovicka-view.py --rezim znaky -- ./slovicka-pasivni.sh de --orig` a podívej se na chyby. Když se PyGObject nesestaví, chybí systémové knihovny (`gobject-introspection`, `cairo`) nebo překladač; bez `uv` skript tiše běží v terminálu.
- **Intro se nezmění po úpravě** – mění se jen nejnovější fotka/hudba v `intro/`; po `cp -p` si soubor může ponechat staré datum (`touch soubor`). Vynutit nové složení: `rm -r intro/.vygenerovano`.
- **Místo vlajek prázdná místa** – chybí `noto-fonts-emoji`.
- **`jaz` po změně aliasu nefunguje** – `source ~/.zshrc` nebo nový terminál.
