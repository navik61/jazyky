*Projekt Jazyky · bash 5 · Python 3*

# Rozbor skriptů Slovíčka

Výklad skriptů `slovicka-interaktivni.sh` a `slovicka-pasivni.sh`: co který kus
dělá, proč je napsaný právě tak a jaké bashové techniky v něm jsou. Na konci
najdeš slabá místa a cvičení s řešením.

> **Jak číst tento materiál:** **Část 1** (kapitoly 1–15) popisuje původní verzi
> skriptů a čísla řádků odkazují na ni. Cvičení si zkus vyřešit sám. **Část 2**
> (16–27) ukazuje, jak se opravila slabá místa, a obsahuje řešení cvičení z
> části 1. **Část 3** (28–41) popisuje vzorové fráze, ovládání klávesami (pauza,
> opakování, označení chybné fráze) a generátory frází v Pythonu. **Část 4**
> (42–51) popisuje okno v GTK místo kitty, `uv`, společný spouštěč, intro,
> play/pauzu v interaktivním režimu, nabídku a fokus v libovolném Wayland
> prostředí. **Část 5** (52–60) popisuje současnou verzi: učení mezi libovolnými
> sedmi jazyky, slovník pojmů a rozhraní v sedmi jazycích.
>
> Části 1–3 zachycují starší stav skriptů (okno kitty, `niri msg`, rofi) –
> techniky v nich platí dál, jen kód dnes vypadá jinak. Části 1–4 navíc počítají
> s češtinou jako jediným mateřským jazykem a se slovníky `cizí — česky`.
> Aktuální podobu najdeš v části 5 a přímo v souborech.

Čísla řádků odkazují na `slovicka-interaktivni.sh`, pokud není uvedeno jinak.
Ukázky jsou zkopírované ze skutečných souborů. Každou techniku si můžeš hned
vyzkoušet v terminálu.

## 1. Celkový tok

Interaktivní skript pracuje ve dvou rolích. Nejdřív běží jako **spouštěč** v
terminálu nebo z rofi: zjistí jazyk a pořadí. Pak spustí **sám sebe** v novém
okně kitty, kde už probíhá samotné procvičování. Kterou roli právě hraje, pozná
podle proměnné prostředí `SLOVICKA_V_OKNE`.

1.  **Spouštěč** (`V_OKNE=0`): přečte argumenty. Když chybí jazyk nebo pořadí,
    zeptá se, v terminálu číslem, bez terminálu přes rofi.
2.  Ověří, že slovník existuje, a zavolá `_spust_v_okne`: `SLOVICKA_V_OKNE=1
    setsid -f kitty … "$SKRIPT" en --swap`.
3.  Spouštěč posune okno na střed (`niri msg`), zruší svůj `trap EXIT` a skončí.
    Terminál je volný.
4.  **Skript v okně** (`V_OKNE=1`): má argumenty, takže se už na nic neptá.
    Načte 30 náhodných řádků a spustí `_kolo`.
5.  `_kolo` zobrazí každé slovíčko, nechá ho přečíst (`_tts_reci`) a čeká na
    Enter, `n` nebo `q`. Neznámá slovíčka sbírá a nabídne je zopakovat
    rekurzivním voláním.

Pasivní skript je jednodušší: běží celý v původním procesu a okno kitty používá
jen jako **displej**. Do souboru zapíše text a smyčka v okně ho vykreslí
(kapitola [11](#11-okno-pasivního-skriptu)).

## 2. Záhlaví a konfigurace

*slovicka-interaktivni.sh · 1–17*

```bash
#!/usr/bin/env bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)

readonly SKRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
readonly CESTA_SLOVNIKU="$(dirname "$SKRIPT")"
readonly V_OKNE="${SLOVICKA_V_OKNE:-0}"
```

### Shebang `#!/usr/bin/env bash`

Říká jádru, čím má soubor spustit. `env` najde `bash` v `PATH`, takže zápis
funguje i tam, kde bash neleží v `/bin`. Skript používá vlastnosti bashe (`[[
]]`, `declare -A`, `${x,,}`), takže s `sh` by nefungoval.

### `export XDG_RUNTIME_DIR`

V této složce leží sockety PipeWire a Waylandu. V grafické relaci je proměnná
nastavená vždy, ale při spuštění z cronu nebo systemd timeru chybět může. Pak by
`mpv` nenašel zvukový server. `$(id -u)` je **substituce příkazu**: bash příkaz
spustí a jeho výstup (tvoje UID, např. 1000) vloží do textu.

### `readlink -f "${BASH_SOURCE[0]}"`

`BASH_SOURCE[0]` je cesta, kterou byl skript zavolán. Z rofi je to
`~/.local/bin/slovicka-interaktivni`, tedy symlink. `readlink -f` symlink
rozbalí na skutečnou cestu `~/Projects/Jazyky/slovicka-interaktivni.sh` a
`dirname` z ní vezme složku. Proto skript najde slovníky, ať ho spustíš
odkudkoli.

### `readonly` a `${PROMENNA:-vychozi}`

`readonly` zakáže pozdější přepsání, takže chráníš konstanty před překlepem v
kódu. `${SLOVICKA_V_OKNE:-0}` znamená „hodnota proměnné, a pokud je prázdná nebo
neexistuje, tak `0`“.

> **Shellcheck SC2155:** `readonly X="$(prikaz)"` skryje chybový návratový kód
> příkazu, protože výsledkem je kód `readonly`, a ten je vždy 0. Tady to nevadí.
> V kódu, kde na chybě záleží, se píše `X=$(prikaz) || exit 1; readonly X`.

## 3. Asociativní pole

*slovicka-interaktivni.sh · 19–61*

```bash
declare -A SOUBORY=(
    [de]="$CESTA_SLOVNIKU/nemcina_slova.txt"
    [en]="$CESTA_SLOVNIKU/anglictina_slova.txt"
    …
)
declare -A TTS_JAZYK=( [de_golf]="de" [en_golf]="en" … )
```

`declare -A` vytvoří **asociativní pole**, tedy slovník s textovými klíči (bash
4+). Klíč jazyka (`en`, `de_golf`) se pak používá všude: `${SOUBORY[$jazyk]}` je
soubor, `${VLAJKY[$jazyk]}` vlajka a `${TTS_JAZYK[$jazyk]}` převede `en_golf` na
`en`, aby golfový slovník použil stejný hlas.

Výhoda: nový jazyk přidáš doplněním řádku do polí, nemusíš psát další `if`. Bez
`declare -A` by bash pole bral jako číselné a `[de]` by vyhodnotil jako index 0.

| Zápis | Výsledek |
|----|----|
| `${SOUBORY[en]}` | hodnota pro klíč `en` |
| `${!SOUBORY[@]}` | všechny klíče |
| `${#SOUBORY[@]}` | počet položek (6) |
| `${TTS_JAZYK[$j]:-$j}` | hodnota, nebo `$j`, když klíč chybí (řádek 103, pro `cs`) |

## 4. Funkce a návratové hodnoty

Bashová funkce neumí vrátit text přes `return`, ten vrací jen číslo 0–255
(stavový kód). Text se proto **vypíše na stdout** a volající ho zachytí přes `$(
)`:

*slovicka-interaktivni.sh · 303–318, 345–348*

```bash
_vyber_jazyk() {
    local volba
    volba=$(_vyber "Vyber jazyk" "🇩🇪 Němčina" "🇬🇧 Angličtina" …)
    case "$volba" in
        1) echo "de" ;;
        …
        "") exit 0 ;;   # zrušeno (Esc v rofi)
        *) _chyba "Neplatná volba: $volba" ;;
    esac
}

jazyk=$(_vyber_jazyk) || exit $?
[[ -z "$jazyk" ]] && exit 0
```

### Chyták: `exit` uvnitř `$( )`

`$( )` spouští kód v **subshellu**, tedy v kopii procesu. `exit` v něm ukončí
jen tu kopii, ne celý skript. Proto řádek 346 pokračuje `|| exit $?`: přiřazení
`jazyk=$(…)` převezme stavový kód subshellu. Když `_chyba` skončí s kódem 1,
skončí s ním i hlavní skript.

*vyzkoušej v terminálu · ověřeno*

```bash
f(){ x=$(exit 3) || echo "sub status=$?"; }; f
sub status=3
```

Esc v rofi vede na `exit 0`, tedy úspěch bez výstupu. Proto je za ním ještě
kontrola prázdné hodnoty `[[ -z "$jazyk" ]] && exit 0`.

### Proč `_vyber` píše nabídku na stderr

*slovicka-interaktivni.sh · 282–294*

```bash
_vyber() {
    local vyzva="$1"; shift
    if [[ -t 0 ]]; then
        echo -e "\n\e[1;34m$vyzva\e[0m" >&2
        local n=1 polozka
        for polozka in "$@"; do echo "  $n) $polozka" >&2; (( n++ )); done
        echo -n "Volba [1-$#, Enter=1]: " >&2
        local volba; read -r volba
        echo "${volba:-1}"            # jediné, co jde na stdout
    else
        printf '%s\n' "$@" | rofi -dmenu -i -no-custom -format d -p "$vyzva"
    fi
}
```

Vše, co funkce vypíše na stdout, skončí v proměnné volajícího. Kdyby nabídka šla
na stdout, uživatel by ji neviděl a v proměnné `volba` by byl celý text menu.
`>&2` pošle řádek na stderr, který `$( )` nezachytává, takže se objeví v
terminálu.

- `[[ -t 0 ]]`: je standardní vstup (deskriptor 0) terminál? Z rofi ne, proto se
  použije `rofi -dmenu`.
- `shift` zahodí první argument (výzvu), v `"$@"` pak zbudou jen položky. `$#`
  je jejich počet.
- `local` omezí platnost proměnné na funkci. Bez něj by `volba` přepsala
  stejnojmennou proměnnou jinde.
- `rofi -format d` vrátí pořadové číslo položky od 1, `-no-custom` nedovolí
  napsat vlastní text, `-i` hledá bez ohledu na velikost písmen.

## 5. Zpracování argumentů

Každý skript to dělá jinak a oba způsoby stojí za pochopení.

### Interaktivní: `for` + `case`

*slovicka-interaktivni.sh · 335–342*

```bash
for arg in "$@"; do
    case "$arg" in
        de|en|it|de_golf|en_golf|it_golf) jazyk="$arg" ;;
        --swap|-s) swap="1" ;;
        -h|--help) _pouziti ;;
        *) echo "Neznámý argument: $arg"; _pouziti ;;
    esac
done
```

Stačí to, protože žádná volba nemá vlastní hodnotu. `"$@"` v uvozovkách zachová
každý argument jako jeden celek, i když obsahuje mezery. `|` v `case` znamená
„nebo“, `*)` zachytí všechno ostatní.

### Pasivní: `while` s indexem

*slovicka-pasivni.sh · main()*

```bash
local i=0
local args=("$@")
while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
        --pocet|-n) (( i++ )); pocet="${args[$i]}" ;;
        --pauza|-p) (( i++ )); pauza="${args[$i]}" ;;
        …
    esac
    (( i++ ))
done
```

`--pocet 50` má hodnotu v **dalším** argumentu. `for` neumí položku přeskočit,
proto se argumenty zkopírují do pole a čte se je podle indexu: `(( i++ ))`
uvnitř větve posune index na hodnotu. Běžnější alternativa je `while (( $# ));
do … shift; done`, kde `shift` odebírá argumenty zepředu.

### Kontrola hodnot regulárním výrazem

*slovicka-pasivni.sh · main()*

```bash
if ! [[ "$pocet" =~ ^[1-9][0-9]*$ ]]; then …
if ! [[ "$pauza" =~ ^[0-9]+([.][0-9]+)?$ ]]; then …
```

`=~` porovná text s rozšířeným regulárním výrazem. Výraz se **nepíše do
uvozovek**, jinak by ho bash bral jako obyčejný text. První výraz povolí kladné
celé číslo bez nuly na začátku, druhý číslo s volitelnou desetinnou částí
(`2.5`). GNU `sleep` desetinná čísla umí.

> ⚠️ **Chyták `(( i++ ))`:** Aritmetický příkaz vrací stavový kód 1, když je
> výsledek výrazu 0. `i++` vrací *starou* hodnotu, takže při `i=0` „selže“. Bez
> `set -e` to nevadí, ale s `set -e` by skript tiše skončil hned na prvním
> argumentu. Bezpečnější zápis je `(( ++i ))` nebo `i=$((i+1))`.

## 6. Práce s řetězci

Řádek slovníku vypadá takto: `Haus — dům`. Rozdělení na originál a překlad
zvládne bash sám, bez `cut` nebo `awk`:

*slovicka-interaktivni.sh · 233–234*

```bash
orig="${radek%% — *}"    # odřízni od konce nejdelší shodu " — *"
cz="${radek#* — }"       # odřízni od začátku nejkratší shodu "* — "
```

| Operátor | Odřízne | Příklad |
|----|----|----|
| `${x#vzor}` | nejkratší shodu ze začátku | `${radek#* — }` |
| `${x##vzor}` | nejdelší shodu ze začátku | `${cesta##*/}` = název souboru |
| `${x%vzor}` | nejkratší shodu z konce | `${soubor%.txt}` |
| `${x%%vzor}` | nejdelší shodu z konce | `${radek%% — *}` |
| `${x,,}` / `${x^^}` | převod na malá / velká písmena | `${odpoved,,}`: `N` i `n` fungují |
| `${x/a/b}` | nahradí první výskyt (`//` všechny) | — |

Vzory jsou **glob** (`*`, `?`, `[…]`), ne regulární výrazy. Když má řádek dva
oddělovače, výsledek vypadá takto:

*vyzkoušej · ověřeno*

```bash
r="Haus — dům — budova"; echo "[${r%% — *}] [${r#* — }]"
[Haus] [dům — budova]
```

Originál je vždy první část, překlad je všechno za prvním `—`. Přesně to chceš.

> ⚠️ **Chyták `${cast## }`:** Řádky 113–114 mají ořezat mezery. Vzor ` ` (jedna
> mezera) ale odpovídá vždy jen jedné mezeře, takže „nejdelší shoda“ je pořád
> jedna mezera. `" ahoj "` se ořízne jen na `" ahoj "` (ověřeno). Při čtení to
> nevadí, Piper mezery ignoruje. Správné ořezání najdeš ve [cvičení
> 1](#14-cvičení-s-řešením).

## 7. Roury a přesměrování

| Zápis | Význam | Kde ve skriptu |
|----|----|----|
| `2>/dev/null` | zahodí chybový výstup | všude u `mpv`, `ffmpeg`, `niri` |
| `&>/dev/null` | zahodí stdout i stderr | `command -v kitty &>/dev/null` |
| `>&2` | pošle stdout na stderr | `_vyber`, `_chyba` |
| `</dev/null` | prázdný vstup | `setsid -f kitty … </dev/null` |
| `a | b` | stdout `a` jde na stdin `b` | Piper → ffmpeg → mpv |
| `< <(prikaz)` | výstup příkazu jako vstupní soubor (process substitution) | `mapfile`, `while read` |
| `a && b` / `a || b` | `b` jen při úspěchu / neúspěchu `a` | `edge-tts … && mpv …`, `niri … || true` |

### Proč `while read … done < <(…)` a ne roura

*slovicka-interaktivni.sh · 112, 155–156*

```bash
while IFS= read -r cast; do
    …
    prvni=0
done < <(echo "$text" | tr '/' '
')
```

Kdyby se psalo `echo … | while read …`, smyčka by běžela v subshellu a změny
proměnných (tady `prvni=0`) by po skončení smyčky zmizely. Process substitution
`<(…)` nechá smyčku v hlavním procesu. V této funkci by to náhodou nevadilo,
protože se `prvni` používá jen uvnitř smyčky. Je to ale správný návyk.

- `IFS=` vypne dělení podle mezer, takže `read` nechá mezery na okrajích.
- `read -r` nebere zpětné lomítko jako escape znak. Piš ho vždy.
- `tr '/' '⏎'` má v kódu doslovný nový řádek uvnitř uvozovek. Funguje to, ale
  čitelnější je `tr '/' '\n'`, `tr` sekvenci `\n` zná.

### `mapfile`: soubor do pole

*slovicka-interaktivni.sh · 369*

```bash
mapfile -t slovicka < <(grep ' — ' "$soubor" | shuf | head -n "$POCET_KOLO")
```

Postup zleva: `grep ' — '` pustí dál jen platné řádky (zahodí prázdné), `shuf`
je náhodně zamíchá, `head -n 30` vezme prvních 30 a `mapfile -t` z nich udělá
pole (`-t` odstraní znak konce řádku). Výsledek je 30 náhodných slovíček bez
opakování.

## 8. Řetězec TTS

Funkce `_tts_reci` rozdělí text podle `/` (např. `dům / budova`) a každou část
přečte zvlášť s půlsekundovou pauzou. Pro čtení má tři možnosti:

| Situace | Nástroj | Poznámka |
|----|----|----|
| čeština | `edge-tts` → mp3 → `mpv` | přirozený hlas, potřebuje internet |
| cizí jazyk, model existuje | `piper` → `ffmpeg` → `mpv` | offline, rychlý |
| model chybí | `espeak-ng` | robotický, ale funguje vždy |

*slovicka-interaktivni.sh · 108–109, 146–153*

```bash
vzorkovani=$(grep -o '"sample_rate": *[0-9]*' "$model.json" 2>/dev/null | grep -o '[0-9]*$')
vzorkovani=${vzorkovani:-22050}

echo "$cast" | "$PIPER" --model "$model" --length_scale "$TTS_SPEED" --output-raw \
    | ffmpeg -f s16le -ar "$vzorkovani" -ac 1 -i pipe: -ar 48000 -ac 2 -f wav pipe:1 \
    | mpv --really-quiet --no-video -
```

Piper s `--output-raw` vydává **holá audio data** bez hlavičky: 16bitová čísla
se znaménkem, little-endian (`s16le`), mono. Kdo je čte, musí znát vzorkovací
frekvenci, protože v datech nikde uvedená není. `ffmpeg` je převede na WAV 48
kHz stereo a `mpv` ho přehraje ze stdin (`-`).

> **Opravená chyba:** Dřív bylo ve skriptu napevno `-ar 22050`. Italský model
> `riccardo-x_low` ale má 16 000 Hz, takže se přehrával 22050 / 16000 = 1,38×
> rychleji a vyšším hlasem. Teď se frekvence čte z `.onnx.json` vedle modelu.
> Poučení: holá data nenesou informaci o formátu, tu musíš dodat sám.

`--length_scale 0.85` řeč mírně zrychlí. Hodnota pod 1 je rychlejší, nad 1
pomalejší. `mktemp /tmp/tts_XXXXXX.mp3` vytvoří soubor s unikátním názvem, takže
dva běžící skripty si soubory nepřepíšou.

## 9. Kolo a rekurze

*slovicka-interaktivni.sh · 219–271 (zkráceno)*

```bash
_kolo() {
    local jazyk="$1" swap="$2"
    local -a pole_slov=("${!3}")
    local -a neznama=()
    for radek in "${pole_slov[@]}"; do
        …
        read -r odpoved
        case "${odpoved,,}" in
            q) exit 0 ;;
            n|ne|x) neznama+=("$radek") ;;
        esac
    done
    if [[ ${#neznama[@]} -gt 0 ]]; then
        …
        mapfile -t zamichana < <(printf '%s\n' "${neznama[@]}" | shuf)
        _kolo "$jazyk" "$swap" zamichana[@]
    fi
}
```

### Předání pole funkci: `${!3}`

Bash neumí předat pole jako jeden argument. Skript proto předává **jméno** pole
jako text `"zamichana[@]"` a funkce si ho rozbalí **nepřímou expanzí** `${!3}`:
„vezmi hodnotu třetího argumentu a použij ji jako jméno proměnné“. Funguje to,
protože bash má dynamický rozsah platnosti a funkce vidí lokální proměnné
volajícího.

Shellcheck proto hlásí `SC2034 zamichana appears unused`: proměnnou nevidí
použitou, protože se na ni odkazuje jen textem. Modernější a čitelnější je
`local -n` (nameref), viz [cvičení 2](#14-cvičení-s-řešením).

### Rekurze

Opakování neznámých slovíček je nové volání `_kolo` uvnitř `_kolo`. Každé kolo
má vlastní `local` proměnné, takže se kola navzájem nepřepisují. Hloubka rekurze
odpovídá počtu opakování, což jsou jednotky, takže to nevadí.

- `arr+=("x")` přidá prvek na konec pole. Závorky jsou nutné, `arr+="x"` by text
  připojil k prvnímu prvku.
- `${#arr[@]}` je počet prvků, `$(( a - b ))` aritmetika.
- `printf '%s\n' "${arr[@]}"` vypíše každý prvek na samostatný řádek. Formát se
  opakuje pro každý argument.

## 10. Procesy, okna a signály

*slovicka-interaktivni.sh · 161–175*

```bash
_spust_v_okne() {
    local -a argumenty=("$@")
    _zjisti_pozici_okna
    SLOVICKA_V_OKNE=1 setsid -f kitty \
        --class kitty-float --title "kitty-float-slovicka" \
        --override font_size=16 … \
        "$SKRIPT" "${argumenty[@]}" </dev/null &>/dev/null
    sleep 0.8
    niri msg action move-floating-window --x "$OKNO_X" --y "$OKNO_Y" 2>/dev/null || true
}
```

- **`PROM=hodnota prikaz`** nastaví proměnnou prostředí jen pro tento příkaz a
  jeho potomky. Dostane ji kitty a od něj skript v okně. Tak se skript v okně
  dozví, že má hrát roli „okna“.
- **`setsid -f`** spustí kitty v nové **relaci** (session) a hned se vrátí.
  Proces pak nepatří k terminálu, takže zavření terminálu (signál SIGHUP) ho
  neukončí.
- **`</dev/null &>/dev/null`** odpojí i vstup a výstup od terminálu.
- **`--class kitty-float`** nastaví app-id, podle kterého pravidlo v
  `niri/config.kdl` udělá okno plovoucí, 700 px široké a bez rámečku.
- **`|| true`** zajistí, že selhání `niri` (např. v jiném kompozitoru) skript
  nezastaví.

### Signály a `trap`

*slovicka-interaktivni.sh · 273–278, 363–365*

```bash
trap _na_preruseni INT TERM     # Ctrl+C nebo kill
trap _okno_zavrit EXIT          # při každém ukončení skriptu
…
_spust_v_okne "${argumenty[@]}"
trap - EXIT                     # spouštěč nesmí zavřít okno, které právě otevřel
exit 0
```

`trap` zaregistruje funkci, která se spustí při signálu. `EXIT` je zvláštní
pseudo-signál, který bash vyvolá při každém konci skriptu: normálním, po `exit`
i po chybě. Hodí se na úklid. `trap - EXIT` úklid zase zruší. Bez něj by
spouštěč při skončení zavolal `pkill` a okno, které před chvílí otevřel, by hned
zavřel.

`_okno_zavrit` uvnitř okna záměrně nic nedělá (`[[ "$V_OKNE" == "1" ]] && return
0`). Okno se zavře samo, když jeho skript skončí.

### `pgrep -f` / `pkill -f`

`-f` hledá v **celém příkazovém řádku** procesu, ne jen v názvu programu.
Titulek `kitty-float-slovicka` je v argumentech kitty, takže ho najde. Pozor:
zasáhl by i jiný proces, který má tento text v argumentech, třeba editor
otevřený se souborem toho jména.

### Pozice okna: `awk` a aritmetika

*slovicka-interaktivni.sh · 74–91*

```bash
vystup=$(niri msg focused-output 2>/dev/null)
log_w=$(echo "$vystup" | awk '/Logical size:/ {split($3,a,"x"); print a[1]}')
…
OKNO_X=$(( (log_w - OKNO_SIRKA) / 2 ))
```

`awk '/vzor/ {akce}'` provede akci jen na řádcích, které vzoru odpovídají. Řádek
`Logical size: 1920x1080` má pole `$1`=Logical, `$2`=size:, `$3`=1920x1080.
`split($3,a,"x")` ho rozdělí podle `x`. `$(( ))` počítá jen s celými čísly.

## 11. Okno pasivního skriptu

Pasivní skript nečeká na klávesy, takže okno slouží jen k zobrazení. Skript
zapisuje text do souboru a v okně běží malá smyčka, která ho vykresluje:

*slovicka-pasivni.sh · \_notifikace()*

```bash
{ echo "$titulek"; echo "$zprava"; } > "$NOTIF_SOUBOR.tmp" \
    && mv -f "$NOTIF_SOUBOR.tmp" "$NOTIF_SOUBOR"
…
kitty … sh -c 'printf "\033[?25l"
    posledni=""
    while true; do
        obsah=$(cat "$1" 2>/dev/null)
        if [ -n "$obsah" ] && [ "$obsah" != "$posledni" ]; then
            printf "\033[?2026h\033[H\033[2J%s\n\033[?2026l" "$obsah"
            posledni=$obsah
        fi
        sleep 0.2
    done' sh "$NOTIF_SOUBOR" &
```

### Proč vlajka dřív blikala

Původní smyčka každých 0,2 s smazala obrazovku a vypsala text znovu, tedy 5× za
sekundu. Barevné emoji vlajek se vykreslují pomaleji než text, takže na chvilku
zmizely. Oprava má tři části:

1.  **Kreslit jen při změně**: smyčka si pamatuje `posledni` a obrazovku
    překreslí, jen když se obsah liší.
2.  **Atomický zápis**: `mv` v rámci jednoho souborového systému je atomický.
    Čtenář vidí buď starý, nebo nový soubor, nikdy prázdný či rozepsaný. Přímé
    `> soubor` by soubor nejdřív vyprázdnilo.
3.  **Synchronizovaný výstup**: `\033[?2026h` … `\033[?2026l` řekne kitty
    „nevykresluj, dokud nedopíšu“. Smazání a nový text se tak zobrazí najednou.

### `sh -c '…' sh "$soubor"`

Argumenty za kódem v `sh -c` se číslují od `$0`. První (`sh`) je jen jméno
procesu, teprve druhý je `$1`. Cesta se tak předá jako argument a nevkládá se do
textu kódu. Kód je v jednoduchých uvozovkách, takže ho bash nerozbaluje a `$1` i
`$obsah` vyhodnotí až vnitřní `sh`.

### Ukončení zavřením okna

`_kontrola_okna` se volá po každém přečtení. Pokud okno bylo otevřené
(`OKNO_OTEVRENO=1`) a `pgrep` ho už nenajde, uživatel ho zavřel a skript skončí.
Při spuštění z rofi je to jediný způsob, jak ho zastavit, protože tam Ctrl+C
nemáš.

## 12. Barvy a výstup

Barvy dělají ANSI escape sekvence `\e[…m`. Skript používá tyto (ukázky kódu na
této stránce mají stejné barvy):

| Kód        | Barva         | Použití ve skriptu              |
|------------|---------------|---------------------------------|
| `\e[1;33m` | tučná žlutá   | slovíčko, které se právě čte    |
| `\e[0;37m` | světle šedá   | překlad                         |
| `\e[0;90m` | tmavě šedá    | titulek, nápověda kláves        |
| `\e[1;32m` | tučná zelená  | „Kolo dokončeno“, počet známých |
| `\e[1;31m` | tučná červená | chyby, počet neznámých          |
| `\e[1;34m` | tučná modrá   | výzvy v menu                    |
| `\e[0m`    | reset         | za každým barevným textem       |

Další užitečné sekvence: `\033[H` přesune kurzor nahoru vlevo, `\033[2J` smaže
obrazovku, `\033[?25l` skryje kurzor.

> **echo -e vs. printf:** `echo -e` zpracuje `\e`, `\n` a podobné sekvence, ale
> i v proměnných. Kdyby slovíčko obsahovalo `\t`, změnilo by se na tabulátor.
> `printf "\e[1;33m%s\e[0m\n" "$slovo"` escape sekvence zpracuje jen ve formátu,
> data v `%s` nechá beze změny. Pro data je proto `printf` bezpečnější a je i
> přenositelnější.

## 13. Slabá místa

Nic z toho není vážné. Jsou to ale dobré příklady k procvičení:

| Místo | Problém | Řešení |
|----|----|----|
| `${cast## }` (113) | ořízne jen jednu mezeru | cvičení 1 |
| `"${!3}"` (222) | nečitelné, shellcheck hlásí SC2034 | cvičení 2 (`local -n`) |
| `mktemp` (123) | po Ctrl+C během češtiny zůstane v `/tmp` soubor mp3 | cvičení 3 |
| `OKNO_VYSKA=180` (72) | pravidlo niri nastavuje výšku 250 px, takže okno není přesně na středu (o 35 px) | změnit na 250 |
| `log_x`, `log_y` (79–80) | vypočítané, ale nepoužité | smazat |
| dva skripty | asi 150 řádků je v obou stejných (pole, TTS, okno) | cvičení 5 (`source`) |
| `_pouziti` (94) | nápověda neuvádí golfové slovníky; `--help` končí kódem 1 | doplnit, `exit 0` |
| neznámá slovíčka | po skončení se zapomenou | cvičení 4 |

## 14. Cvičení s řešením

Každé cvičení zkoušej na **kopii** skriptu (`cp slovicka-interaktivni.sh
pokus.sh`). Po úpravě spusť `bash -n pokus.sh` (kontrola syntaxe) a `shellcheck
pokus.sh`.

<details><summary><b>1. Správné ořezání mezer</b></summary>

*procvičíš: expanze parametrů, třídy znaků*

Uprav řádky 113–114, aby ořízly všechny mezery a tabulátory na začátku i na
konci.

*řešení · čistý bash*

```bash
cast="${cast#"${cast%%[![:space:]]*}"}"   # zleva
cast="${cast%"${cast##*[![:space:]]}"}"   # zprava
```

Vnitřní `${cast%%[![:space:]]*}` najde úsek mezer na začátku (všechno před
prvním znakem, který není mezera). Vnější `#` ho pak odřízne. Jednodušší
alternativa s `shopt -s extglob`: `cast="${cast##+([[:space:]])}"`.

</details>

<details><summary><b>2. Předání pole přes nameref</b></summary>

*procvičíš: local -n, pole*

Nahraď `"${!3}"` a `slovicka[@]` čitelnější variantou.

*řešení · bash 4.3+*

```bash
_kolo() {
    local jazyk="$1" swap="$2"
    local -n _pole="$3"              # _pole je alias pro pole volajícího
    local -a pole_slov=("${_pole[@]}")
    …
    _kolo "$jazyk" "$swap" zamichana  # předává se jen jméno, bez [@]
}
_kolo "$jazyk" "$swap" slovicka
```

Jméno namerefu (`_pole`) se nesmí shodovat se jménem předávaného pole, jinak
vznikne kruhový odkaz. Proto podtržítko.

</details>

<details><summary><b>3. Úklid dočasného mp3</b></summary>

*procvičíš: trap, globální stav*

Zařiď, aby po Ctrl+C nezůstal v `/tmp` soubor `tts_*.mp3`.

*řešení*

```bash
TMP_MP3=""                        # globální, aby ho trap viděl
_uklid() { [[ -n "$TMP_MP3" ]] && rm -f "$TMP_MP3"; _okno_zavrit; }
trap _uklid EXIT

# v _tts_reci místo local tmp_mp3:
TMP_MP3=$(mktemp /tmp/tts_XXXXXX.mp3)
edge-tts … --write-media "$TMP_MP3" && mpv … "$TMP_MP3"
rm -f "$TMP_MP3"; TMP_MP3=""
```

Na skript v okně se pak vztahuje i `trap - EXIT` ve spouštěči. Ten mp3 nikdy
nevytváří, takže tam nevadí.

</details>

<details><summary><b>4. Ukládání neznámých slovíček</b></summary>

*procvičíš: zápis do souboru,sort -u, nová volba*

Na konci kola připiš neznámá slovíčka do `neznama_<jazyk>.txt` a přidej volbu
`--neznama`, která procvičí jen je.

*řešení*

```bash
# v _kolo po smyčce:
local soubor_n="$CESTA_SLOVNIKU/neznama_${jazyk}.txt"
if (( ${#neznama[@]} )); then
    { cat "$soubor_n" 2>/dev/null; printf '%s\n' "${neznama[@]}"; } \
        | sort -u > "$soubor_n.tmp" && mv -f "$soubor_n.tmp" "$soubor_n"
fi

# v main, ve for/case:
--neznama) jen_neznama=1 ;;
# před mapfile:
[[ "$jen_neznama" == 1 ]] && soubor="$CESTA_SLOVNIKU/neznama_${jazyk}.txt"
```

Pozor: spouštěč předává do okna jen jazyk a `--swap`. Musíš do `argumenty`
přidat i `--neznama`, jinak se volba v okně ztratí. To je dobrá kontrola, že
rozumíš kapitole 01. Bonus: slovíčko, které v kole označíš jako známé, ze
souboru odeber (`grep -vxF`).

</details>

<details><summary><b>5. Společná knihovna</b></summary>

*procvičíš: source, struktura projektu*

Přesuň pole `SOUBORY`, `NAZVY`, `VLAJKY`, `TTS_*` a funkce `_tts_reci`,
`_zjisti_pozici_okna`, `_vyber*`, `_chyba` do `spolecne.sh`.

*řešení · začátek obou skriptů*

```bash
readonly SKRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
readonly CESTA_SLOVNIKU="$(dirname "$SKRIPT")"
# shellcheck source=spolecne.sh
source "$CESTA_SLOVNIKU/spolecne.sh" || { echo "Chybí spolecne.sh" >&2; exit 1; }
```

`spolecne.sh` nepotřebuje shebang ani právo ke spuštění, protože se jen načítá.
`source` provede soubor v aktuálním shellu, takže jeho proměnné a funkce
zůstanou dostupné. Oprava chyby v TTS pak platí pro oba skripty najednou.

</details>

<details><summary><b>6. Bezpečnější režim: set -u</b></summary>

*procvičíš: ladění, nedefinované proměnné*

Přidej pod shebang `set -u` (chyba při použití nedefinované proměnné) a skript
spusť. Kde spadne a proč?

Spadne na `${SLOVICKA_V_OKNE:-0}`? Ne, `:-` výchozí hodnota se `set -u` nevadí.
Zkus ale `[[ -n "$WAYLAND_DISPLAY$DISPLAY" ]]` na řádku 360 v prostředí bez X11:
`DISPLAY` není definovaná, takže skript skončí chybou. Oprava:
`"${WAYLAND_DISPLAY:-}${DISPLAY:-}"`. Spouštěj skript s `bash -x pokus.sh en`,
uvidíš každý vykonaný příkaz.

</details>

## 15. Tahák

| Potřebuješ | Zápis |
|----|----|
| výchozí hodnotu | `${x:-vychozi}` |
| výstup příkazu do proměnné | `x=$(prikaz)` |
| vrátit text z funkce | `echo` uvnitř, `x=$(funkce)` venku |
| vypsat něco mimo zachycení | `echo … >&2` |
| soubor do pole | `mapfile -t pole < soubor` |
| číst po řádcích | `while IFS= read -r r; do …; done < soubor` |
| je stdin terminál? | `[[ -t 0 ]]` |
| existuje program? | `command -v prog &>/dev/null` |
| úklid při konci | `trap uklid EXIT` |
| odpojit proces od terminálu | `setsid -f prikaz </dev/null &>/dev/null` |
| atomicky přepsat soubor | `… > f.tmp && mv -f f.tmp f` |
| zkontrolovat syntaxi / ladit | `bash -n s.sh` / `bash -x s.sh` / `shellcheck s.sh` |

K dalšímu čtení: `man bash` (sekce *Parameter Expansion*, *Redirection*, *SHELL
BUILTIN COMMANDS*) a [BashGuide na
wooledge.org](https://mywiki.wooledge.org/BashGuide), nejlepší volně dostupný
průvodce bashem s důrazem na správné návyky.

*Část 2 · spolecne.sh · slovicka-\*.sh*

# Provedené úpravy

Jak se opravila slabá místa z kapitoly 13: ke každé změně kód před a po a
vysvětlení nových technik. Ukázky jsou ze skutečných souborů po úpravě.

## 16. Přehled změn

| Slabé místo | Oprava | Kde |
|----|----|----|
| zdvojený kód | nová knihovna načítaná přes `source` | `spolecne.sh` |
| `${cast## }` | ořezání všech bílých znaků | `_tts_reci` |
| `"${!3}"` | nameref `local -n` | `_kolo`, `_zapis_vysledky` |
| mp3 po Ctrl+C | globální `TMP_MP3` + `trap _uklid EXIT` | oba skripty |
| `OKNO_VYSKA=180` | 250, jako pravidlo v niri | `spolecne.sh` |
| `log_x`, `log_y` | odstraněno | `_zjisti_pozici_okna` |
| nápověda | jazyky ze seznamu, správné návratové kódy | `_pouziti` |
| neznámá slovíčka | ukládání, `--neznama`, položky v nabídce | `_neznama_*`, `_vyber_jazyk` |

Velikost: `spolecne.sh` 247 řádků, pasivní skript 211, interaktivní 246. Každý
skript teď obsahuje jen to, čím se od druhého liší.

## 17. Společná knihovna

Do `spolecne.sh` se přesunula pole (`SOUBORY`, `NAZVY`, `VLAJKY`, `TTS_*`),
konstanty okna a funkce `_tts_reci`, `_zjisti_pozici_okna`, `_vyber*`, `_chyba`
a nové `_je_jazyk`, `_seznam_jazyku` a `_neznama_*`. Začátek obou skriptů teď
vypadá takto:

*slovicka-interaktivni.sh · po úpravě*

```bash
# Bez grafické relace (cron, systemd) by mpv nenašel PipeWire
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
export XDG_RUNTIME_DIR

SKRIPT=$(readlink -f "${BASH_SOURCE[0]}")
readonly SKRIPT
CESTA_SLOVNIKU=$(dirname "$SKRIPT")
readonly CESTA_SLOVNIKU
# shellcheck source=spolecne.sh
source "$CESTA_SLOVNIKU/spolecne.sh" || { echo "Chybí $CESTA_SLOVNIKU/spolecne.sh" >&2; exit 1; }
```

- **`source`** (nebo `.`) provede soubor **v aktuálním shellu**. Proměnné a
  funkce z něj zůstanou dostupné, jako by byly napsané přímo ve skriptu.
  Spuštění `bash spolecne.sh` by naopak běželo v novém procesu a nic by
  nepředalo.
- **Pořadí je důležité**: knihovna v polích používá `$CESTA_SLOVNIKU`, takže ji
  skript musí nastavit *před* `source`. Knihovna to uvádí v hlavičce: „Očekává,
  že volající skript už nastavil CESTA_SLOVNIKU.“
- **Knihovna nemá shebang ani právo ke spuštění**. Místo shebangu má `#
  shellcheck shell=bash`, aby shellcheck věděl, jaký dialekt kontroluje.
- **`# shellcheck source=spolecne.sh`** řekne shellchecku, který soubor se
  načítá. S `shellcheck -x` ho pak zkontroluje spolu se skriptem.
- **`# shellcheck disable=SC2034`** na začátku knihovny potlačí hlášení
  „proměnná nepoužita“. Proměnné používají skripty, ne knihovna sama.

*před · SC2155*

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
readonly CESTA_SLOVNIKU="$(dirname …)"
```

*po · bez varování*

```bash
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
export XDG_RUNTIME_DIR
CESTA_SLOVNIKU=$(dirname "$SKRIPT")
readonly CESTA_SLOVNIKU
```

Přiřazení a `readonly`/`export` jsou zvlášť, takže chyba příkazu v `$( )` se
neztratí. `$UID` je vestavěná proměnná bashe, takže není potřeba spouštět `id`.
`:-` zajistí, že existující hodnota z grafické relace se nepřepíše.

## 18. Ořezání mezer

*před · jen 1 mezera*

```bash
cast="${cast## }"
cast="${cast%% }"
```

*po · spolecne.sh · \_tts_reci*

```bash
cast="${cast#"${cast%%[![:space:]]*}"}"
cast="${cast%"${cast##*[![:space:]]}"}"
```

Rozbor prvního řádku na příkladu `cast="␣␣ahoj␣"`:

1.  `[![:space:]]` je „jeden znak, který **není** bílý“ (`!` uvnitř závorek
    neguje). `[:space:]` zahrnuje mezeru, tabulátor i konec řádku.
2.  Vnitřní `${cast%%[![:space:]]*}` odřízne od konce nejdelší úsek, který
    začíná prvním nebílým znakem. Zbude jen úvodní `␣␣`.
3.  Vnější `${cast#"␣␣"}` odřízne přesně tento úsek ze začátku. Výsledek je
    `ahoj␣`.
4.  Druhý řádek dělá totéž zrcadlově: vnitřní `${cast##*[![:space:]]}` nechá jen
    koncové mezery a vnější `%` je odřízne.

> **Proč uvozovky uvnitř:** Vnitřní výraz je v uvozovkách (`"${cast%%…}"`), aby
> se jeho výsledek bral **doslova**, ne jako glob vzor. Kdyby text obsahoval `*`
> nebo `[`, bez uvozovek by se choval jako zástupný znak.

## 19. Nameref místo `${!3}`

*před · nepřímá expanze*

```bash
_kolo() {
    local -a pole_slov=("${!3}")
    …
    _kolo "$jazyk" "$swap" zamichana[@]
}
_kolo "$jazyk" "$swap" slovicka[@]
```

*po · slovicka-interaktivni.sh*

```bash
_kolo() {
    local jazyk="$1" swap="$2" kolo="${4:-1}"
    local -n _vstup="$3"
    local -a pole_slov=("${_vstup[@]}")
    …
    _kolo "$jazyk" "$swap" zamichana $(( kolo + 1 ))
}
_kolo "$jazyk" "$swap" slovicka
```

`local -n _vstup="$3"` vytvoří **odkaz** (nameref): každé použití `_vstup` se ve
skutečnosti týká proměnné, jejíž jméno je v `$3`. Volající předá čisté jméno
`slovicka` bez `[@]` a funkce s polem pracuje normálně: `${_vstup[@]}`,
`${#_vstup[@]}`, a mohla by do něj i zapisovat.

- **Podtržítko ve jménu**: kdyby se nameref jmenoval stejně jako předávané pole
  (`local -n slovicka=slovicka`), vznikl by kruhový odkaz a bash ohlásí chybu.
  Prefix `_` kolizi prakticky vyloučí.
- **Rekurze**: vnitřní `_kolo` dostane jméno `zamichana`. To je `local` proměnná
  *volajícího* kola a díky dynamickému rozsahu ji vnitřní kolo vidí. Pole se
  hned zkopíruje do vlastního `pole_slov`, takže na dalším vnoření nezáleží.
- **Číslo kola** (`$4`, výchozí 1) je nové. Potřebuje ho ukládání neznámých
  slovíček (kapitola [23](#23-neznámá-slovíčka)).

Stejnou techniku používá nová funkce, která přijímá **dvě** pole:

*slovicka-interaktivni.sh · \_zapis_vysledky*

```bash
_zapis_vysledky() {
    local jazyk="$1" kolo="$2"
    local -n _nez="$3" _zn="$4"
    _neznama_pridej "$jazyk" "${_nez[@]}"
    if [[ "$JEN_NEZNAMA" == "1" && "$kolo" == "1" ]]; then
        _neznama_odeber "$jazyk" "${_zn[@]}"
    fi
}
_zapis_vysledky "$jazyk" "$kolo" neznama znama
```

Shellcheck nameref nesleduje a u `zamichana` hlásí SC2034. Řádek proto má
komentář `# shellcheck disable=SC2034 # předává se jménem (nameref)`. Direktiva
platí jen pro **následující příkaz**, proto stojí přímo nad `mapfile`.

## 20. Úklid dočasného mp3

*před · local*

```bash
local tmp_mp3
tmp_mp3=$(mktemp /tmp/tts_XXXXXX.mp3)
edge-tts … --write-media "$tmp_mp3" \
&& mpv … "$tmp_mp3"
rm -f "$tmp_mp3"
```

*po · spolecne.sh*

```bash
TMP_MP3=""          # globální
_uklid_tts() {
    [[ -n "$TMP_MP3" ]] && rm -f "$TMP_MP3"
    TMP_MP3=""
}
# v _tts_reci:
TMP_MP3=$(mktemp /tmp/tts_XXXXXX.mp3)
edge-tts … --write-media "$TMP_MP3" \
&& mpv … "$TMP_MP3"
_uklid_tts
```

Při Ctrl+C během přehrávání bash přeruší `mpv` a spustí `trap`. Ten ale běží
mimo funkci `_tts_reci` a její `local` proměnnou nevidí, takže soubor nemohl
smazat. Globální `TMP_MP3` vidí kdokoli. Po úklidu se vynuluje, takže druhé
volání nic nesmaže dvakrát.

*slovicka-interaktivni.sh · trap*

```bash
_uklid() {
    _uklid_tts
    _okno_zavrit
}
trap _na_preruseni INT TERM
trap _uklid EXIT
```

Řetězec je: Ctrl+C → `_na_preruseni` → `exit 0` → pseudo-signál EXIT → `_uklid`.
Úklid je tak na jednom místě a proběhne při každém způsobu ukončení.

## 21. Kontrola jazyka

*před · seznam 3×*

```bash
case "$arg" in
    de|en|it|de_golf|en_golf|it_golf)
        jazyk="$arg" ;;
```

*po · jeden seznam*

```python
readonly JAZYKY=(de en it de_golf en_golf it_golf)

_je_jazyk() {
    local j
    for j in "${JAZYKY[@]}"; do
        [[ "$1" == "$j" ]] && return 0
    done
    return 1
}
# v main:
*)  if _je_jazyk "$arg"; then jazyk="$arg"
    else echo "Neznámý argument: $arg" >&2; _pouziti 1 >&2; fi ;;
```

Seznam jazyků byl dřív napsaný na třech místech: ve dvou `case` a v nabídce. Teď
je jen v poli `JAZYKY`. Funkce vrací stavový kód (0 = ano), takže ji jde použít
přímo v `if`. Takhle se v bashi píšou „funkce vracející pravdu“.

> **Alternativa: `${SOUBORY[$arg]+x}`:** Test „existuje klíč?“ by fungoval taky:
> `[[ -n "${SOUBORY[$arg]+x}" ]]`. Výraz `${x+slovo}` dá `slovo`, když proměnná
> existuje, jinak nic. V bashi 5.3 se i argument `@` v proměnné bere jako
> obyčejný klíč (ověřeno: `k=@; echo "[${A[$k]+x}]"` vypíše `[]`). Smyčka přes
> `JAZYKY` má výhodu, že pořadí a seznam jazyků jsou na jednom místě i pro
> nabídku a nápovědu.

*spolecne.sh · \_seznam_jazyku*

```bash
_seznam_jazyku() {
    local IFS=","
    printf '%s' "${JAZYKY[*]}" | sed 's/,/, /g'
}
de, en, it, de_golf, en_golf, it_golf
```

`"${pole[*]}"` (hvězdička, ne `@`) spojí prvky do **jednoho** řetězce a jako
oddělovač použije první znak `IFS`. `local IFS` změnu omezí na funkci. `sed` pak
za čárky doplní mezery.

## 22. Nápověda a návratové kódy

*před · vždy exit 1*

```bash
_pouziti() {
    echo "Použití: $0 [de|en|it] [--swap]"
    …
    exit 1
}
```

*po · kód jako parametr*

```bash
_pouziti() {
    echo "Použití: $0 [jazyk] [volby]"
    echo "Jazyky: $(_seznam_jazyku)"
    …
    exit "${1:-0}"
}
-h|--help) _pouziti 0 ;;
*) …; _pouziti 1 >&2 ;;
```

Konvence: `--help` je úspěch (kód 0) a nápověda jde na stdout, takže ji můžeš
poslat do `less`. Chybné použití vrací kód 1 a vypisuje na stderr. Přesměrování
`_pouziti 1 >&2` platí pro celé volání funkce, takže všechny její `echo` jdou na
stderr, aniž by se funkce musela měnit.

## 23. Neznámá slovíčka

Slovíčka označená `n` se ukládají do `neznama_<jazyk>.txt`. Soubor má stejný
formát jako slovník, takže se dá načíst stejným kódem.

*spolecne.sh · \_neznama_pridej*

```bash
_neznama_pridej() {
    local f
    f=$(_soubor_neznamych "$1"); shift
    (( $# )) || return 0
    { cat "$f" 2>/dev/null; printf '%s\n' "$@"; } | sort -u > "$f.tmp" \
        && mv -f "$f.tmp" "$f"
}
```

- `(( $# )) || return 0`: bez řádků k přidání nic nedělej. `(( 0 ))` je
  „nepravda“.
- `{ …; …; }` seskupí dva příkazy do jednoho výstupu: starý obsah (pokud
  existuje, `2>/dev/null` potlačí chybu u prvního použití) a nové řádky.
- `sort -u` seřadí a odstraní duplicity. Slovíčko neoznačené dvakrát je v
  souboru jen jednou.
- Zápis do `.tmp` a `mv` je atomický, stejně jako u okna pasivního skriptu.
  Kdyby se psalo rovnou `> "$f"`, soubor by se vyprázdnil dřív, než ho `cat`
  stihne přečíst.

*spolecne.sh · \_neznama_odeber*

```bash
_neznama_odeber() {
    local f
    f=$(_soubor_neznamych "$1"); shift
    (( $# )) && [[ -f "$f" ]] || return 0
    grep -vxF -f <(printf '%s\n' "$@") "$f" > "$f.tmp"
    mv -f "$f.tmp" "$f"
    [[ -s "$f" ]] || rm -f "$f"
}
```

| Přepínač grep | Význam |
|----|----|
| `-v` | vypiš řádky, které vzoru **neodpovídají** |
| `-x` | shoda celého řádku, ne jen části |
| `-F` | vzory jsou obyčejný text, ne regulární výrazy (slovíčko může obsahovat `.` nebo `(`) |
| `-f soubor` | vzory se čtou ze souboru, jeden na řádek. Tady je „soubor“ výstup `printf` přes `<( )` |

Mezi `grep` a `mv` je `;` (nový řádek), ne `&&`. Když `grep` odebere všechny
řádky, vrátí kód 1 („nic nenalezeno“), ale prázdný výsledek je správný a musí se
zapsat. `[[ -s ]]` („soubor existuje a není prázdný“) pak prázdný soubor smaže,
takže zmizí i z nabídky.

### Kdy se odebírá

Odebírá se jen v režimu `--neznama` a jen v **1. kole**. Slovíčko, které v
opakovacím kole hned po chybě uhodneš, ještě neznamená, že ho umíš. Proto má
`_kolo` čtvrtý parametr s číslem kola. Výsledky se zapisují i při `q`:

*slovicka-interaktivni.sh · \_kolo*

```bash
case "${odpoved,,}" in
    q) _zapis_vysledky "$jazyk" "$kolo" neznama znama
       echo -e "\n\e[1;31mUkončeno po $((i-1)) slovíčkách.\e[0m"
       exit 0 ;;
    n|ne|x) neznama+=("$radek") ;;
    *) znama+=("$radek") ;;          # dřív: *) : ;;
esac
```

## 24. Dynamická nabídka

Nabídka jazyků už není napsaná napevno. Skládá se ze dvou **souběžných polí**:
`polozky` (co uvidíš) a `klice` (co skript vrátí). Prvek na stejném indexu k
sobě patří.

*spolecne.sh · \_vyber_jazyk*

```bash
local -a klice=() polozky=()
for j in "${JAZYKY[@]}"; do
    klice+=("$j"); polozky+=("${NAZVY[$j]}")
done
for j in "${JAZYKY[@]}"; do
    f=$(_soubor_neznamych "$j")
    [[ -s "$f" ]] || continue                 # jen neprázdné soubory
    n=$(wc -l < "$f")
    klice+=("neznama:$j"); polozky+=("Neznámá: ${NAZVY[$j]} ($n)")
done

volba=$(_vyber "Vyber jazyk" "${polozky[@]}")
[[ -z "$volba" ]] && exit 0
if [[ "$volba" =~ ^[0-9]+$ ]] && (( volba >= 1 && volba <= ${#klice[@]} )); then
    echo "${klice[volba-1]}"
else
    _chyba "Neplatná volba: $volba"
fi
```

- `wc -l < "$f"` s přesměrováním vypíše jen číslo. `wc -l "$f"` by připojil i
  název souboru.
- Kontrola má dva kroky: regulární výraz ověří, že jde o číslo, a teprve pak `((
  ))` porovná rozsah. Opačné pořadí by u vstupu `abc` v aritmetice vyhodnotilo
  proměnnou `abc` (prázdnou, tedy 0).
- Index pole `[volba-1]` se v bashi vyhodnocuje aritmeticky, takže `$` není
  potřeba. Nabídka čísluje od 1, pole od 0.

Návratová hodnota `neznama:en` nese dvě informace v jednom řetězci. Volající ji
rozloží:

*slovicka-interaktivni.sh · main*

```bash
if [[ "$jazyk" == neznama:* ]]; then      # glob uvnitř [[ ]] bez uvozovek
    jazyk="${jazyk#neznama:}"            # odřízni předponu
    JEN_NEZNAMA=1
fi
```

Pozor na uvozovky: `[[ $x == neznama:* ]]` porovnává se vzorem, kdežto `[[ $x ==
"neznama:*" ]]` s doslovným textem včetně hvězdičky.

## 25. Volby pro okno

Spouštěč musí předat oknu všechno, co zjistil, jinak by se okno znovu ptalo nebo
by volbu ztratilo.

*před · \$# -le 1*

```bash
if [[ "$swap" == "0" && $# -le 1 \
      && "$V_OKNE" == "0" ]]; then
    swap=$(_vyber_poradi) …
fi
…
local -a argumenty=("$jazyk")
[[ "$swap" == "1" ]] && argumenty+=("--swap")
```

*po · poradi_zadano*

```bash
--swap|-s) swap="1"; poradi_zadano="1" ;;
--orig|-o) swap="0"; poradi_zadano="1" ;;
…
if [[ "$poradi_zadano" == "0" && "$V_OKNE" == "0" ]]; then …
…
local -a argumenty=("$jazyk")
if [[ "$swap" == "1" ]]; then argumenty+=(--swap); else argumenty+=(--orig); fi
[[ "$JEN_NEZNAMA" == "1" ]] && argumenty+=(--neznama)
```

Počítání argumentů (`$# -le 1`) bylo křehké: `jazi en --neznama` by se na pořadí
nezeptal, i když ho nikdo nezadal. Samostatný příznak `poradi_zadano` říká
přesně to, co se má ověřit. Okno teď dostane pořadí vždy výslovně (`--swap` nebo
`--orig`).

> **Proč `if/else` a ne `a && b || c`:** Zkratka `[[ … ]] && x || y` (shellcheck
> SC2015) **není** if/else: když selže `x`, spustí se i `y`. U přidávání do pole
> se to stát nemůže, ale návyk psát `if` chrání před chybami jinde.

## 26. Drobnosti

| Před | Po | Proč |
|----|----|----|
| `echo -e "\e[1;33m $prvni\e[0m"` | `printf '\e[1;33m %s\e[0m\n' "$prvni"` | data se nezpracovávají jako escape sekvence |
| `(( i++ ))` | `(( ++i ))` | nevrací chybový kód při `i=0` |
| `tr '/' '⏎'` (doslovný konec řádku) | `tr '/' '\n'` | čitelnost |
| `echo "$text" | …` | `printf '%s\n' "$text" | …` | text začínající `-n` by `echo` vzal jako přepínač |
| `"$WAYLAND_DISPLAY$DISPLAY"` | `"${WAYLAND_DISPLAY:-}${DISPLAY:-}"` | funguje i se `set -u` |
| `pocet="${args[$i]}"` | `pocet="${args[i]:-}"` | `--pocet` bez hodnoty dá jasnou chybu; index je aritmetický, `$` není potřeba |
| 4 řádky mapování pro espeak | `espeak-ng -v "$tts_jazyk"` | kódy jazyků jsou stejné (`cs de en it`) |
| `"kitty-float-slovicka"` na 4 místech | `$OKNO_NAZEV` | jedno místo pro změnu |
| chyby pasivního `echo … ; exit 1` | `_chyba "…"` | z rofi se ukáže i notifikace |

## 27. Jak se to testovalo

Skripty přehrávají zvuk a otevírají okna, takže je nejde jen tak „pustit a
zkontrolovat“. Použité techniky se hodí i pro tvoje vlastní skripty.

### 1. Statická kontrola

*terminál*

```bash
for f in spolecne.sh slovicka-*.sh; do bash -n "$f"; done   # syntaxe
shellcheck -x -S warning spolecne.sh slovicka-pasivni.sh slovicka-interaktivni.sh
```

`-x` sleduje `source`, `-S warning` vynechá drobné stylové poznámky.

### 2. Terminál bez terminálu: `script`

Nabídka se chová jinak podle `[[ -t 0 ]]`. Roura (`printf '2\n' | skript`)
terminál není, takže by se otevřelo rofi. `script` vytvoří **pseudoterminál** a
vstup do něj pošle:

*terminál · ověřeno*

```bash
printf '7\n' | script -qc "bash menu.sh" /dev/null | tail -2
  7) Neznámá: 🇩🇪 Němčina (1)
Volba [1-7, Enter=1]: vysledek=[neznama:de]
```

### 3. Test funkcí s „podvrženými“ příkazy

Logika kola se testovala na kopii projektu s malým slovníkem. Skript se načetl
bez spuštění `main` a funkce, které dělají zvuk nebo čekají, se přepsaly
prázdnými:

*beh.sh · testovací kopie*

```bash
source <(sed 's/^main "\$@"$//' "$1/slovicka-interaktivni.sh")
_tts_reci(){ :; }; clear(){ :; }; sleep(){ :; }    # ticho a rychlost
trap - EXIT

mapfile -t s < <(grep ' — ' "$1/nemcina_slova.txt")
printf 'n\n\nn\n\n\n\nn\nn\n' | _kolo de 0 s | grep -E "Znám|Neznám:"
cat "$1/neznama_de.txt"
```

- `source <(sed …)` načte skript s vymazaným posledním řádkem `main "$@"`.
  Definují se funkce, ale nic se nespustí.
- Funkce má přednost před příkazem stejného jména, takže `sleep(){ :; }` „vypne“
  všechna čekání. `:` je příkaz, který nic nedělá.
- `printf 'n\n\n…'` simuluje stisky kláves: `n`, Enter, `n`, Enter, pak Enter
  pro opakování a odpovědi v opakovacím kole.

*výsledek · ověřeno*

```bash
  Znám:   2/4
  Neznám: 2/4
  Znám:   1/2
  Neznám: 1/2
Haus — dům
Hund — pes / psík
```

Zkus si totéž sám: změň vstup v `printf` a předem si napiš, co by mělo vyjít.
Když výsledek nesedí, máš chybu buď v kódu, nebo ve svém pochopení. Obojí stojí
za to najít.

*Část 3 · finální verze*

# Rozšíření: fráze, klávesy, generátory

Ke každému slovíčku přibyla vzorová věta. Pasivní režim se ovládá klávesami a
fráze generují dva skripty v Pythonu. Nové techniky: práce s procesy na pozadí,
signály, čtení kláves bez blokování, měření času a Batch API.

## 28. Přehled rozšíření

| Funkce | Hlavní technika | Kde |
|----|----|----|
| vzorové fráze | TSV soubor, `IFS=$'\t' read`, asociativní pole | `_nacti_fraze` |
| zalamování dlouhých vět | `tput cols`, `fold -s` | `_vypis_zalomene` |
| mezera = pauza | proces na pozadí, `SIGSTOP` / `SIGCONT` | `_mluv`, `_pauza` |
| `z` = znovu | `SIGTERM`, příznak a smyčka s `continue` | `_zopakuj`, hlavní smyčka |
| `x` = chybná fráze | atomický zápis, `sort -u` | `_oznac_chybnou` |
| čekání, které reaguje na klávesy | `read -t`, `$EPOCHREALTIME`, `awk` | `_cekej` |
| generování frází | Python: `argparse`, JSON schéma, Batch API | `generuj-fraze*.py` |

## 29. Fráze jako data

Fráze jsou v samostatných souborech `fraze/<slovník>.tsv`, slovníky zůstaly beze
změny. TSV (tab-separated values) je text, kde jsou sloupce oddělené
tabulátorem. Tabulátor se v běžném textu nevyskytuje, proto je to bezpečný
oddělovač.

*spolecne.sh · \_nacti_fraze*

```bash
_nacti_fraze() {
    local soubor radek fraze cs
    soubor=$(_soubor_frazi "$1")
    [[ -f "$soubor" ]] || return 0
    while IFS=$'\t' read -r radek fraze cs; do
        [[ -n "$fraze" ]] || continue
        FRAZE["$radek"]="$fraze"
        FRAZE_CS["$radek"]="$cs"
    done < "$soubor"
}
```

- **`$'\t'`** je ANSI-C quoting: bash v něm rozbalí escape sekvence, takže
  `$'\t'` je skutečný tabulátor. V obyčejných uvozovkách by `"\t"` byly dva
  znaky.
- **`IFS=$'\t' read -r a b c`** rozdělí řádek podle tabulátoru do tří
  proměnných. Mezery uvnitř vět se nedělí. Kdyby sloupců bylo víc, poslední
  proměnná dostane celý zbytek.
- **Klíčem je celý řádek slovníku** (`la chiave — klíč`), ne jen slovo. Stejné
  slovo může mít ve slovníku víc významů a každý pak dostane vlastní frázi.
  Navíc se klíč nemusí nijak počítat: `${FRAZE[$radek]}` použije přesně ten
  řádek, který skript právě zobrazuje.
- Chybějící soubor není chyba (`return 0`). Slovíčka se pak zobrazí bez fráze.
  Tak se dá funkce přidávat postupně.

> ⚠️ **Chyták: prázdný klíč:** U asociativního pole je `${FRAZE[""]}` chyba „bad
> array subscript“. Proto pasivní skript před dotazem kontroluje `[[ -n
> "$AKT_RADEK" && -n "${FRAZE[$AKT_RADEK]:-}" ]]`. Před prvním slovíčkem je
> `AKT_RADEK` prázdný. `:-` zajistí prázdný výsledek, když klíč neexistuje.

## 30. Zalamování textu

*spolecne.sh · \_vypis_zalomene*

```bash
_vypis_zalomene() {
    local barva="$1" text="$2" sirka radek
    sirka=$(( $(tput cols 2>/dev/null || echo 80) - 4 ))
    (( sirka < 20 )) && sirka=20
    while IFS= read -r radek; do
        printf '%s  %s\e[0m\n' "$barva" "$radek"
    done < <(printf '%s\n' "$text" | fold -s -w "$sirka")
}
_vypis_zalomene $'\e[3;36m' "$fraze"       # kurzíva, tyrkysová
```

- `tput cols` vrátí šířku terminálu ve znacích. V okně 820 px je to zhruba 75.
  `|| echo 80` je záloha, když terminál není.
- `fold -s` zalamuje jen v mezerách, ne uprostřed slova. Terminál by text
  zalomil sám, ale bez odsazení a klidně uprostřed slova.
- Každý řádek se vypíše s barvou a odsazením zvlášť. Kdyby se barva nastavila
  jen jednou na začátku, druhý řádek by ji neměl odsazenou.
- `$'\e[3;36m'` předává escape sekvenci jako skutečné znaky. Funkce ji pak
  vypíše přes `%s` beze změny.

> **Detail:** GNU `fold` počítá **bajty**, ne znaky. Znak s diakritikou zabírá v
> UTF-8 dva bajty, takže české řádky vycházejí o trochu kratší, než by musely.
> Nevadí to, text se vždycky vejde. Viz [cvičení 3](#41-cvičení-k-části-3).

## 31. Pasivní skript v okně

Dřív pasivní skript běžel v terminálu a okno kitty jen zobrazovalo text ze
souboru. Aby fungovala mezera, musí klávesy dostávat okno, ve kterém skript
běží. Pasivní skript proto převzal princip interaktivního: spustí sám sebe v
okně a soubor `slovicka-notif.txt` i smyčka v okně zmizely.

*spolecne.sh · společné pro oba skripty*

```bash
_lze_otevrit_okno() {
    [[ "$V_OKNE" == "0" ]] && command -v kitty &>/dev/null \
        && [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]
}
```

*slovicka-pasivni.sh · main*

```bash
if _lze_otevrit_okno; then
    local -a argumenty=("$jazyk" --pocet "$pocet" --pauza "$pauza")
    if [[ "$swap" == "1" ]]; then argumenty+=(--swap); else argumenty+=(--orig); fi
    [[ "$jen_neznama" == "1" ]] && argumenty+=(--neznama)
    [[ "$bez_frazi" == "1" ]] && argumenty+=(--bez-frazi)
    [[ "$vsechna" == "1" ]] && argumenty+=(--vsechna)
    _spust_v_okne "${argumenty[@]}"
    trap - EXIT
    exit 0
fi
```

- **Funkce jako podmínka:** `_lze_otevrit_okno` nic nevypisuje, jen vrací
  stavový kód posledního výrazu. Díky tomu se čte jako věta: „pokud lze otevřít
  okno, …“.
- **Všechny volby se předávají dál.** Skript v okně je nový proces a ví jen to,
  co dostane v argumentech. Na `--pauza` by se snadno zapomnělo, proto se
  předává i výchozí hodnota.
- **`trap … HUP`:** zavření okna pošle skriptu signál SIGHUP (hangup,
  „zavěšeno“). Skript ho zachytí stejně jako Ctrl+C a provede úklid.

*slovicka-pasivni.sh · trap*

```bash
trap _na_preruseni INT TERM HUP    # HUP = zavřené okno
trap _uklid EXIT
```

## 32. Čtení na pozadí

Dřív skript při čtení **čekal**, dokud `mpv` nedohrálo, a mezitím nemohl
reagovat na klávesy. Teď čtení běží na pozadí a skript mezitím každou desetinu
sekundy kontroluje klávesnici:

*slovicka-pasivni.sh · \_mluv*

```bash
_mluv() {
    local klavesa
    (
        trap _uklid_tts EXIT
        _tts_reci "$1" "$2"
    ) </dev/null 2>/dev/null &
    TTS_PID=$!
    while kill -0 "$TTS_PID" 2>/dev/null; do
        if IFS= read -rsn1 -t 0.1 klavesa; then
            _zpracuj_klavesu "$klavesa"
        fi
    done
    wait "$TTS_PID" 2>/dev/null
    TTS_PID=""
}
```

| Zápis | Význam |
|----|----|
| `( … ) &` | spustí blok v podprocesu na pozadí, skript pokračuje dál |
| `$!` | PID posledního procesu spuštěného na pozadí |
| `kill -0 PID` | nepošle žádný signál, jen ověří, že proces ještě žije |
| `read -s` | nevypisovat stisknutou klávesu (silent) |
| `read -n1` | skončit po jednom znaku, bez Enteru |
| `read -t 0.1` | čekat nejvýš 0,1 s. Když nic nepřijde, vrátí chybový kód a smyčka jde dál |
| `wait PID` | posbírá ukončený proces, aby nezůstal jako „zombie“ |

> ⚠️ **Kdo čte klávesnici?:** Klávesy z terminálu si může vzít každý proces,
> který z něj čte. Proto má podproces `</dev/null`: jeho vstup je prázdný, takže
> klávesy zůstanou skriptu. Stejně tak `mpv` běží s `--no-input-terminal`. Bez
> toho `mpv` při přehrávání češtiny poslouchalo klávesnici samo a `q` ukončilo
> přehrávání místo skriptu. Tahle chyba tam byla od začátku a projevila se až s
> ovládáním klávesami.

## 33. Signály: pauza a přerušení

Signál je zpráva, kterou jádro doručí procesu. Většinu znáš: Ctrl+C je SIGINT,
zavření okna SIGHUP. Pauza a opakování používají tři další:

| Signál | Co udělá | Použití |
|----|----|----|
| `SIGSTOP` | proces zamrzne, nelze ho zachytit ani ignorovat | mezera = pauza |
| `SIGCONT` | zamrzlý proces pokračuje přesně tam, kde byl | mezera = pokračovat |
| `SIGTERM` | žádost o ukončení (výchozí signál příkazu `kill`) | `z`, `q`, úklid |

*slovicka-pasivni.sh · \_signal_tts, \_zopakuj*

```python
_signal_tts() {
    [[ -n "$TTS_PID" ]] || return 0
    pkill "-$1" -P "$TTS_PID" 2>/dev/null     # potomci: piper, ffmpeg, mpv
    kill "-$1" "$TTS_PID" 2>/dev/null           # samotný podproces
    return 0
}

_zopakuj() {
    ZOPAKOVAT=1
    _signal_tts CONT      # zmrazený proces musí běžet, aby přijal TERM
    _signal_tts TERM
}
```

- **`pkill -P PID`** pošle signál všem přímým potomkům procesu. Podproces sám
  zvuk nepřehrává, to dělá roura `piper | ffmpeg | mpv`. Kdyby se zastavil jen
  podproces, `mpv` by hrálo dál.
- **Nejdřív potomci, pak podproces.** Bash odloží zpracování signálu, dokud
  neskončí příkaz, na který právě čeká. Kdyby dostal TERM jen podproces, dočkal
  by se až konce věty.
- **CONT před TERM:** zmrazený proces nemůže na TERM reagovat, takže při `z`
  během pauzy je potřeba ho nejdřív rozmrazit.
- **Podproces nedědí `trap`** hlavního skriptu, proto má vlastní `trap
  _uklid_tts EXIT`. Bez něj by přerušení během češtiny nechalo v `/tmp` soubor
  mp3, tedy stejnou chybu jako v kapitole 20, jen o úroveň hlouběji.
- **`2>/dev/null` u podprocesu:** když jeho potomka ukončí signál, bash vypíše
  „Terminated“. V okně by to rozházelo obrazovku. Odhalil to až test (kapitola
  [40](#40-testování-kláves-a-času)).

## 34. Čekání s klávesami

Pauza mezi slovíčky (`--pauza 3`) dřív používala `sleep`, který na klávesy
nereaguje. Nová funkce čeká stejně dlouho, ale každou klávesu hned zpracuje:

*slovicka-pasivni.sh · \_cekej*

```bash
_cekej() {
    local konec zbyva klavesa
    konec=$(awk -v t="${EPOCHREALTIME/,/.}" -v d="$1" 'BEGIN { printf "%.3f", t + d }')
    while zbyva=$(awk -v k="$konec" -v t="${EPOCHREALTIME/,/.}" \
                  'BEGIN { d = k - t; if (d <= 0) exit 1; printf "%.3f", d }'); do
        if IFS= read -rsn1 -t "$zbyva" klavesa; then
            _zpracuj_klavesu "$klavesa"
            (( ZOPAKOVAT )) && return 0
        fi
    done
}
```

- **`$EPOCHREALTIME`** (bash 5) je aktuální čas v sekundách s mikrosekundami,
  např. `1795261297.736758`. Je to proměnná, takže se nespouští žádný příkaz.
- **`${EPOCHREALTIME/,/.}`:** v českém prostředí má čas **desetinnou čárku**
  (`1795261298,743214`), ale `awk` čte čísla s tečkou. Bez náhrady by vzal jen
  celé sekundy a čekání by se mohlo splést až o sekundu. Ověřeno přímo:
  `LC_ALL=cs_CZ.UTF-8 bash -c 'echo $EPOCHREALTIME'`.
- **Proč `awk`:** aritmetika bashe `$(( ))` umí jen celá čísla. Pro desetinná je
  nejjednodušší `awk` (nebo `bc`).
- **Konec počítaný předem:** když se klávesa zpracuje uprostřed čekání, `read`
  skončí dřív. Smyčka pak spočítá zbytek z pevného konce, takže celkové čekání
  zůstane stejné.
- **`while zbyva=$(…)`:** podmínkou smyčky je přiřazení. To vrací stavový kód
  substituce, tedy `exit 1` z awk, když čas vypršel. Výpočet i test konce jsou v
  jednom kroku.

## 35. Opakování klávesou z

`z` může přijít kdykoli: během čtení, během čekání i během pauzy. Funkce, ve
které se to stane, přeruší jen sebe a nastaví příznak. Na začátek se vrací
hlavní smyčka:

*slovicka-pasivni.sh · hlavní smyčka*

```bash
while :; do
    ZOPAKOVAT=0
    _zobraz "$titulek" "$nazev" "$prvni" "$druhy" "$fraze" "$fraze_cs"

    _mluv "$prvni" "$prvni_jazyk";      (( ZOPAKOVAT )) && continue
    _cekej "$PAUZA_MEZI_JAZYKY";        (( ZOPAKOVAT )) && continue
    _mluv "$druhy" "$druhy_jazyk";      (( ZOPAKOVAT )) && continue
    if [[ -n "$fraze" ]]; then
        _cekej "$PAUZA_PRED_FRAZI";     (( ZOPAKOVAT )) && continue
        _mluv "$fraze" "$jazyk";        (( ZOPAKOVAT )) && continue
    fi
    _cekej "$pauza";                    (( ZOPAKOVAT )) && continue
    break
done
```

- **`while :`** je nekonečná smyčka (`:` je příkaz, který vždy uspěje). Ukončí
  ji jen `break` na konci, když vše proběhlo bez přerušení.
- **`continue`** skočí na začátek smyčky: vynuluje příznak, znovu vykreslí
  obrazovku a čte od prvního slova.
- **Proč příznak, a ne volání odjinud:** `_zopakuj` se volá hluboko uvnitř
  `_mluv` nebo `_pauza`. Odtud se do hlavní smyčky skočit nedá. Funkce proto jen
  „zvedne praporek“ a skončí. Rozhodnutí, co dál, zůstane na jednom místě.
  Stejný princip se používá v hrách a GUI.

V interaktivním režimu je to jednodušší, protože skript stejně čeká na odpověď:
`z` zavolá `_zobraz_slovicko` znovu a smyčka nápovědy pokračuje.

## 36. Nápověda v interaktivním režimu

*slovicka-interaktivni.sh · \_kolo*

```bash
local oznaceno=0 napoveda
while :; do
    napoveda="[Enter] znám · [n] neznám · [z] znovu"
    if [[ -n "${FRAZE[$radek]:-}" ]]; then
        if (( oznaceno )); then
            napoveda+=" · \e[1;31m✗ fráze označena\e[0;90m"
        else
            napoveda+=" · [x] chybná fráze"
        fi
    fi
    printf '\r\e[K\e[0;90m%b · [q] konec \e[0m' "$napoveda"
    read -r odpoved
    if [[ "${odpoved,,}" == "z" ]]; then
        _zobraz_slovicko "$radek" "$jazyk" "$swap" "$i" "$celkem"
        continue
    fi
    [[ "${odpoved,,}" == "x" ]] || break
    if (( ! oznaceno )) && _oznac_chybnou "$jazyk" "$radek"; then
        oznaceno=1
    fi
    printf '\e[1A'     # zpět na řádek s nápovědou
done
```

- **`%b` místo `%s`:** `%b` zpracuje escape sekvence i v argumentu. Barva
  `\e[1;31m` je uložená v proměnné jako text, takže by se přes `%s` vypsala
  doslova. U dat ze slovníku se naopak používá `%s`, viz kapitola 12.
- **`\e[1A`** posune kurzor o řádek nahoru. Enter po `x` posunul kurzor níž a
  nápověda se má přepsat na místě.
- **`\r\e[K`**: návrat na začátek řádku a smazání do konce. Takhle se přepisuje
  jeden řádek bez `clear`.
- **Výsledek `break`** nese proměnná `odpoved`, kterou pak zpracuje `case` pod
  smyčkou. Smyčka slouží jen k „vedlejším“ klávesám `x` a `z`.

## 37. Označení chybné fráze

*spolecne.sh · \_oznac_chybnou*

```bash
_oznac_chybnou() {
    local jazyk="$1" radek="$2" soubor
    [[ -n "${FRAZE[$radek]:-}" ]] || return 1
    soubor=$(basename "$(_soubor_frazi "$jazyk")")
    { cat "$SOUBOR_CHYBNYCH" 2>/dev/null
      printf '%s\t%s\t%s\t%s\n' "$soubor" "$radek" "${FRAZE[$radek]}" "${FRAZE_CS[$radek]:-}"
    } | sort -u > "$SOUBOR_CHYBNYCH.tmp" && mv -f "$SOUBOR_CHYBNYCH.tmp" "$SOUBOR_CHYBNYCH"
}
```

Je to stejný vzor jako `_neznama_pridej` v kapitole 23: starý obsah plus nový
řádek, `sort -u` odstraní duplicity a `mv` soubor atomicky nahradí. Opakování
osvědčeného vzoru je dobrá praxe, protože kód se čte snáz a chyby se opravují na
jednom místě.

- **`return 1`** u slovíčka bez fráze. Volající podle toho pozná, jestli se
  označení povedlo: `_oznac_chybnou … && AKT_OZNACENO=1`.
- **Do souboru se zapisuje i jméno souboru frází.** Při opravě je pak jasné,
  který soubor upravit. V `chybne.tsv` se míchají všechny jazyky.
- **Pojistka proti opakování** (`AKT_OZNACENO`) je nadbytečná, `sort -u` by
  duplicitu stejně odstranil. Ušetří ale zbytečný zápis a hlavně řídí text
  nápovědy.

## 38. Generátor s lokálním modelem

`generuj-fraze.py` je v Pythonu, protože se v něm s JSON a HTTP pracuje snáz než
v bashi. Používá jen standardní knihovnu (`urllib`, `json`, `argparse`), takže
nic neinstaluje.

*generuj-fraze.py · obnovení po přerušení*

```python
def nacti_hotove(soubor: Path) -> set[str]:
    if not soubor.exists():
        return set()
    return {r.split("\t", 1)[0] for r in soubor.read_text(encoding="utf-8").splitlines() if "\t" in r}

radky = list(dict.fromkeys(r.strip() for r in zdroj.read_text(encoding="utf-8").splitlines() if ODDELOVAC in r))
hotove = nacti_hotove(cil)
zbyva = [r for r in radky if r not in hotove]
```

- **Obnovení po přerušení:** výsledky se po každé dávce připíšou do souboru
  (`open("a")` a `flush()`). Při dalším spuštění se hotové řádky načtou do
  **množiny** (`set`) a přeskočí se. Hledání v množině je okamžité i při
  tisících položek.
- **`dict.fromkeys(…)`** odstraní duplicity a **zachová pořadí**. `set()` by
  pořadí zamíchal. Ve slovnících je celkem 207 zdvojených řádků (12 033 řádků,
  11 826 různých).
- **`for … else`** při opakování neúspěšného dotazu: větev `else` se provede,
  jen když smyčka doběhla bez `break`, tedy když selhaly všechny tři pokusy. Je
  to méně známá konstrukce Pythonu, ale přesně se sem hodí.
- **Kontrola kvality** (`platna()`) zahodí věty, které jsou zjevně špatně: jsou
  moc krátké, opakují heslo nebo obsahují zkopírovanou poznámku. Zahozené se
  zkusí znovu.

> **Poučení z praxe:** Lokální model gpt-oss-20b psal cizojazyčné věty dobře,
> ale česká část měla zhruba třetinu chyb („Pečl celý dort“, „Uklízel včera celý
> město“). Lepší zadání pomohlo jen trochu. U jazykových úloh rozhoduje hlavně
> model, a menší modely bývají slabé právě v menších jazycích, jako je čeština.

## 39. Generátor přes Claude

### Skript se závislostmi bez instalace

*generuj-fraze-claude.py · začátek*

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["anthropic"]
# ///
```

- **Inline metadata (PEP 723):** komentářový blok `# /// script` uvádí
  závislosti přímo ve skriptu. `uv run --script` je načte, stáhne do mezipaměti
  a skript spustí v izolovaném prostředí. Do systému se nic neinstaluje.
- **`env -S`** rozdělí zbytek shebangu na víc argumentů. Bez `-S` by jádro
  hledalo program s názvem „uv run --script“.

### Sdílený kód z jiného skriptu

*generuj-fraze-claude.py · import*

```python
_spec = importlib.util.spec_from_file_location("generuj_fraze", ADRESAR / "generuj-fraze.py")
assert _spec is not None and _spec.loader is not None, "chybí generuj-fraze.py"
gf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gf)
# pak: gf.prompt(…), gf.platna(…), gf.SLOVNIKY
```

Zadání pro model, seznam slovníků i kontrola kvality jsou v `generuj-fraze.py` a
nekopírují se. Běžné `import generuj-fraze` nejde, protože pomlčka není v názvu
modulu povolená. `importlib` načte soubor podle cesty. Je to pythonská obdoba
`source` z kapitoly 17.

### Průběh Batch API

1.  **Sestavení:** slovíčka se rozdělí po 25. Každý dotaz dostane `custom_id`
    (např. `s2-00050`) a skript si uloží, která slovíčka k němu patří.
2.  **Odeslání:** `client.messages.batches.create(requests=…)` pošle všech asi
    475 dotazů najednou. ID dávky a mapa se uloží do `fraze/.claude-batch.json`.
3.  **Čekání:** jednou za minutu `batches.retrieve(id)`, dokud stav není
    `ended`. Ctrl+C nic nezruší, dávka běží na serveru.
4.  **Výsledky:** `batches.results(id)` vrací odpovědi **v libovolném pořadí**.
    Proto se párují podle `custom_id`, nikdy podle pozice.
5.  **Zápis:** každá věta projde kontrolou kvality a zapíše se. Ze `usage` v
    odpovědích se spočítá skutečná cena.

*generuj-fraze-claude.py · jeden dotaz*

```python
Request(
    custom_id=cid,
    params=MessageCreateParamsNonStreaming(
        model=args.model,
        max_tokens=16000,
        output_config={
            "effort": args.effort,                                     # low = nejlevnější
            "format": {"type": "json_schema", "schema": SCHEMA},       # vynucený JSON
        },
        messages=[{"role": "user", "content": gf.prompt(jazyk, golf, davka)}],
    ),
)
```

- **Strukturovaný výstup** (`output_config.format`) zaručí, že odpověď je platný
  JSON podle schématu. Odpadne parsování a hádání, kde JSON začíná. Schéma musí
  mít `additionalProperties: false`.
- **Přihlášení:** skript zkusí `ANTHROPIC_API_KEY`, pak soubor s klíčem a
  nakonec profil z `ant auth login`. Ten knihovna `anthropic` najde sama.
- **Cena:** výstupní tokeny jsou pětkrát dražší než vstupní a tvořily přes 85 %
  ceny. Batch API dává slevu 50 %. Skutečná cena: 0,78 USD za 1000 slovíček s
  Opusem 5.5, 0,40 USD se Sonnetem 5.5. Odhad z délky vět byl o 50 % nižší,
  protože nepočítal s uvažováním modelu a s novým tokenizérem. Proto je dobré
  nejdřív pustit malou zkoušku (`--limit 40`) a teprve pak celek.

> ⚠️ **Skutečná chyba: idempotence:** Při prvním spuštění skript přesouvá fráze
> z lokálního modelu do zálohy. Kontroloval přitom „existuje záloha tohoto
> souboru?“. Po zkoušce s Opusem ale v pěti souborech byly už fráze **od
> Claude** a jejich záloha neexistovala, takže je hlavní běh přesunul taky.
> Oprava: značka `fraze/lokalni/.hotovo`, která se vytvoří po prvním zálohování.
> Poučení: operace „jen poprvé“ musí mít vlastní značku. Odvozovat „poprvé“ z
> jiného stavu je křehké. Operace, kterou lze bezpečně spustit opakovaně, se
> nazývá **idempotentní**.

## 40. Testování kláves a času

Klávesy, pauzu a opakování nejde otestovat statickou kontrolou. Testy proto
simulovaly uživatele s přesným načasováním:

*test pauzy · ověřeno*

```bash
# čtení podvržené smyčkou, která každých 0,2 s zapíše čas
_tts_reci() { for i in $(seq 1 15); do printf '%s\n' "${EPOCHREALTIME/,/.}" >> log; sleep 0.2; done; }

# mezera po 0,8 s, další mezera o 2 s později
( sleep 0.8; printf ' '; sleep 2; printf ' '; sleep 6 ) | script -qc "bash test.sh" /dev/null

# v logu hledáme mezeru mezi časy delší než 1 s
awk 'NR>1{d=$1-p; if(d>1) printf "mezera: %.1f s\n", d} {p=$1}' log
mezera mezi ticky: 2.0 s (po 5. ticku)
```

- **Časovaný vstup:** `( sleep 0.8; printf ' '; … ) | script -qc …` „zmáčkne“
  klávesy v přesně daných okamžicích. `script` vytvoří pseudoterminál, takže
  `read -n1` funguje jako u skutečné klávesnice.
- **Podvrh s měřitelným výsledkem:** místo hlasu běží smyčka, která zapisuje
  čas. Pauza je pak vidět jako díra v časech, což se dá ověřit číslem, ne
  odhadem.
- **Kontrola osiřelých procesů:** po `q` nesmí nic běžet. První test hlásil
  „zůstal proces“, ale `pgrep -f` našel jen příkazový řádek samotného testu, ve
  kterém hledaný text byl. Falešný poplach odhalil přesnější dotaz (`pgrep -P
  $$`, tedy jen potomci). **I test se může mýlit**, takže podezřelé výsledky
  ověřuj jinou cestou.
- **Test odhalil chybu, kterou by čtení kódu nenašlo:** hlášku „Terminated“ v
  okně po `z` (kapitola 33).

## 41. Cvičení k části 3

Pracuj na kopii projektu (`cp -r ~/Projects/Jazyky ~/pokus`), aby se ti
nepřepsaly fráze ani neznámá slovíčka.

<details><summary><b>1. Klávesa b : zpět na předchozí slovíčko</b></summary>

*procvičíš: příznaky, indexované procházení pole*

V pasivním režimu přidej klávesu `b` (back), která se vrátí na předchozí
slovíčko. Nápověda: smyčka `for radek in …` se vrátit neumí, potřebuješ index.

*řešení*

```bash
ZPET=0
_zpet() { ZPET=1; _signal_tts CONT; _signal_tts TERM; }
# do _zpracuj_klavesu a _pauza:  b|B) _zpet ;;   (v _pauza: _zpet; break)
# v _cekej:  (( ZOPAKOVAT || ZPET )) && return 0

local idx=0
while (( idx < ${#slovicka[@]} )); do
    radek="${slovicka[idx]}"
    …
    while :; do
        ZOPAKOVAT=0; ZPET=0
        _zobraz …
        _mluv "$prvni" "$prvni_jazyk"; (( ZOPAKOVAT )) && continue; (( ZPET )) && break
        …                              # stejně u každého kroku
        break
    done
    if (( ZPET )); then
        (( idx > 0 )) && (( idx-- ))
    else
        (( ++idx ))
    fi
done
```

Pozor na `(( idx-- ))`, když se z 1 stane 0: výraz vrátí starou hodnotu 1, takže
je to v pořádku. Problém by nastal u `(( idx-- ))` na nule, viz chyták v
kapitole 5. Ten tady hlídá `idx > 0`.

</details>

<details><summary><b>2. Volba --jen-s-frazi</b></summary>

*procvičíš: filtrování pole, pořadí operací*

Přidej volbu, která vybere jen slovíčka, ke kterým existuje fráze. Hodí se, když
je slovník vygenerovaný jen zčásti.

*řešení*

```bash
--jen-s-frazi) jen_s_frazi=1 ;;
# fráze se musí načíst PŘED výběrem slovíček
_nacti_fraze "$jazyk"
if (( jen_s_frazi )); then
    mapfile -t slovicka < <(cut -f1 "$(_soubor_frazi "$jazyk")" | grep -Fxf - "$soubor" | shuf | head -n "$pocet")
fi
```

`grep -Fxf -` čte vzory ze stdin (`-f -`): celé řádky (`-x`), doslova (`-F`).
Vybere tak řádky slovníku, které jsou i v prvním sloupci souboru frází.
Nezapomeň volbu předat do okna, viz kapitola 31.

</details>

<details><summary><b>3. Zalamování podle znaků, ne bajtů</b></summary>

*procvičíš: \${#text}, práce s řetězci v bashi*

Napiš vlastní zalamování, které počítá znaky. Bash v UTF-8 prostředí počítá
`${#slovo}` ve znacích.

*řešení*

```bash
_zalom() {   # _zalom šířka "text"
    local sirka="$1" radek="" slovo
    for slovo in $2; do                       # záměrně bez uvozovek: dělení podle mezer
        if (( ${#radek} + ${#slovo} + 1 > sirka )) && [[ -n "$radek" ]]; then
            printf '%s\n' "$radek"; radek="$slovo"
        else
            radek="${radek:+$radek }$slovo"
        fi
    done
    [[ -n "$radek" ]] && printf '%s\n' "$radek"
}
```

`${radek:+$radek }` znamená „pokud `radek` není prázdný, dej `$radek` a mezeru“,
takže první slovo nedostane mezeru před sebou. Nevýhoda: `for slovo in $2`
rozbalí i znaky `*` a `?` jako glob. Ošetři to přes `set -f` uvnitř funkce, nebo
přes `read -ra slova <<< "$2"`.

</details>

<details><summary><b>4. Ukazatel průběhu s odhadem konce</b></summary>

*procvičíš: \$EPOCHREALTIME, aritmetika vawk*

Do titulku pasivního režimu přidej odhad, za jak dlouho poslech skončí, např.
„~6 min“.

*řešení*

```bash
start="${EPOCHREALTIME/,/.}"        # před smyčkou
# v cyklu, před _zobraz:
if (( i > 1 )); then
    zbyva=$(awk -v s="$start" -v t="${EPOCHREALTIME/,/.}" -v i="$i" -v n="$celkem" \
        'BEGIN { printf "%d", (t - s) / (i - 1) * (n - i + 1) / 60 + 0.5 }')
    titulek+="  ·  ~${zbyva} min"
fi
```

Průměrná doba na slovíčko krát počet zbývajících. Pauzy a opakování odhad
zkreslí. Zkus je vyloučit tak, že se po pauze posune `start` o dobu pauzy.

</details>

<details><summary><b>5. Oprava chybných frází přes Claude jedním příkazem</b></summary>

*procvičíš: Python, propojení souborů, Batch API*

Napiš volbu `--opravit` do `generuj-fraze-claude.py`: vezme řádky z
`fraze/chybne.tsv`, smaže jejich fráze z příslušných `.tsv` a nechá je
vygenerovat znovu.

*řešení (kostra)*

```python
def odstran_chybne() -> None:
    soubor = ADRESAR_FRAZI / "chybne.tsv"
    if not soubor.exists():
        return
    podle_souboru: dict[str, set[str]] = {}
    for r in soubor.read_text(encoding="utf-8").splitlines():
        tsv, radek, *_ = r.split("\t")
        podle_souboru.setdefault(tsv, set()).add(radek)
    for tsv, radky in podle_souboru.items():
        cesta = ADRESAR_FRAZI / tsv
        zachovat = [r for r in cesta.read_text(encoding="utf-8").splitlines(keepends=True)
                    if r.split("\t", 1)[0] not in radky]
        cesta.write_text("".join(zachovat), encoding="utf-8")
    soubor.unlink()
# v main(): if args.opravit: odstran_chybne()   a pak normálně odesli()
```

Skript generuje jen slovíčka bez fráze, takže po smazání chybných řádků je
odešle znovu sám. Pro jistotu napiš do zadání pro model, ať napíše jinou větu
než minule. Původní větu mu můžeš poslat jako „špatný příklad“.

</details>

# Část 4: GTK okno, intro a libovolný Wayland

*Stav k 24. 11. 2026 · `slovicka.sh` · `spolecne.sh` · `slovicka-view.py` ·
`intro-obrazek.py`*

Od části 3 se změnilo hodně: okno kitty nahradilo vlastní GTK okno, přibyly tři
jazyky, společný spouštěč, intro s obrázkem a hudbou, play/pauza v interaktivním
režimu a nabídka, která funguje v libovolném Wayland prostředí. Kapitoly 1, 10 a
11 o kitty a `niri msg` proto popisují už jen historii.

## 42. Přehled změn

| Funkce | Hlavní technika | Kde |
|----|----|----|
| okno bez kitty | GTK4 + Pango, příkazy přes deskriptor, `uv run --script` | `slovicka-view.py`, `_view` |
| závislosti bez instalace | inline metadata skriptu (PEP 723) | hlavička `.py` souborů |
| výchozí interaktivní režim | filtrování argumentů, `exec` | `slovicka.sh` |
| intro | otisk `sha256sum`, nejnovější soubor přes `find -printf`, Pillow | `_intro_priprav`, `intro-obrazek.py` |
| play/pauza v interaktivním režimu | čtení na pozadí, návratové kódy `read -t` | `_precti` |
| spolehlivá pauza | pořadí signálů (souběh rodič × potomek) | `_signal_tts` |
| nabídka bez rofi | GTK okno vracející číslo volby | `slovicka-view.py --vyber`, `_vyber` |
| fokus v GNOME/KDE | aktivační token, předávání souborem kvůli `$( )` | `_s_tokenem`, `TOKEN_SOUBOR` |
| plovoucí intro všude | dialog (`transient_for`) místo pravidel kompozitoru | třída `Intro` |
| přenositelnost | podmíněné proměnné prostředí, `fc-match`, hledání Piperu | `slovicka-view.py`, `_najdi_piper` |

## 43. Skript se závislostmi: `uv run --script`

*slovicka-view.py · 1–5*

```python
#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pygobject"]
# ///
```

Blok `# /// script` je standard PEP 723: skript sám popisuje, jaké knihovny
potřebuje. `uv run --script` je při prvním spuštění stáhne (PyGObject si sestaví
ze zdrojů, asi 20 s) do vlastního prostředí a dál používá cache. Na systému tak
nemusí být nainstalovaný `python-gobject` a skript nezávisí na verzi Pythonu v
distribuci.

`env -S` rozdělí zbytek řádku na víc argumentů. Bez `-S` by jádro předalo `uv
run --quiet --script` jako **jeden** argument a `env` by hledal program s
mezerami v názvu.

> **Proč ne `python3 slovicka-view.py`:** shebang zajistí, že skript jde spustit
> i přímo (`./slovicka-view.py`). Bash ho ale spouští explicitně (`uv run
> --quiet --script "$VIEW_PY"`), aby nezáleželo na spustitelném bitu souboru.

## 44. Společný spouštěč

*slovicka.sh*

```bash
skript="$adresar/slovicka-interaktivni.sh"
argumenty=()
for arg in "$@"; do
    case "$arg" in
        --pasivni|pasivni|-P) skript="$adresar/slovicka-pasivni.sh" ;;
        --interaktivni|interaktivni|-I) skript="$adresar/slovicka-interaktivni.sh" ;;
        *) argumenty+=("$arg") ;;
    esac
done
exec "$skript" "${argumenty[@]}"
```

Spouštěč z argumentů **vyfiltruje** volbu režimu a zbytek předá dál beze změny.
Pole `argumenty` drží každý argument zvlášť, takže se nerozbijí ani argumenty s
mezerami.

`exec` nahradí proces spouštěče vybraným skriptem, nevznikne tedy zbytečný
mezičlánek. Signály (Ctrl+C) i návratový kód jdou rovnou ke skutečnému skriptu.

## 45. Intro: kontrola změn a nejnovější soubor

*spolecne.sh · _intro_soubor, _intro_priprav*

```bash
_intro_soubor() {
    local -a vzory=() p
    for p in "$@"; do vzory+=(-o -iname "*.$p"); done
    find "$INTRO_ADR" -maxdepth 1 -type f \( "${vzory[@]:1}" \) -printf '%T@\t%p\n' 2>/dev/null \
        | sort -rn | head -n1 | cut -f2-
}

otisk=$( { sha256sum "$obrazek" "$INTRO_PY" | cut -d' ' -f1
           sha256sum "$INTRO_TEXT" 2>/dev/null | cut -d' ' -f1
           printf '%s\n' "$obrazek" "$vlajky"
         } | sha256sum | cut -d' ' -f1 )
if [[ -f "$INTRO_VYSTUP" && "$(cat "$INTRO_OTISK" 2>/dev/null)" == "$otisk" ]]; then
    return 0
fi
```

**Nejnovější soubor.** Pole `vzory` poskládá podmínku `-o -iname "*.jpg" -o
-iname "*.png" …`. Výraz `${vzory[@]:1}` vynechá první `-o`, aby podmínka
nezačínala spojkou. `-printf '%T@\t%p\n'` vypíše čas změny v sekundách a cestu,
`sort -rn` seřadí od nejnovějšího a `cut -f2-` nechá jen cestu (i s mezerami
nebo tabulátory dál v názvu).

**Otisk (hash).** Obrázek se má přegenerovat, jen když se změnil text, fotka,
seznam vlajek nebo samotný generátor. Místo porovnávání časů se spočítá
`sha256sum` všech vstupů a z nich jeden společný otisk. Ten se uloží vedle
vygenerovaného obrázku. Porovnání otisků trvá pár milisekund, generování obrázku
stovky.

> **Proč i cesta a generátor:** když vyměníš fotku za jinou se stejným obsahem
> pod jiným jménem, nebo upravíš `intro-obrazek.py` (třeba rozvržení textu),
> obrázek se má složit znovu. Proto jsou v otisku i název souboru a hash
> generátoru.

*intro-obrazek.py · fc_match*

```python
def fc_match(vzor: str, musi_obsahovat: str = "") -> str | None:
    cesta = subprocess.run(["fc-match", "-f", "%{file}", vzor],
                           capture_output=True, text=True, timeout=5).stdout.strip()
    if cesta and Path(cesta).exists() and musi_obsahovat.lower() in Path(cesta).name.lower():
        return cesta
    return None
```

Cesty k fontům se mezi distribucemi liší (`/usr/share/fonts/noto/` na Archu,
`/usr/share/fonts/truetype/noto/` na Debianu). `fc-match` se zeptá fontconfigu.
Pozor: fontconfig vrátí **vždy nějaký** font, i když hledaný chybí. U emoji
proto kód ověří, že v názvu souboru opravdu je „emoji“.

## 46. Play/pauza: čtení na pozadí a `read -t`

*slovicka-interaktivni.sh · _precti (zkráceno)*

```bash
( trap _uklid_tts EXIT
  _tts_reci "$prvni" "$prvni_jazyk"; sleep "$PAUZA_PO_ORIG"; … ) </dev/null 2>/dev/null &
TTS_PID=$!
while kill -0 "$TTS_PID" 2>/dev/null; do
    IFS= read -r -t 0.1 klavesa
    case $? in
        0) ;;                       # přečten řádek
        1) klavesa=q ;;             # konec vstupu (zavřené okno)
        *) continue ;;              # vypršel čas, nic nestisknuto
    esac
    case "${klavesa,,}" in
        " ") … _signal_tts STOP / CONT … ;;
        z)   znovu=1; _signal_tts CONT; _signal_tts TERM ;;
        *)   ODPOVED="$klavesa"; ODPOVED_ZADANA=1; _signal_tts CONT; _signal_tts TERM ;;
    esac
done
```

Dřív interaktivní režim četl slovíčko **synchronně**, tedy po dobu čtení nic
jiného nedělal a mezera neměla na co reagovat. Teď čtení běží v podprocesu na
pozadí (stejně jako v pasivním režimu, kapitola 32) a hlavní smyčka mezitím čeká
na klávesy.

- **`kill -0`** nic nezabíjí, jen ověří, že proces ještě existuje.
- **Návratový kód `read -t`** rozliší tři situace: `0` = přečteno, `1` = konec
  vstupu (okno se zavřelo, roura je prázdná a zavřená), větší než 128 = vypršel
  čas.
- **`IFS= read`**: bez `IFS=` by `read` ořízl mezery na okrajích a mezera by se
  změnila v prázdný řetězec, tedy v Enter. Tady je mezera samotná klávesa, proto
  se okraje ořezávat nesmí.
- **Odpověď během čtení:** Enter nebo `n` čtení přeruší a uloží odpověď do
  `ODPOVED`. Příznak `ODPOVED_ZADANA` je nutný, protože Enter je prázdný řetězec
  – bez příznaku by se nedalo poznat „odpověděl Enterem“ od „zatím nic“.

> **Souběh při pauze.** Pauza zprvu občas nefungovala: `piper` hrál dál, i když
> byl podproces zastavený. Funkce `_signal_tts` nejdřív poslala `SIGSTOP`
> potomkům (`pkill -P`) a teprve potom rodiči. Mezi těmi dvěma kroky stihl rodič
> spustit dalšího potomka, kterého už první krok neviděl. Oprava: u `STOP`
> nejdřív zastavit rodiče, pak potomky – zastavený rodič už nikoho nového
> nespustí.

```bash
if [[ "$1" == "STOP" ]]; then
    kill -STOP "$TTS_PID" 2>/dev/null
    pkill -STOP -P "$TTS_PID" 2>/dev/null
else
    pkill "-$1" -P "$TTS_PID" 2>/dev/null
    kill "-$1" "$TTS_PID" 2>/dev/null
fi
```

## 47. Nabídka v GTK a aktivační token

Bez terminálu se dřív jazyk vybíral přes `rofi -dmenu`. Rofi ale nefunguje všude
(třeba v GNOME). Nabídku teď kreslí `slovicka-view.py --vyber "Výzva" položka…`
a na stdout vypíše číslo volby. Bash ho přečte stejně jako dřív výstup rofi.

Druhý problém je **fokus**. Wayland nedovolí oknu, aby si fokus vzalo samo –
jinak by se jakékoli okno mohlo „vnutit“ doprostřed psaní. Okno potřebuje
**aktivační token** (protokol xdg-activation), který vydá aplikace, se kterou
uživatel právě pracuje. Spouštěč aplikací (fuzzel, rofi) token předá v proměnné
`XDG_ACTIVATION_TOKEN`. GTK ho při startu převezme a okno dostane fokus.

Jenže token se dá použít **jen jednou** a oken je víc (výběr jazyka → výběr
pořadí → karta). Řešení: každá nabídka po výběru požádá o nový token pro další
okno (`get_app_launch_context().get_startup_notify_id()`) a vypíše ho na druhý
řádek.

*spolecne.sh · _vyber, _s_tokenem (zkráceno)*

```bash
readonly TOKEN_SOUBOR="${XDG_RUNTIME_DIR:-/tmp}/slovicka-aktivace.$$"

vystup=$(_s_tokenem uv run --quiet --script "$VIEW_PY" --vyber "$vyzva" "$@") || return 0
{ IFS= read -r index; IFS= read -r token; } <<< "$vystup"
[[ -n "$token" ]] && printf '%s' "$token" > "$TOKEN_SOUBOR"
echo "$index"
```

> **Proč soubor a ne proměnná:** `_vyber` se volá jako `jazyk=$(_vyber_jazyk)`,
> tedy v **podshellu**. Co podshell nastaví nebo exportuje, se do rodiče
> nevrátí. Soubor ano. Název obsahuje `$$`, což je PID hlavního skriptu – a ten
> zůstává stejný i uvnitř podshellů (na rozdíl od `$BASHPID`). Všechny podshelly
> tak píšou do stejného souboru.

`_s_tokenem` token ze souboru přečte, smaže (je jednorázový) a předá ho jako
proměnnou jen spouštěnému příkazu: `XDG_ACTIVATION_TOKEN="$token" "$@"`. Na X11
se místo toho použije `DESKTOP_STARTUP_ID`.

## 48. Intro jako dialog: plovoucí bez pravidel

První verze ukazovala intro přes `mpv` v samostatném okně. V dlaždicovém
kompozitoru (niri, sway, Hyprland) by se takové okno zařadilo mezi dlaždice,
takže bylo potřeba pravidlo v konfiguraci niri. To ale nefunguje jinde.

Okno s **rodičem** (`transient_for`) je pro kompozitor dialog – a dialogy
otevírají plovoucí všechny. Intro proto kreslí přímo `slovicka-view.py` na
příkaz `INTRO`:

*slovicka-view.py · třída Intro (zkráceno)*

```python
super().__init__(transient_for=karta, decorated=False, resizable=False)
pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(cesta, sirka, vyska, True)
_ok, png = pixbuf.save_to_bufferv("png", [], [])
obraz = Gtk.Picture.new_for_paintable(Gdk.Texture.new_from_bytes(GLib.Bytes.new(png)))
```

> **Chyták: velikost okna.** Okno bez možnosti změny velikosti
> (`resizable=False`) má **přirozenou velikost obsahu**. `Gtk.Picture` z fotky
> 1920×1080 chtěl 1920×1080, a `set_size_request` nastavuje jen minimum. Proto
> se obrázek nejdřív zmenší na cílový rozměr a okno pak sedí přesně na 1280×720.

Hudba hraje dál přes `mpv`, ale jen zvuk (`--no-video`). Skript čeká jedním
`read -t "$INTRO_DELKA"`: buď vyprší čas, nebo přijde klávesa – dialog při
přeskočení pošle skriptu Enter.

## 49. Přenositelnost

- **Grafická karta:** okno vynucovalo integrovanou AMD grafiku proměnnými
  `VK_DRIVER_FILES` a `__EGL_VENDOR_LIBRARY_FILENAMES`. Na počítači bez těch
  souborů by GTK nemělo čím kreslit. Teď se nastaví jen tehdy, když soubory
  existují (`os.path.exists`).
- **Piper:** hledá se postupně v `SLOVICKA_PIPER`, v instalaci přes `uv tool`, v
  `~/.local/bin` a v `PATH`. Pořadí není náhodné: na některých distribucích je
  „piper“ i nástroj na nastavení herních myší, proto má instalace přes `uv`
  přednost.
- **Hlasy:**
  `${SLOVICKA_PIPER_MODELY:-${XDG_DATA_HOME:-$HOME/.local/share}/piper}` –
  vnořené výchozí hodnoty: nejdřív vlastní proměnná, pak standardní
  `XDG_DATA_HOME`, nakonec obvyklá cesta.
- **Nabídka:** pořadí GTK → `rofi` → `fuzzel` → `wofi` → `zenity`. Rofi umí
  vrátit číslo řádku (`-format d`), ostatní vrací text, který se pak dohledá v
  seznamu položek.

## 50. Jak se testovalo (a na co si dát pozor)

Okna se testovala naživo na niri: `niri msg -j windows` vypíše okna jako JSON
(název, plovoucí, fokus, velikost) a klávesy posílal `wtype`. **Vždy až po
kontrole, že fokus má testované okno** – jinak by klávesa (třeba Enter) skončila
v jiném okně, klidně v terminálu.

Zvuk se při testech ztlumil **podvrženými příkazy**: do `PATH` se dala složka s
vlastním `mpv`, který jen přečte vstup a chvíli počká. Skript nic nepozná a test
je potichu.

Při testech se objevily tři chyty, které se hodí znát:

1. **Diagnostika v rouře.** Test posílal klávesy rourou (`( printf ' \n'; … ) |
   ./skript`) a uprostřed vypsal `pgrep` pro kontrolu. Ten výstup ale šel do
   **stejné roury** a skript ho bral jako stisknuté klávesy. Diagnostiku je
   potřeba přesměrovat do souboru nebo na stderr.
2. **`read -t 0.3 < <(:)` nečeká.** Měla to být náhrada `sleep`, ale `<(:)` je
   prázdný vstup, který se hned zavře – `read` dostane konec souboru a skončí
   okamžitě, bez čekání.
3. **`pgrep -f` najde sám sebe.** `while pgrep -f fake.sh; do sleep 0.5; done`
   čekal donekonečna, protože vzor `fake.sh` je i v příkazové řádce shellu,
   který smyčku spouští. Pomůže hledat konkrétnější vzor (`'bin/bash
   .*fake.sh'`) nebo PID uložený při spuštění (`$!`).

## 51. Cvičení k části 4

<details><summary><b>1. Délka intra podle hudby</b></summary>

*procvičíš: ffprobe, aritmetika*

Uprav `_intro_spust`, aby intro trvalo jako hudba, nejvýš ale `INTRO_DELKA`
sekund.

```bash
local delka=$INTRO_DELKA d
if [[ -n "$hudba" ]]; then
    d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$hudba")
    d=${d%.*}                                   # celé sekundy
    [[ "$d" =~ ^[0-9]+$ ]] && (( d > 0 && d < delka )) && delka=$d
fi
```

`ffprobe` vypíše délku jako desetinné číslo (`59.981`). Bash počítá jen s celými
čísly, proto `${d%.*}` odřízne desetinnou část. Kontrola regulárním výrazem
chrání před prázdným výstupem, když soubor není zvukový.

</details>

<details><summary><b>2. Token bez souboru</b></summary>

*procvičíš: podshelly, globální proměnné*

Přepiš `_vyber_jazyk` tak, aby nevracel výsledek přes `$( )`, ale přes globální
proměnnou (`VYBRANY_JAZYK`). Pak může `_vyber` ukládat token do proměnné místo
do souboru.

Klíčové je volat funkci **bez** `$( )`: `_vyber_jazyk; jazyk=$VYBRANY_JAZYK`.
Funkce pak běží v hlavním shellu a její přiřazení zůstanou. Nevýhoda: `_vyber`
píše nabídku na stdout terminálu, takže výstup z GTK nabídky se musí zachytit
uvnitř (`vystup=$(uv run …)`) a do globální proměnné uložit až výsledek.

</details>

<details><summary><b>3. Test pauzy bez lidí</b></summary>

*procvičíš: ps, stavy procesů*

Napiš test, který spustí interaktivní skript s podvrženým `mpv`, pošle mezeru a
ověří, že žádný potomek čtení neběží (stav procesu `T` = zastaven).

```bash
( sleep 1; printf ' \n'; sleep 0.5
  ps -o stat=,comm= --ppid "$(pgrep -nf '^bash ./slovicka-interaktivni')" > /tmp/stav.txt
  printf 'q\n' ) | PATH="$PWD/shim:$PATH" ./slovicka-interaktivni.sh fr --orig --bez-sumu >/dev/null
grep -v '^T' /tmp/stav.txt && echo "CHYBA: něco běží" || echo "OK: vše zastaveno"
```

Skript spuštěný přes shebang má v příkazové řádce `bash
./slovicka-interaktivni.sh` a stejnou řádku mají i jeho podshelly – `pgrep -n`
vybere nejnovější z nich, tedy obvykle podproces čtení, jehož potomky (`piper`,
`ffmpeg`, `mpv`) chceme kontrolovat. Diagnostika jde do souboru, ne do roury se
vstupem skriptu (viz kapitola 50, chyták 1).

</details>

# Část 5: učení napříč jazyky

*Stav k 24. 11. 2026 · `slovnik/*.tsv` · `fraze/*.tsv` · `locale/*.tsv` ·
`spolecne.sh` · `generuj-claude.py`*

Do části 4 byla čeština natvrdo jediný mateřský jazyk: každý slovník měl tvar
`cizí slovo — česky` a věty měly jen český překlad. Část 5 popisuje přestavbu,
po které jde procvičovat **libovolnou dvojici ze sedmi jazyků** (Němec se učí
španělsky, Rus anglicky, cizinec česky) a rozhraní mluví všemi sedmi jazyky.
Mění se hlavně data; zbytek skriptů zůstal skoro stejný díky jednomu triku
(kapitola 54).

## 52. Přehled změn

| Co | Dřív | Teď |
|----|----|----|
| slovník | 9 souborů `<jazyk>_slova.txt`, `golf_<jazyk>.txt` | 2 tabulky pojmů `slovnik/obecne.tsv`, `slovnik/golf.tsv` |
| věty | `fraze/<slovník>.tsv`: věta + český překlad | `fraze/<sada>-<jazyk>.tsv`: věta + překlady do všech jazyků |
| mateřský jazyk | vždy čeština | `--z`, uložené nastavení, jinak jazyk rozhraní |
| rozhraní | česky v kódu | `locale/<kód>.tsv`, funkce `_t` |
| neznámá slovíčka | `neznama_<jazyk>.txt` (řádky) | `neznama/<mateřský>-<cíl>.txt` (id pojmů) |
| generátor | `generuj-fraze-claude.py` (jen věty) | `generuj-claude.py slova` a `vety` |

## 53. Od dvojic k pojmům

Původní slovníky nebyly propojené: němčina a italština měly každá svůj seznam ~3
000 hesel. Pro dvojici němčina → španělština by ke slovu `der Schlüssel` nebylo
jak najít `la llave`. Řešením je **tabulka pojmů**: jeden řádek = jeden význam,
sloupec = jazyk.

```
id	cs	de	en	it	fr	es	ru
o00177	klíč	der Schlüssel	the key	la chiave	la clé	la llave	ключ
```

Převod (`nastroje/migrace-pojmy.py`) spojil hesla podle **českého významu** – to
je jediné, co měly všechny slovníky společné:

```python
def klic(cs: str) -> str:
    return " ".join(cs.split()).lower()        # „Klíč “ i „klíč“ → stejný pojem
```

Výsledek ukázal, jak málo se slovníky překrývaly: ze ~3 000 hesel na jazyk mělo
všech šest jazyků společných jen **1 606** pojmů, dohromady jich vzniklo **5
031**. Každému jazyku tak chybělo ~2 000 slov – ta doplnil generátor (kapitola
59).

> **Česká věta zdarma.** Čeština jako cílový jazyk potřebuje české věty. Ty už
> existovaly: český *překlad* italské věty je česká věta a italská věta je pak
> její překlad. Převod proto pro `fraze/obecne-cs.tsv` jen přehodil sloupce a
> čeština měla věty ke všem 5 031 pojmům, aniž by se cokoli generovalo.

> ⚠️ **Slabé místo:** podle přesného textu se nespojí blízké významy („zatímco“
> a „zatímco / během“ jsou dva pojmy). Ve slovníku tak zůstalo pár téměř
> stejných hesel. Pro procvičování to nevadí, jen se občas stejné slovo objeví
> dvakrát.

## 54. Trik: starý formát řádku v paměti

Zbytek skriptů (kolo, neznámá slovíčka, označení věty) pracoval s řádky `cizí —
česky`. Místo přepisování všeho si `_nacti_slovnik` z tabulky pojmů **vyrobí
řádky ve starém formátu** pro zvolenou dvojici – a k nim převodní tabulky na id:

*spolecne.sh · _sloupce, _nacti_slovnik*

```bash
_sloupce() {
    [[ -f "$1" ]] || return 0
    awk -F'\t' -v a="$2" -v b="$3" '
        NR == 1 { for (i = 1; i <= NF; i++) sl[$i] = i; next }
        { printf "%s\t%s\t%s\n", $1, $(sl[a]), $(sl[b]) }' "$1"
}

_nacti_slovnik() {
    …
    while IFS=$'\t' read -r id slovo preklad; do
        radek="$slovo — $preklad"
        RADKY+=("$radek")
        RADEK_ID["$radek"]="$id"
        ID_RADEK["$id"]="$radek"
    done < <(_sloupce "$ADRESAR_SLOVNIKU/$(_sada "$1").tsv" "$kod" "$ZDROJ" | awk -F'\t' '$2 != "" && $3 != ""')
}
```

- **Sloupec podle názvu, ne podle čísla.** `awk` si v prvním řádku (`NR == 1`)
  zapamatuje, ve kterém sloupci je který jazyk (`sl["de"] = 3`), a pak vypisuje
  `$(sl[a])`. Přidání nového jazyka nebo přehození sloupců nic nerozbije.
- **Druhý `awk`** zahodí pojmy, kterým chybí slovo v jednom z jazyků (`$2 != ""
  && $3 != ""`).
- **`RADEK_ID` a `ID_RADEK`** jsou asociativní pole v obou směrech. Kód, který
  dřív ukládal řádky, teď přes ně ukládá id: neznámá slovíčka jsou v souboru
  jako `o01117`, takže přežijí i opravu slova ve slovníku.

> **Proč `< <( … )` a ne roura:** `while … done < <(prikaz)` běží v hlavním
> shellu, takže pole `RADKY` a spol. po smyčce existují. S rourou (`prikaz |
> while …`) by smyčka běžela v podshellu a pole by se ztratila (viz kapitola 7).

Věty se načítají stejně – `_sloupce` vybere sloupec cílového jazyka (věta) a
mateřského (překlad) a přes `ID_RADEK` je přiřadí ke správnému řádku.

## 55. Texty rozhraní: `_t` a printf

*spolecne.sh · _nacti_texty, _t*

```bash
_nacti_texty() {
    local f k v
    TEXTY=()
    for f in "$CESTA_SLOVNIKU/locale/en.tsv" "$CESTA_SLOVNIKU/locale/$LOCALE.tsv"; do
        [[ -f "$f" ]] || continue
        while IFS=$'\t' read -r k v; do
            [[ -z "$k" || "$k" == \#* ]] && continue
            TEXTY["$k"]="$v"
        done < "$f"
    done
}

_t() {
    local klic="$1"; shift
    # shellcheck disable=SC2059  # formát je text rozhraní z locale/*.tsv
    printf -- "${TEXTY[$klic]:-$klic}" "$@"
}
```

- **Záloha v angličtině:** nejdřív se načte `en.tsv`, pak zvolený jazyk ho
  přepíše. Chybí-li klíč v překladu, zůstane anglický text; chybí-li i ten,
  vypíše se aspoň název klíče (`${TEXTY[$klic]:-$klic}`).
- **Text je printf formát:** `kolo.znam` je `Znám: %s/%s`, volá se `_t kolo.znam
  12 30`. Pořadí `%s` je v každém jazyce stejné, slova kolem se mohou lišit.
  (Ruské `слов: %s` má číslo na konci – proto je `%s` v textu, ne přilepené
  zvenku.)
- **`printf --`:** dvojitá pomlčka chrání před textem, který začíná `-` – printf
  by ho jinak bral jako volbu.
- **SC2059:** shellcheck varuje před proměnnou ve formátu, protože `%` v datech
  by se interpretovalo. Tady je formát záměrně text rozhraní, data jdou jen přes
  `%s`. Proto `disable` s komentářem, proč.

> **Chyták: nové řádky.** Text `Slovíček: %s\nPořadí: %s` obsahuje `\n`. Printf
> ho ve formátu převede na skutečný konec řádku. Jenže `_view` posílá oknu jeden
> příkaz na řádek a dřív konce řádků nahrazoval mezerou – zpráva se slila do
> jednoho řádku. Oprava: `_view` teď skutečné konce řádků posílá jako dvojznak
> `\n` a okno je převede zpět.
>
> ```bash
> printf '%s\n' "${*//$'\n'/\\n}" >&"$VIEW_FD"
> ```

Texty se nepíšou ručně do sedmi souborů. Zdroj je `nastroje/texty-rozhrani.py`:
slovník `klíč → (cs, de, en, it, fr, es, ru)`. Skript ověří, že má každý klíč
všech sedm překladů a že v nich není tabulátor, a soubory vygeneruje. Okno v
Pythonu čte stejné soubory (funkce `t()`), takže jedna úprava platí všude.

## 56. Odkud se vezme jazyk

*spolecne.sh · _vychozi_locale*

```bash
_vychozi_locale() {
    local l
    for l in "${SLOVICKA_LOCALE:-}" "$(_nastaveni_cti locale)" "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
        l="${l:0:2}"
        _je_kod "$l" && { printf '%s' "$l"; return; }
    done
    printf 'en'
}
```

Smyčka prochází kandidáty od nejsilnějšího a vrátí první, který je platný kód
jazyka. `${l:0:2}` vezme první dva znaky: z `cs_CZ.UTF-8` udělá `cs`, z
`C.UTF-8` udělá `C.` – a ten neprojde `_je_kod`, takže se pokračuje dál.

> **Chyták z praxe:** autor má v systému `LANG=en_US.UTF-8` a česky jen formáty
> data (`LC_TIME=cs_CZ`). Po přestavbě by mu rozhraní i mateřský jazyk naskočily
> anglicky. Proto existuje uložené nastavení (`~/.config/slovicka/nastaveni`) a
> má přednost před `LANG`. Ověřit si to jde jedním příkazem: `locale | grep -E
> 'LANG|LC_MESSAGES'`.

Nastavení je obyčejný soubor `klic=hodnota`. Čte se `sed -n "s/^zdroj=//p"` a
zapisuje přes dočasný soubor (`grep -v` starý řádek + nový řádek → `mv`), stejně
jako neznámá slovíčka – soubor nikdy nezůstane napůl zapsaný.

## 57. Nabídka, která mění nastavení

Položky **💬 Můj jazyk** a **🌐 Jazyk rozhraní** jsou v téže nabídce jako jazyky.
Po jejich změně se má nabídka ukázat znovu – už v novém jazyce. To má háček:

*spolecne.sh · _vyber_cil*

```bash
_vyber_cil() {
    local volba
    while :; do
        volba=$(_vyber_jazyk) || exit $?
        [[ -z "$volba" ]] && exit 0
        if [[ "$volba" == "nastaveni" ]]; then
            _nastav_jazyky "$(_nastaveni_cti zdroj)" "$(_nastaveni_cti locale)"
            continue
        fi
        VYBRANY_CIL="$volba"
        return 0
    done
}
```

`_vyber_jazyk` běží v `$( )`, tedy v podshellu – nemůže změnit `ZDROJ` ani
`LOCALE` hlavního skriptu. Proto nastavení **uloží do souboru** a vrátí smluvené
slovo `nastaveni`. Smyčka pak nastavení přečte, přenačte texty a nabídku zobrazí
znovu. A protože i `_vyber_cil` mění globální proměnné, volá se **bez** `$( )` a
výsledek předává v proměnné `VYBRANY_CIL`.

*spolecne.sh · _volba_z*

```bash
_volba_z() {
    local volba="$1"; shift
    [[ -z "$volba" ]] && exit 0
    if [[ "$volba" =~ ^[0-9]+$ ]] && (( volba >= 1 && volba <= $# )); then
        printf '%s' "${!volba}"
    …
}
```

Nabídka vrací číslo položky. `${!volba}` je **nepřímá expanze**: když `volba=3`,
znamená to `$3`, tedy třetí argument funkce. Jedna funkce tak převede číslo na
klíč pro jakýkoli seznam: `_volba_z "$cislo" "${JAZYKY[@]}"`.

## 58. Společné volby a tři návratové kódy

Volby `--z` a `--locale` mají oba skripty. Aby se nekopírovaly, zpracuje je
`_spolecna_volba` – jenže volba s hodnotou spotřebuje **dva** argumenty a
volající to musí vědět. Řeší to návratový kód:

```bash
_spolecna_volba() {
    case "$1" in
        --z|--from|-f)
            _je_kod "${2:-}" || _chyba "$(_t chyba.jazyk "${2:-}" "${JAZYKY[*]}")"
            _nastav_jazyky "$2" ""; return 2 ;;
        …
    esac
    return 1                      # není moje volba
}

# ve smyčce voleb:
_spolecna_volba "${args[i]}" "${args[i+1]:-}"
kod=$?
if (( kod == 2 )); then (( i += 2 )); continue; fi
```

Návratový kód nemusí znamenat jen úspěch a chybu – `2` tu znamená „zpracováno,
přeskoč dva argumenty“, `1` „není moje, zpracuj sám“. Proto taky smyčka přes
index (`while (( i < ${#args[@]} ))`), ne `for arg in "$@"` – ten neumí
přeskočit hodnotu volby.

## 59. Generátor ve dvou krocích

`generuj-claude.py` doplňuje jen to, co chybí, ve dvou krocích, protože druhý
potřebuje výsledek prvního:

1. **`slova`** – pojmům doplní chybějící slova. Model dostane k pojmu český
   význam, už známé překlady (pomáhají rozlišit význam) a seznam jazyků, které
   chybí.
2. **`vety`** – ke každému pojmu v každém cílovém jazyce: chybí-li věta, napíše
   ji; chybí-li překlady, přeloží ji. Věta v cílovém jazyce potřebuje slovo v
   tom jazyce – proto až po kroku 1.

**Styl z dat, ne z popisu.** Místo dlouhého vysvětlování („německá podstatná
jména se členem, anglická slovesa s *to*…“) zadání obsahuje pár náhodných
existujících hesel každého jazyka. Model zvyklosti okopíruje – i ruské vidové
dvojice (`делать / сделать`).

```python
def ukazky_stylu(pojmy: list[dict], jazyk: str, pocet: int = 8) -> str:
    s_jazykem = [p for p in pojmy if p.get(jazyk)]
    nahodne = random.Random(jazyk).sample(s_jazykem, min(pocet, len(s_jazykem)))
    return "; ".join(f"{p['cs']} → {p[jazyk]}" for p in nahodne)
```

`random.Random(jazyk)` je generátor se **semínkem**: pro stejný jazyk vybere
vždy stejné ukázky, takže se zadání mezi běhy nemění.

**JSON schéma se všemi poli.** Odpověď má pevné schéma, kde jsou povinná všechna
pole `cs … ru` a model vrací prázdný řetězec tam, kde nic nechceme. Jednodušší
než schéma pro každou kombinaci chybějících jazyků – a pár prázdných řetězců
stojí zanedbatelně tokenů.

**Nejdřív zkouška, pak rozhodnutí.** Odhad pro všech 7 mateřských jazyků vyšel
řádově jinak než první odhad z hlavy (~50 USD místo ~15 USD se Sonnetem, ~3 USD
s Haiku). Před ostrým během proto proběhla zkouška obou modelů na 8 větách
(`--limit 8`, za haléře) a rozhodnutí padlo podle skutečných výsledků, ne podle
dojmu.

## 60a. Gramatika (`--gr`): stejná kostra, jiná data

Nový režim nepotřeboval nový skript. Kolo, klávesy, čtení na pozadí i ukládání
neznámých pracují s „řádky“ a jejich `id`, takže `_nacti_gramatiku` jen naplní
`RADKY` identifikátory vět a `RADEK_ID` / `ID_RADEK` jako identitu
(`RADEK_ID[g001]=g001`). Zbytek se liší jen na třech místech: `_zobraz_slovicko`
a `_precti_znovu` se na začátku větví podle `GR` a `_soubor_neznamych` přidá
příponu `-gr`. Věta s větvením na začátku funkce (`if … ; then _zobraz_gramatiku
…; return; fi`) je nejlevnější způsob, jak do hotové funkce přidat režim bez
přepisování.

Data jsou asociativní pole podle `id` (`GR_TVAR`, `GR_ZDROJ`, `GR_CIL`,
`GR_DOSL`), načtená smyčkou `while IFS=$'\t' read -r …` – stejný vzor jako u
slovníku. Doslovný překlad se pro čtení čistí přes `sed -E` (značky pádů a
závorky pryč). Cíl se bez zadání vybere z existujících souborů
`gramatika/*-<zdroj>.tsv` (`_gr_cile`): jediný možný se vezme rovnou, víc
možností → nabídka.

Čtení doslovného překladu (`_gr_dosl_tts`) čistí značky jedním regexem
`s/([^[:space:].])(\.[[:alpha:]äöüß]+)+/\1/g`: tečka s písmeny hned za
neprázdným znakem je značka (`bought.pp`, `[the].dat`), `…` a konec věty (tečka
za mezerou nebo bez písmen) zůstanou. Dřívější seznam značek (`.acc|.dat|…`)
jich spoustu nezachytil (`.fut .cond .subj .ser .ä`) a TTS je četl nahlas;
záchyt jen po písmeni (`[[:alpha:]]`) zase míjel `[the].dat`. Nový regex je
obecný, takže další jazyk nevyžaduje úpravu kódu.

## 60. Cvičení k části 5

<details><summary><b>1. Nový jazyk: polština</b></summary>

*procvičíš: awk, asociativní pole, práce s TSV*

Přidej polštinu (`pl`). Co všechno se musí změnit?

1. `spolecne.sh`: `JAZYKY+=(pl)`, `VLAJKY[pl]="🇵🇱"`,
   `TTS_MODELY[pl]=…pl_PL-gosia-medium.onnx`.
2. Sloupec `pl` do všech `slovnik/*.tsv` a `fraze/*.tsv`:
   ```bash
   for f in slovnik/*.tsv fraze/*.tsv; do
       awk -F'\t' -v OFS='\t' 'NR == 1 { print $0, "pl"; next } { print $0, "" }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
   done
   ```
3. `generuj-claude.py`: `JAZYKY` a `NAZEV["pl"] = "Polish"`, pak
   `./generuj-claude.py slova` a `vety`.
4. `nastroje/texty-rozhrani.py`: ke každému klíči osmý překlad – nebo zatím nic
   a polské rozhraní bude anglicky (záloha z `en.tsv`).

Díky čtení sloupců podle hlavičky (kapitola 54) se kód načítání nemění vůbec.

</details>

<details><summary><b>2. Statistika pokrytí</b></summary>

*procvičíš: awk, pole v awk*

Vypiš, kolik pojmů má v každém jazyce slovo a kolik vět:

```bash
awk -F'\t' 'NR == 1 { for (i = 2; i <= NF; i++) jm[i] = $i; next }
            { for (i = 2; i <= NF; i++) if ($i != "") n[i]++ }
            END { for (i = 2; i in jm; i++) printf "%s %d\n", jm[i], n[i] }' slovnik/obecne.tsv
for f in fraze/obecne-*.tsv; do printf '%s %d\n' "$f" $(( $(wc -l < "$f") - 1 )); done
```

`i in jm` ukončí smyčku, když sloupec s tímhle číslem v hlavičce neexistuje.

</details>

<details><summary><b>3. Nabídka bez podshellu</b></summary>

*procvičíš: podshelly, globální proměnné*

`_vyber_jazyk` vrací výsledek přes `$( )` a nastavení předává souborem (kapitola
57). Přepiš ho tak, aby výsledek ukládal do globální proměnné a volal se bez `$(
)`. Co se pak musí změnit v `_vyber`, která sama běží v `$( )` kvůli zachycení
výstupu GTK nabídky?

Stačí, když `_vyber` vrací číslo přes proměnnou a výstup nabídky zachytí uvnitř:
`vystup=$(uv run … --vyber …)`. Ze všech funkcí kolem nabídek pak zmizí
podshelly a nastavení může jít rovnou do `ZDROJ` / `LOCALE` – soubor zůstane jen
kvůli zapamatování na příště.

</details>

---

*Stav skriptů k 24. 11. 2026 · část 1: původní verze · část 2: opravy · část 3:
fráze a ovládání klávesami · část 4: GTK, intro, libovolný Wayland · část 5:
učení napříč sedmi jazyky*
