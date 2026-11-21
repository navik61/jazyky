# shellcheck shell=bash
# Proměnné se používají ve skriptech, které soubor načítají:
# shellcheck disable=SC2034
# ================================================================
# spolecne.sh — sdílený kód pro slovicka-pasivni.sh a slovicka-interaktivni.sh
# Nespouští se samostatně, načítá se přes:  source "$CESTA_SLOVNIKU/spolecne.sh"
# Očekává, že volající skript už nastavil SKRIPT a CESTA_SLOVNIKU.
# ================================================================

# ── Konfigurace ─────────────────────────────────────────────────
readonly PIPER="$HOME/.local/share/uv/tools/piper-tts/bin/piper"
readonly PIPER_MODELY="$HOME/.local/share/piper"
readonly TTS_SPEED="0.85"

# Titulek okna kitty, podle něj se okno hledá (pgrep/pkill -f)
readonly OKNO_NAZEV="kitty-float-slovicka"
# Rozměry musí odpovídat pravidlu app-id "kitty-float" v niri config.kdl
readonly OKNO_SIRKA=820
readonly OKNO_VYSKA=380

# 1 = skript běží uvnitř plovoucího okna (nastavuje _spust_v_okne)
readonly V_OKNE="${SLOVICKA_V_OKNE:-0}"

# Vzorové fráze: fraze/<slovník>.tsv, řádek = <řádek slovníku> TAB <fráze> TAB <překlad>
# (generuje generuj-fraze.py)
readonly ADRESAR_FRAZI="$CESTA_SLOVNIKU/fraze"
# Fráze označené klávesou [x] jako chybné — k pozdější opravě
readonly SOUBOR_CHYBNYCH="$ADRESAR_FRAZI/chybne.tsv"
declare -A FRAZE=()
declare -A FRAZE_CS=()

# Pořadí určuje i pořadí v nabídce
readonly JAZYKY=(de en it de_golf en_golf it_golf)

declare -A SOUBORY=(
    [de]="$CESTA_SLOVNIKU/nemcina_slova.txt"
    [en]="$CESTA_SLOVNIKU/anglictina_slova.txt"
    [it]="$CESTA_SLOVNIKU/italstina_slova.txt"
    [de_golf]="$CESTA_SLOVNIKU/golf_nemcina.txt"
    [en_golf]="$CESTA_SLOVNIKU/golf_anglictina.txt"
    [it_golf]="$CESTA_SLOVNIKU/golf_italstina.txt"
)

declare -A NAZVY=(
    [de]="🇩🇪 Němčina"
    [en]="🇬🇧 Angličtina"
    [it]="🇮🇹 Italština"
    [de_golf]="🇩🇪 Němčina Golf"
    [en_golf]="🇬🇧 Angličtina Golf"
    [it_golf]="🇮🇹 Italština Golf"
)

declare -A VLAJKY=(
    [de]="🇩🇪"
    [en]="🇬🇧"
    [it]="🇮🇹"
    [de_golf]="🇩🇪"
    [en_golf]="🇬🇧"
    [it_golf]="🇮🇹"
)

declare -A TTS_MODELY=(
    [de]="$PIPER_MODELY/de_DE-thorsten-medium.onnx"
    [en]="$PIPER_MODELY/en_US-lessac-medium.onnx"
    [it]="$PIPER_MODELY/it_IT-riccardo-x_low.onnx"
    [cs]="$PIPER_MODELY/cs_CZ-jirka-medium.onnx"
)

declare -A TTS_JAZYK=(
    [de]="de"
    [en]="en"
    [it]="it"
    [cs]="cs"
    [de_golf]="de"
    [en_golf]="en"
    [it_golf]="it"
)

# Rozpracovaný mp3 soubor edge-tts; globální, aby ho uklidil i trap při Ctrl+C
TMP_MP3=""

# ── Pomocné funkce ──────────────────────────────────────────────

# Je $1 platný klíč jazyka?
_je_jazyk() {
    local j
    for j in "${JAZYKY[@]}"; do
        [[ "$1" == "$j" ]] && return 0
    done
    return 1
}

# Výpis jazyků pro nápovědu: "de, en, it, de_golf, en_golf, it_golf"
_seznam_jazyku() {
    local IFS=","
    printf '%s' "${JAZYKY[*]}" | sed 's/,/, /g'
}

# Chybová hláška do terminálu, a když terminál není (rofi), i jako notifikace
_chyba() {
    echo -e "\e[1;31mChyba: $1\e[0m" >&2
    [[ -t 0 ]] || notify-send -u critical "Slovíčka" "$1" 2>/dev/null
    exit 1
}

# Vypíše text zalomený podle šířky terminálu, s odsazením a barvou
# _vypis_zalomene $'\e[1;33m' "text"
_vypis_zalomene() {
    local barva="$1" text="$2" sirka radek
    sirka=$(( $(tput cols 2>/dev/null || echo 80) - 4 ))
    (( sirka < 20 )) && sirka=20
    while IFS= read -r radek; do
        printf '%s  %s\e[0m\n' "$barva" "$radek"
    done < <(printf '%s\n' "$text" | fold -s -w "$sirka")
}

# ── Vzorové fráze ───────────────────────────────────────────────
_soubor_frazi() {
    local slovnik="${SOUBORY[$1]}"
    printf '%s/%s.tsv' "$ADRESAR_FRAZI" "$(basename "$slovnik" .txt)"
}

# Načte fráze jazyka do FRAZE / FRAZE_CS (klíč = celý řádek slovníku).
# Chybějící soubor nevadí — slovíčka se pak zobrazí bez frází.
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

# Označí frázi slovíčka jako chybnou (klávesa [x]).
# Řádek: <soubor frází> TAB <řádek slovníku> TAB <fráze> TAB <překlad>, bez duplicit.
# Vrací 1, když slovíčko frázi nemá.
_oznac_chybnou() {
    local jazyk="$1" radek="$2" soubor
    [[ -n "${FRAZE[$radek]:-}" ]] || return 1
    soubor=$(basename "$(_soubor_frazi "$jazyk")")
    { cat "$SOUBOR_CHYBNYCH" 2>/dev/null
      printf '%s\t%s\t%s\t%s\n' "$soubor" "$radek" "${FRAZE[$radek]}" "${FRAZE_CS[$radek]:-}"
    } | sort -u > "$SOUBOR_CHYBNYCH.tmp" && mv -f "$SOUBOR_CHYBNYCH.tmp" "$SOUBOR_CHYBNYCH"
}

# ── Plovoucí okno ───────────────────────────────────────────────
# Spustí tentýž skript v plovoucím okně kitty (odpojeně od terminálu),
# aby klávesy fungovaly přímo v okně se slovíčky.
_spust_v_okne() {
    _zjisti_pozici_okna
    SLOVICKA_V_OKNE=1 setsid -f kitty \
        --class kitty-float \
        --title "$OKNO_NAZEV" \
        --override font_size=16 \
        --override background_opacity=0.92 \
        --override window_padding_width=24 \
        "$SKRIPT" "$@" </dev/null &>/dev/null
    sleep 0.8
    niri msg action move-floating-window --x "$OKNO_X" --y "$OKNO_Y" 2>/dev/null || true
    echo -e "\e[0;90mBěží v plovoucím okně ([q] v okně = konec).\e[0m"
}

# Lze otevřít okno? (kitty + grafická relace, a skript ještě neběží v okně)
_lze_otevrit_okno() {
    [[ "$V_OKNE" == "0" ]] && command -v kitty &>/dev/null \
        && [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]
}

_okno_zavrit() {
    # Uvnitř okna nic nezabíjet — okno se zavře samo s koncem skriptu
    [[ "$V_OKNE" == "1" ]] && return 0
    pkill -f "$OKNO_NAZEV" 2>/dev/null || true
}

# ── Pozice okna (střed aktivního monitoru) ──────────────────────
_zjisti_pozici_okna() {
    local vystup log_w log_h
    vystup=$(niri msg focused-output 2>/dev/null)
    log_w=$(echo "$vystup" | awk '/Logical size:/ {split($3,a,"x"); print a[1]}')
    log_h=$(echo "$vystup" | awk '/Logical size:/ {split($3,a,"x"); print a[2]}')
    log_w=${log_w:-1920}
    log_h=${log_h:-1080}

    OKNO_X=$(( (log_w - OKNO_SIRKA) / 2 ))
    OKNO_Y=$(( (log_h - OKNO_VYSKA) / 2 ))
}

# ── TTS ─────────────────────────────────────────────────────────
_uklid_tts() {
    [[ -n "$TMP_MP3" ]] && rm -f "$TMP_MP3"
    TMP_MP3=""
}

# _tts_reci "text" jazyk   — jazyk: cs nebo klíč z JAZYKY
_tts_reci() {
    local text="$1"
    local jazyk="$2"
    local tts_jazyk="${TTS_JAZYK[$jazyk]:-$jazyk}"
    local model="${TTS_MODELY[$tts_jazyk]:-}"
    local prvni=1 cast vzorkovani

    # Piper vydává holá data bez hlavičky — frekvence je v <model>.onnx.json
    vzorkovani=$(grep -o '"sample_rate": *[0-9]*' "$model.json" 2>/dev/null | grep -o '[0-9]*$')
    vzorkovani=${vzorkovani:-22050}

    # Rozdělit na části podle "/" (např. "dům / budova") a přečíst každou zvlášť
    while IFS= read -r cast; do
        # Oříznout všechny mezery a tabulátory na obou koncích
        cast="${cast#"${cast%%[![:space:]]*}"}"
        cast="${cast%"${cast##*[![:space:]]}"}"
        [[ -z "$cast" ]] && continue

        [[ "$prvni" == "0" ]] && sleep 0.5
        prvni=0

        # Čeština — edge-tts (přirozenější hlas, potřebuje internet)
        if [[ "$jazyk" == "cs" ]]; then
            TMP_MP3=$(mktemp /tmp/tts_XXXXXX.mp3)
            edge-tts --voice cs-CZ-AntoninNeural \
                --text "$cast" \
                --write-media "$TMP_MP3" 2>/dev/null \
            && mpv --really-quiet --no-video --no-input-terminal "$TMP_MP3" 2>/dev/null
            _uklid_tts
            continue
        fi

        # Ostatní jazyky — Piper, bez modelu záložně espeak-ng
        if [[ ! -f "$model" ]]; then
            if command -v espeak-ng &>/dev/null; then
                espeak-ng -v "$tts_jazyk" -s 130 "$cast" 2>/dev/null
            else
                echo "[TTS model nenalezen: $model]" >&2
            fi
            continue
        fi

        printf '%s\n' "$cast" | "$PIPER" \
            --model "$model" \
            --length_scale "$TTS_SPEED" \
            --output-raw 2>/dev/null \
            | ffmpeg -f s16le -ar "$vzorkovani" -ac 1 -i pipe: \
                     -ar 48000 -ac 2 \
                     -f wav pipe:1 2>/dev/null \
            | mpv --really-quiet --no-video --no-input-terminal - 2>/dev/null

    done < <(printf '%s\n' "$text" | tr '/' '\n')
}

# ── Neznámá slovíčka ────────────────────────────────────────────
# Soubor neznama_<jazyk>.txt ve stejném formátu jako slovníky

_soubor_neznamych() {
    printf '%s/neznama_%s.txt' "$CESTA_SLOVNIKU" "$1"
}

# _neznama_pridej jazyk "radek" ...   — přidá řádky (bez duplicit)
_neznama_pridej() {
    local f
    f=$(_soubor_neznamych "$1"); shift
    (( $# )) || return 0
    { cat "$f" 2>/dev/null; printf '%s\n' "$@"; } | sort -u > "$f.tmp" \
        && mv -f "$f.tmp" "$f"
}

# _neznama_odeber jazyk "radek" ...   — odebere řádky; prázdný soubor smaže
_neznama_odeber() {
    local f
    f=$(_soubor_neznamych "$1"); shift
    (( $# )) && [[ -f "$f" ]] || return 0
    grep -vxF -f <(printf '%s\n' "$@") "$f" > "$f.tmp"
    mv -f "$f.tmp" "$f"
    [[ -s "$f" ]] || rm -f "$f"
}

# ── Nabídky (terminál nebo rofi) ────────────────────────────────

# Výběr z nabídky: v terminálu číslem, bez terminálu (rofi) přes rofi -dmenu.
# Vypíše pořadové číslo zvolené položky (1..N), při zrušení nic.
_vyber() {
    local vyzva="$1"; shift
    if [[ -t 0 ]]; then
        echo -e "\n\e[1;34m$vyzva\e[0m" >&2
        local n=1 polozka
        for polozka in "$@"; do printf '  %d) %s\n' "$n" "$polozka" >&2; (( ++n )); done
        echo -n "Volba [1-$#, Enter=1]: " >&2
        local volba; read -r volba
        echo "${volba:-1}"
    else
        printf '%s\n' "$@" | rofi -dmenu -i -no-custom -format d -p "$vyzva"
    fi
}

# Vypíše klíč jazyka, u uložených neznámých slovíček "neznama:<klíč>".
# Esc v rofi = konec skriptu.
_vyber_jazyk() {
    local -a klice=() polozky=()
    local j f n volba
    for j in "${JAZYKY[@]}"; do
        klice+=("$j"); polozky+=("${NAZVY[$j]}")
    done
    for j in "${JAZYKY[@]}"; do
        f=$(_soubor_neznamych "$j")
        [[ -s "$f" ]] || continue
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
}

# Vypíše 0 (originál první) nebo 1 (česky první)
_vyber_poradi() {
    local volba
    volba=$(_vyber "Pořadí" "Originál → Česky" "Česky → Originál")
    case "$volba" in
        1) echo "0" ;;
        2) echo "1" ;;
        "") exit 0 ;;
        *) _chyba "Neplatná volba: $volba" ;;
    esac
}
