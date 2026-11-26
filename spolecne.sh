# shellcheck shell=bash
# Proměnné se používají ve skriptech, které soubor načítají:
# shellcheck disable=SC2034
# ================================================================
# spolecne.sh — sdílený kód pro slovicka-pasivni.sh a slovicka-interaktivni.sh
# Nespouští se samostatně, načítá se přes:  source "$CESTA_SLOVNIKU/spolecne.sh"
# Očekává, že volající skript už nastavil SKRIPT a CESTA_SLOVNIKU.
# ================================================================

# ── Konfigurace ─────────────────────────────────────────────────
# Bez grafické proměnné (tty, ssh, terminál mimo relaci) zkusit najít běžící Wayland socket,
# aby se otevřelo okno místo textového režimu. Vyloučené: SLOVICKA_V_TERMINALU=1.
if [[ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" && "${SLOVICKA_V_TERMINALU:-0}" != "1" ]]; then
    for _sock in "${XDG_RUNTIME_DIR:-/run/user/$UID}"/wayland-[0-9]*; do
        if [[ -S "$_sock" ]]; then
            WAYLAND_DISPLAY="${_sock##*/}"; export WAYLAND_DISPLAY
            export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
            break
        fi
    done
    unset _sock
fi

# Piper (TTS): SLOVICKA_PIPER, jinak instalace přes `uv tool install piper-tts`, jinak piper z PATH.
# Pozor: na některých distribucích je „piper“ i nástroj na herní myši — proto má uv přednost.
_najdi_piper() {
    local p
    for p in "${SLOVICKA_PIPER:-}" "$HOME/.local/share/uv/tools/piper-tts/bin/piper" \
             "$HOME/.local/bin/piper" "$(command -v piper 2>/dev/null)"; do
        [[ -n "$p" && -x "$p" ]] && { printf '%s' "$p"; return; }
    done
}
PIPER=$(_najdi_piper)
readonly PIPER
# Hlasy Piperu (<jazyk>.onnx + .onnx.json)
readonly PIPER_MODELY="${SLOVICKA_PIPER_MODELY:-${XDG_DATA_HOME:-$HOME/.local/share}/piper}"
readonly TTS_SPEED="0.85"

# Zvuk na pozadí po celou dobu procvičování — drží Bluetooth reproduktor vzhůru,
# aby neuřízl začátek krátkých slov.
#   SLOVICKA_POZADI = sum (výchozí, tichý šum) | ne (vypnuto) | cesta ke zvukovému souboru (smyčka)
#   SLOVICKA_SUM_BARVA = white | pink | brown (výchozí white), SLOVICKA_SUM_UROVEN = amplituda (výchozí 0.003)
#   SLOVICKA_POZADI_HLASITOST = hlasitost souboru 0–100 (výchozí 25)
POZADI_PID=""

# 0 = skript běží v terminálu (spouštěč, nebo záložní režim bez grafické relace),
# 2 = v průhledném okně slovicka-view.py (nastavuje _spust_v_okne)
readonly V_OKNE="${SLOVICKA_V_OKNE:-0}"
# Průhledné okno: deskriptor, na který se posílají příkazy pro slovicka-view.py
readonly VIEW_FD="${SLOVICKA_FD:-}"
readonly VIEW_PY="$CESTA_SLOVNIKU/slovicka-view.py"

# Aktivační token (xdg-activation na Waylandu, DESKTOP_STARTUP_ID na X11): bez něj GNOME/KDE
# otevřou nové okno na pozadí. Spouštěč (rofi, fuzzel…) ho předá v proměnné; každé GTK okno
# (nabídka) pak vydá token pro další okno. Předává se souborem, protože nabídky běží v $( ).
readonly TOKEN_SOUBOR="${XDG_RUNTIME_DIR:-/tmp}/slovicka-aktivace.$$"
if [[ "$V_OKNE" == "0" && -n "${XDG_ACTIVATION_TOKEN:-}${DESKTOP_STARTUP_ID:-}" ]]; then
    printf '%s' "${XDG_ACTIVATION_TOKEN:-$DESKTOP_STARTUP_ID}" > "$TOKEN_SOUBOR"
fi
unset XDG_ACTIVATION_TOKEN DESKTOP_STARTUP_ID

# ── Jazyky ──────────────────────────────────────────────────────
# Každý jazyk může být mateřský (ZDROJ, volba --z) i cílový (co se učíš).
# Cílový „klíč“ je kód jazyka, u golfové terminologie <kód>_golf.
readonly JAZYKY=(cs de en it fr es ru)
declare -A VLAJKY=([cs]="🇨🇿" [de]="🇩🇪" [en]="🇬🇧" [it]="🇮🇹" [fr]="🇫🇷" [es]="🇪🇸" [ru]="🇷🇺")
declare -A TTS_MODELY=(
    [de]="$PIPER_MODELY/de_DE-thorsten-medium.onnx"
    [en]="$PIPER_MODELY/en_US-lessac-medium.onnx"
    [it]="$PIPER_MODELY/it_IT-riccardo-x_low.onnx"
    [fr]="$PIPER_MODELY/fr_FR-siwis-medium.onnx"
    [es]="$PIPER_MODELY/es_ES-davefx-medium.onnx"
    [ru]="$PIPER_MODELY/ru_RU-irina-medium.onnx"
    [cs]="$PIPER_MODELY/cs_CZ-jirka-medium.onnx"
)

# Data: slovnik/<sada>.tsv (pojmy: id cs de en it fr es ru), fraze/<sada>-<cíl>.tsv (paralelní věty)
readonly ADRESAR_SLOVNIKU="$CESTA_SLOVNIKU/slovnik"
readonly ADRESAR_FRAZI="$CESTA_SLOVNIKU/fraze"
readonly ADRESAR_NEZNAMYCH="$CESTA_SLOVNIKU/neznama"
# Fráze označené klávesou [x] jako chybné — k pozdější opravě
readonly SOUBOR_CHYBNYCH="$ADRESAR_FRAZI/chybne.tsv"

# Nastavení mezi spuštěními (mateřský jazyk, jazyk rozhraní): klic=hodnota
readonly SOUBOR_NASTAVENI="${XDG_CONFIG_HOME:-$HOME/.config}/slovicka/nastaveni"

# 1 = režim gramatiky (--gr): místo slovíček se procvičují gramatické tvary (gramatika/<cíl>-<zdroj>.tsv)
GR=0
readonly ADRESAR_GRAMATIKY="$CESTA_SLOVNIKU/gramatika"
# Gramatika podle id: název tvaru, věta v mateřském jazyce, věta v cílovém jazyce, doslovný překlad
declare -A GR_TVAR=() GR_ZDROJ=() GR_CIL=() GR_DOSL=()

# Načtený slovník: řádek „cílové slovo — slovo v mateřském jazyce“ ↔ id pojmu
declare -A RADEK_ID=() ID_RADEK=()
RADKY=()
# Vzorové věty podle řádku slovníku: věta v cílovém jazyce a její překlad do mateřského
declare -A FRAZE=() FRAZE_PREKLAD=()

# Rozpracovaný mp3 soubor edge-tts; globální, aby ho uklidil i trap při Ctrl+C
TMP_MP3=""

# ── Nastavení a texty rozhraní ──────────────────────────────────
_je_kod() {
    local j
    for j in "${JAZYKY[@]}"; do [[ "$1" == "$j" ]] && return 0; done
    return 1
}

_nastaveni_cti() {
    [[ -f "$SOUBOR_NASTAVENI" ]] || return 0
    sed -n "s/^$1=//p" "$SOUBOR_NASTAVENI" | tail -n1
}

_nastaveni_zapis() {
    mkdir -p "$(dirname "$SOUBOR_NASTAVENI")"
    { grep -v "^$1=" "$SOUBOR_NASTAVENI" 2>/dev/null; printf '%s=%s\n' "$1" "$2"; } \
        > "$SOUBOR_NASTAVENI.tmp" && mv -f "$SOUBOR_NASTAVENI.tmp" "$SOUBOR_NASTAVENI"
}

# Jazyk rozhraní: SLOVICKA_LOCALE > uložené nastavení > LC_ALL/LC_MESSAGES/LANG > angličtina
_vychozi_locale() {
    local l
    for l in "${SLOVICKA_LOCALE:-}" "$(_nastaveni_cti locale)" "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
        l="${l:0:2}"
        _je_kod "$l" && { printf '%s' "$l"; return; }
    done
    printf 'en'
}

LOCALE=$(_vychozi_locale)
# Mateřský jazyk: SLOVICKA_ZDROJ > uložené nastavení > jazyk rozhraní
ZDROJ="${SLOVICKA_ZDROJ:-$(_nastaveni_cti zdroj)}"
_je_kod "$ZDROJ" || ZDROJ="$LOCALE"

declare -A TEXTY=()
# Načte texty rozhraní: nejdřív angličtina (záloha pro chybějící klíče), pak LOCALE.
# Formát locale/<kód>.tsv: klíč TAB text (printf formát, \n = nový řádek)
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
    export SLOVICKA_LOCALE="$LOCALE"     # pro slovicka-view.py (nabídka, okno)
}

# _t klíč [argumenty…] — přeložený text (printf formát)
_t() {
    local klic="$1"; shift
    # shellcheck disable=SC2059  # formát je text rozhraní z locale/*.tsv
    printf -- "${TEXTY[$klic]:-$klic}" "$@"
}

# _nastav_jazyky zdroj locale — po volbách --z / --locale nebo po změně v nabídce
_nastav_jazyky() {
    _je_kod "${1:-}" && ZDROJ="$1"
    _je_kod "${2:-}" && LOCALE="$2"
    _nacti_texty
}
_nacti_texty

# Název jazyka v jazyce rozhraní; s vlajkou: _nazev_jazyka kód [vlajka]
_nazev_jazyka() {
    if [[ "${2:-}" == "vlajka" ]]; then
        printf '%s %s' "${VLAJKY[$1]}" "$(_t "jazyk.$1")"
    else
        _t "jazyk.$1"
    fi
}

# Kód jazyka a sada z cílového klíče (de_golf → de, golf)
_kod() { printf '%s' "${1%_golf}"; }
_sada() { if [[ "$1" == *_golf ]]; then printf 'golf'; else printf 'obecne'; fi; }

# Název cíle pro nabídku a titulek: „🇩🇪 Němčina“, „🇩🇪 Němčina Golf“
_nazev() {
    local n
    n=$(_nazev_jazyka "$(_kod "$1")" vlajka)
    [[ "$1" == *_golf ]] && n+=" $(_t golf)"
    printf '%s' "$n"
}

# Cílové klíče pro mateřský jazyk ZDROJ (všechny jazyky kromě něj, pak golf)
_cile() {
    local j
    for j in "${JAZYKY[@]}"; do [[ "$j" != "$ZDROJ" ]] && printf '%s\n' "$j"; done
    for j in "${JAZYKY[@]}"; do [[ "$j" != "$ZDROJ" ]] && printf '%s\n' "${j}_golf"; done
}

# Je $1 platný cílový klíč (cs, de_golf…)?
_je_jazyk() {
    _je_kod "$(_kod "$1")" && [[ "$1" == "$(_kod "$1")" || "$1" == "$(_kod "$1")_golf" ]]
}

# Výpis cílů pro nápovědu: "cs, de, en, …, de_golf, …"
_seznam_jazyku() {
    local -a c
    mapfile -t c < <(_cile)
    local IFS=","
    printf '%s' "${c[*]}" | sed 's/,/, /g'
}

# Chybová hláška do terminálu, a když terminál není (rofi), i jako notifikace
_chyba() {
    echo -e "\e[1;31m$(_t chyba "$1")\e[0m" >&2
    [[ -t 0 ]] || notify-send -u critical "$(_t app)" "$1" 2>/dev/null
    exit 1
}

# ── Slovník a věty ──────────────────────────────────────────────
# _nacti_slovnik cíl — RADKY / RADEK_ID / ID_RADEK pro dvojici cíl × ZDROJ.
# Pojmy bez slova v jednom z obou jazyků se přeskočí.
_nacti_slovnik() {
    local cil kod id slovo preklad radek
    kod=$(_kod "$1")
    RADKY=(); RADEK_ID=(); ID_RADEK=()
    while IFS=$'\t' read -r id slovo preklad; do
        radek="$slovo — $preklad"
        RADKY+=("$radek")
        RADEK_ID["$radek"]="$id"
        ID_RADEK["$id"]="$radek"
    done < <(_sloupce "$ADRESAR_SLOVNIKU/$(_sada "$1").tsv" "$kod" "$ZDROJ" | awk -F'\t' '$2 != "" && $3 != ""')
}

# _sloupce soubor.tsv sloupec1 sloupec2 — vypíše id a dva sloupce podle hlavičky
_sloupce() {
    [[ -f "$1" ]] || return 0
    awk -F'\t' -v a="$2" -v b="$3" '
        NR == 1 { for (i = 1; i <= NF; i++) sl[$i] = i; next }
        { printf "%s\t%s\t%s\n", $1, $(sl[a]), $(sl[b]) }' "$1"
}

_soubor_frazi() {
    printf '%s/%s-%s.tsv' "$ADRESAR_FRAZI" "$(_sada "$1")" "$(_kod "$1")"
}

# Načte věty cíle do FRAZE / FRAZE_PREKLAD (klíč = řádek slovníku; nejdřív _nacti_slovnik).
# Chybějící soubor nevadí — slovíčka se pak zobrazí bez vět.
_nacti_fraze() {
    local id veta preklad radek
    FRAZE=(); FRAZE_PREKLAD=()
    while IFS=$'\t' read -r id veta preklad; do
        radek="${ID_RADEK[$id]:-}"
        [[ -n "$radek" && -n "$veta" ]] || continue
        FRAZE["$radek"]="$veta"
        FRAZE_PREKLAD["$radek"]="$preklad"
    done < <(_sloupce "$(_soubor_frazi "$1")" "$(_kod "$1")" "$ZDROJ")
}

# Slovíčka k procvičení (řádky slovníku): _slovicka cíl [neznama]
_slovicka() {
    if [[ "${2:-}" == "neznama" ]]; then
        local id
        while IFS= read -r id; do
            [[ -n "${ID_RADEK[$id]:-}" ]] && printf '%s\n' "${ID_RADEK[$id]}"
        done < <(cat "$(_soubor_neznamych "$1")" 2>/dev/null)
    else
        printf '%s\n' "${RADKY[@]}"
    fi
}

# Označí větu slovíčka jako chybnou (klávesa [x]).
# Řádek: <sada>-<cíl> TAB <id> TAB <mateřský jazyk> TAB <věta> TAB <překlad>, bez duplicit.
# Vrací 1, když slovíčko větu nemá.
_oznac_chybnou() {
    local cil="$1" radek="$2"
    [[ -n "${FRAZE[$radek]:-}" ]] || return 1
    { cat "$SOUBOR_CHYBNYCH" 2>/dev/null
      printf '%s-%s\t%s\t%s\t%s\t%s\n' "$(_sada "$cil")" "$(_kod "$cil")" "${RADEK_ID[$radek]:-}" \
          "$ZDROJ" "${FRAZE[$radek]}" "${FRAZE_PREKLAD[$radek]:-}"
    } | sort -u > "$SOUBOR_CHYBNYCH.tmp" && mv -f "$SOUBOR_CHYBNYCH.tmp" "$SOUBOR_CHYBNYCH"
}

# Vypíše kartu slovíčka tak, aby se vešla do výšky terminálu (záložní režim bez okna;
# při přetečení by terminál odroloval a titulek s vlajkami zmizel). Poslední řádek je pro nápovědu.
# Prázdné řádky se vloží jen když je místo; v krajním případě se zkrátí věta (…).
# _vypis_kartu titulek nazev prvni druhy fraze preklad
_vypis_kartu() {
    local titulek="$1" nazev="$2" prvni="$3" druhy="$4" fraze="$5" fraze_cs="$6"
    local sirka vyska volno
    sirka=$(( $(tput cols 2>/dev/null || echo 80) - 4 ))
    (( sirka < 20 )) && sirka=20
    vyska=$(tput lines 2>/dev/null || echo 24)

    local -a r_prvni=() r_druhy=() r_fraze=() r_cs=()
    mapfile -t r_prvni < <(printf '%s\n' "$prvni" | fold -s -w "$sirka")
    mapfile -t r_druhy < <(printf '%s\n' "$druhy" | fold -s -w "$sirka")
    [[ -n "$fraze" ]] && mapfile -t r_fraze < <(printf '%s\n' "$fraze" | fold -s -w "$sirka")
    [[ -n "$fraze_cs" ]] && mapfile -t r_cs < <(printf '%s\n' "$fraze_cs" | fold -s -w "$sirka")

    # titulek + nápověda + obsah
    volno=$(( vyska - 2 - ${#r_prvni[@]} - ${#r_druhy[@]} - ${#r_fraze[@]} - ${#r_cs[@]} ))

    # Nevejde se → zkrátit nejdřív překlad věty, pak větu (poslední řádek s …)
    while (( volno < 0 && ${#r_cs[@]} > 1 )); do
        unset 'r_cs[-1]'; r_cs[-1]="${r_cs[-1]% } …"; (( ++volno ))
    done
    while (( volno < 0 && ${#r_fraze[@]} > 1 )); do
        unset 'r_fraze[-1]'; r_fraze[-1]="${r_fraze[-1]% } …"; (( ++volno ))
    done
    (( volno < 0 && ${#r_cs[@]} )) && { r_cs=(); (( ++volno )); }

    # Prázdné řádky podle priority: před větou, za titulkem, před nápovědou
    local mezera_fraze=0 mezera_titulek=0 mezera_konec=0
    if (( ${#r_fraze[@]} && volno > 0 )); then mezera_fraze=1; (( --volno )); fi
    if (( volno > 0 )); then mezera_titulek=1; (( --volno )); fi
    if (( volno > 0 )); then mezera_konec=1; (( --volno )); fi

    local radek
    printf '\e[0;90m%s  │  %s\e[0m\n' "$titulek" "$nazev"
    (( mezera_titulek )) && echo
    for radek in "${r_prvni[@]}"; do printf '\e[1;33m  %s\e[0m\n' "$radek"; done
    for radek in "${r_druhy[@]}"; do printf '\e[0;37m  %s\e[0m\n' "$radek"; done
    (( mezera_fraze )) && echo
    for radek in "${r_fraze[@]}"; do printf '\e[3;36m  %s\e[0m\n' "$radek"; done   # kurzíva, tyrkysová
    for radek in "${r_cs[@]}"; do printf '\e[0;90m  %s\e[0m\n' "$radek"; done
    (( mezera_konec )) && echo
    return 0
}

# ── Gramatika (--gr) ────────────────────────────────────────────
# gramatika/<cíl>-<zdroj>.tsv: id, tvar, věta v mateřském jazyce, věta v cílovém jazyce, doslovný překlad
# (slovo od slova v mateřském jazyce = způsob myšlení v cílovém jazyce). Zatím en↔cs.
_gr_soubor() {
    printf '%s/%s-%s.tsv' "$ADRESAR_GRAMATIKY" "$(_kod "$1")" "$ZDROJ"
}

# Cíle, pro které existují data gramatiky k mateřskému jazyku ZDROJ
_gr_cile() {
    local j
    for j in "${JAZYKY[@]}"; do
        [[ "$j" != "$ZDROJ" && -f "$(_gr_soubor "$j")" ]] && printf '%s\n' "$j"
    done
}

# Vypíše cíl gramatiky: jediný možný rovnou, jinak nabídka. Bez dat chyba.
_gr_vyber_cil() {
    local -a cile
    local j
    mapfile -t cile < <(_gr_cile)
    (( ${#cile[@]} )) || _chyba "$(_t gr.neni "$(_nazev_jazyka "$ZDROJ")")"
    if (( ${#cile[@]} == 1 )); then printf '%s' "${cile[0]}"; return; fi
    local -a polozky=()
    for j in "${cile[@]}"; do polozky+=("$(_nazev "$j")"); done
    _volba_z "$(_vyber "$(_t vyber.jazyk)" "${polozky[@]}")" "${cile[@]}"
}

# _nacti_gramatiku cíl — RADKY = id vět; RADEK_ID / ID_RADEK jsou identita,
# takže neznámá (neznama/<zdroj>-<cíl>-gr.txt) fungují stejně jako u slovíček.
_nacti_gramatiku() {
    local id tvar zdroj cil dosl
    RADKY=(); RADEK_ID=(); ID_RADEK=()
    GR_TVAR=(); GR_ZDROJ=(); GR_CIL=(); GR_DOSL=()
    [[ -f "$(_gr_soubor "$1")" ]] || return 0
    while IFS=$'\t' read -r id tvar zdroj cil dosl; do
        [[ -z "$id" || "$id" == id || "$id" == \#* ]] && continue
        RADKY+=("$id"); RADEK_ID["$id"]="$id"; ID_RADEK["$id"]="$id"
        GR_TVAR["$id"]="$tvar"; GR_ZDROJ["$id"]="$zdroj"; GR_CIL["$id"]="$cil"; GR_DOSL["$id"]="$dosl"
    done < "$(_gr_soubor "$1")"
}

# Doslovný překlad pro čtení: bez značek (.acc, .pf …), závorek a spojovníků
_gr_dosl_tts() {
    printf '%s' "$1" | sed -E 's/\.(nom|gen|dat|acc|voc|loc|ins|pf|impf|imp|pl|m|f|n|now|habitually|reflexive)\b//g; s/[][()]//g; s/[-_]/ /g'
}

# ── Průhledné okno ──────────────────────────────────────────────
# Spustí tentýž skript v průhledném okně slovicka-view.py (vzhled jako poznámky pozt),
# odpojeně od terminálu, aby klávesy fungovaly přímo v okně se slovíčky.
# slovicka-view.py běží přes `uv run --script` (PyGObject si uv nainstaluje sám).
# $1 = režim kláves (znaky = pasivní, radky = interaktivní), zbytek = argumenty skriptu
_spust_v_okne() {
    local rezim="$1"; shift
    _s_tokenem setsid -f uv run --quiet --script "$VIEW_PY" --rezim "$rezim" -- "$SKRIPT" "$@" \
        </dev/null &>/dev/null
    echo -e "\e[0;90m$(_t okno.bezi)\e[0m"
}

# Jde spustit GTK okno? (grafická relace — Wayland i X11 — a uv)
_lze_gtk() {
    [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" && -f "$VIEW_PY" ]] && command -v uv &>/dev/null
}

# Lze otevřít okno? (jde GTK, a skript ještě neběží v okně)
_lze_otevrit_okno() {
    [[ "$V_OKNE" == "0" ]] && _lze_gtk
}

# Spustí příkaz s aktivačním tokenem od předchozího okna (token se tím spotřebuje)
_s_tokenem() {
    local token=""
    if [[ -f "$TOKEN_SOUBOR" ]]; then
        token=$(<"$TOKEN_SOUBOR")
        rm -f "$TOKEN_SOUBOR"
    fi
    if [[ -z "$token" ]]; then
        "$@"
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        XDG_ACTIVATION_TOKEN="$token" "$@"
    else
        DESKTOP_STARTUP_ID="$token" "$@"
    fi
}

# Běží skript v průhledném okně?
_pruhledne() { [[ "$V_OKNE" == "2" && -n "$VIEW_FD" ]]; }

# Pošle příkaz průhlednému oknu (pole oddělená tabulátorem, viz slovicka-view.py):
#   _view KARTA hlavička první druhý věta překlad
#   _view NAPOVEDA "text *zvýrazněné*"
#   _view ZPRAVA nadpis "řádek\nřádek" [nápověda]
# Skutečné konce řádků se posílají jako \n (okno je převede zpět). Mimo okno nic nedělá.
_view() {
    _pruhledne || return 0
    local IFS=$'\t'
    # shellcheck disable=SC2261  # >&"$VIEW_FD" je deskriptor, ne soubor
    printf '%s\n' "${*//$'\n'/\\n}" >&"$VIEW_FD" 2>/dev/null
    return 0
}

# ── TTS ─────────────────────────────────────────────────────────
_uklid_tts() {
    [[ -n "$TMP_MP3" ]] && rm -f "$TMP_MP3"
    TMP_MP3=""
}

# PID čtení běžícího na pozadí (pasivní i interaktivní režim), viz _signal_tts
TTS_PID=""

# Pošle signál (STOP/CONT/TERM) běžícímu čtení i jeho potomkům
# (piper, ffmpeg, mpv, edge-tts jsou přímí potomci podprocesu TTS)
# STOP: nejdřív rodič, aby mezitím nespustil dalšího potomka (jinak by piper hrál dál).
_signal_tts() {
    [[ -n "$TTS_PID" ]] || return 0
    if [[ "$1" == "STOP" ]]; then
        kill -STOP "$TTS_PID" 2>/dev/null
        pkill -STOP -P "$TTS_PID" 2>/dev/null
    else
        pkill "-$1" -P "$TTS_PID" 2>/dev/null
        kill "-$1" "$TTS_PID" 2>/dev/null
    fi
    return 0
}

# _tts_reci "text" jazyk   — jazyk: kód (cs, de…) nebo cílový klíč (de_golf)
_tts_reci() {
    local text="$1"
    local jazyk
    jazyk=$(_kod "$2")
    local model="${TTS_MODELY[$jazyk]:-}"
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

        # Čeština — edge-tts (přirozenější hlas, potřebuje internet); bez něj Piper / espeak-ng
        if [[ "$jazyk" == "cs" ]] && command -v edge-tts &>/dev/null; then
            TMP_MP3=$(mktemp /tmp/tts_XXXXXX.mp3)
            edge-tts --voice cs-CZ-AntoninNeural \
                --text "$cast" \
                --write-media "$TMP_MP3" 2>/dev/null \
            && mpv --really-quiet --no-video --no-input-terminal "$TMP_MP3" 2>/dev/null
            _uklid_tts
            continue
        fi

        # Ostatní jazyky — Piper, bez Piperu nebo modelu záložně espeak-ng
        if [[ -z "$PIPER" || ! -f "$model" ]]; then
            if command -v espeak-ng &>/dev/null; then
                espeak-ng -v "$jazyk" -s 130 "$cast" 2>/dev/null
            else
                echo "[TTS: $model]" >&2
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

# ── Intro (--intro) ─────────────────────────────────────────────
# Před procvičováním se v dialogu nad kartou ukáže úvodní obrázek (vlajky + text) a hraje
# hudba, pak je krátká pauza. Text je v jazyce rozhraní: intro.<kód>.txt, čeština intro.txt.
# Obrázek se skládá z nejnovější fotky v intro/ a znovu se vygeneruje jen když se změnil
# text, fotka, seznam vlajek nebo intro-obrazek.py (pro každý jazyk rozhraní zvlášť).
readonly INTRO_ADR="$CESTA_SLOVNIKU/intro"
readonly INTRO_PY="$CESTA_SLOVNIKU/intro-obrazek.py"
readonly INTRO_DELKA="${SLOVICKA_INTRO_DELKA:-60}"
readonly INTRO_PAUZA="${SLOVICKA_INTRO_PAUZA:-5}"
# Šířka okna s úvodním obrázkem v px (výška = 16 : 9)
readonly INTRO_SIRKA="${SLOVICKA_INTRO_SIRKA:-1280}"
INTRO_HUDBA_PID=""

# Soubor s textem intra pro jazyk rozhraní (záložně angličtina, pak čeština)
_intro_text() {
    local f
    for f in "intro.$LOCALE.txt" "$( [[ "$LOCALE" == "cs" ]] && echo intro.txt)" "intro.en.txt" "intro.txt"; do
        [[ -n "$f" && -f "$CESTA_SLOVNIKU/$f" ]] && { printf '%s' "$CESTA_SLOVNIKU/$f"; return; }
    done
    printf '/dev/null'
}

_intro_vystup() { printf '%s/.vygenerovano/intro-%s.jpg' "$INTRO_ADR" "$LOCALE"; }

# Nejnovější soubor v intro/ s některou z přípon: _intro_soubor jpg png …
_intro_soubor() {
    local -a vzory=() p
    for p in "$@"; do vzory+=(-o -iname "*.$p"); done
    find "$INTRO_ADR" -maxdepth 1 -type f \( "${vzory[@]:1}" \) -printf '%T@\t%p\n' 2>/dev/null \
        | sort -rn | head -n1 | cut -f2-
}

# Vlajky všech jazyků oddělené mezerou (pořadí podle JAZYKY)
_intro_vlajky() {
    local j vysledek=""
    for j in "${JAZYKY[@]}"; do vysledek+="${vysledek:+ }${VLAJKY[$j]}"; done
    printf '%s' "$vysledek"
}

# Zkontroluje text, fotku a vlajky; při změně znovu složí úvodní obrázek.
# Vrací 1, když obrázek nejde připravit (chybí fotka nebo generátor selže).
_intro_priprav() {
    local obrazek vlajky otisk text vystup otisk_soubor
    obrazek=$(_intro_soubor jpg jpeg png webp)
    if [[ -z "$obrazek" ]]; then
        { _t intro.chybi_obrazek "$INTRO_ADR"; echo; } >&2
        return 1
    fi
    vlajky=$(_intro_vlajky)
    text=$(_intro_text)
    vystup=$(_intro_vystup)
    otisk_soubor="${vystup%.jpg}.otisk"
    otisk=$( { sha256sum "$obrazek" "$INTRO_PY" | cut -d' ' -f1
               sha256sum "$text" 2>/dev/null | cut -d' ' -f1
               printf '%s\n' "$obrazek" "$text" "$vlajky"
             } | sha256sum | cut -d' ' -f1 )
    if [[ -f "$vystup" && "$(cat "$otisk_soubor" 2>/dev/null)" == "$otisk" ]]; then
        return 0
    fi
    _view ZPRAVA "🎨 Intro" "$(_t intro.sklada)"
    echo -e "\e[0;90m$(_t intro.sklada_kratce)\e[0m"
    if ! uv run --quiet --script "$INTRO_PY" --obrazek "$obrazek" --text "$text" \
            --vystup "$vystup" --vlajky "$vlajky" >&2; then
        { _t intro.selhalo; echo; } >&2
        return 1
    fi
    printf '%s\n' "$otisk" > "$otisk_soubor"
}

_intro_zastav() {
    [[ -n "$INTRO_HUDBA_PID" ]] && kill "$INTRO_HUDBA_PID" 2>/dev/null
    INTRO_HUDBA_PID=""
    _view INTRO_KONEC
}

# Celé intro: příprava obrázku, INTRO_DELKA s obrázkem a hudbou, INTRO_PAUZA pauza.
# Obrázek ukazuje slovicka-view.py jako dialog nad kartou (plovoucí v každém kompozitoru,
# bez pravidel v konfiguraci); hudba hraje přes mpv. Klávesa v dialogu (q/Esc/mezera/Enter)
# intro přeskočí, [q] v okně se slovíčky ukončí procvičování. Bez okna (terminál) hraje jen hudba.
_intro_spust() {
    local hudba obraz_ok=1 klavesa
    _intro_priprav || obraz_ok=0
    hudba=$(_intro_soubor ogg mp3 opus flac wav m4a)

    if [[ -n "$hudba" ]]; then
        mpv --really-quiet --no-video --no-input-terminal --length="$INTRO_DELKA" \
            "$hudba" </dev/null &>/dev/null &
        INTRO_HUDBA_PID=$!
    fi

    _view ZPRAVA "🎵 Intro" "$(_t intro.text "$INTRO_DELKA")" "$(_t intro.napoveda)"
    echo -e "\e[1;32m🎵 Intro (${INTRO_DELKA} s)\e[0m \e[0;90m$(_t intro.napoveda_term)\e[0m"
    if [[ "$obraz_ok" == "1" ]] && _pruhledne; then
        _view INTRO "$(_intro_vystup)" "$INTRO_SIRKA"
    fi
    if [[ "$obraz_ok" == "1" ]] && _pruhledne || [[ -n "$INTRO_HUDBA_PID" ]]; then
        # Čeká INTRO_DELKA s, nebo na klávesu (přeskočit / q = konec)
        if IFS= read -r -s -n 1 -t "$INTRO_DELKA" klavesa; then
            [[ "${klavesa,,}" == "q" ]] && { _intro_zastav; exit 0; }
        fi
    fi
    _intro_zastav

    # Zbytek řádku / další stisknuté klávesy zahodit
    while read -r -t 0.05 -n 1 _; do :; done

    local i
    for (( i = INTRO_PAUZA; i > 0; i-- )); do
        _view ZPRAVA "$(_t intro.odpocet_nadpis)" "$(_t intro.odpocet "$i")"
        printf '\r\e[0;90m%s \e[0m' "$(_t intro.odpocet "$i")"
        sleep 1
    done
    echo
}

# ── Zvuk na pozadí ──────────────────────────────────────────────
# _pozadi_spust [vypnuto]   — vypnuto=1 (volba --bez-sumu) nic nespustí
_pozadi_spust() {
    local zdroj="${SLOVICKA_POZADI:-sum}"
    [[ "${1:-0}" == "1" || "$zdroj" == "ne" || "$zdroj" == "0" ]] && return 0
    command -v mpv &>/dev/null || return 0
    local -a mpv_volby=(--no-video --really-quiet --no-input-terminal
                        --audio-client-name=slovicka-pozadi)
    if [[ "$zdroj" == "sum" ]]; then
        mpv "${mpv_volby[@]}" \
            "av://lavfi:anoisesrc=color=${SLOVICKA_SUM_BARVA:-white}:amplitude=${SLOVICKA_SUM_UROVEN:-0.003}" \
            </dev/null &>/dev/null &
    elif [[ -f "$zdroj" ]]; then
        mpv "${mpv_volby[@]}" --loop-file=inf --volume="${SLOVICKA_POZADI_HLASITOST:-25}" "$zdroj" \
            </dev/null &>/dev/null &
    else
        return 0
    fi
    POZADI_PID=$!
}

_pozadi_zastav() {
    [[ -n "$POZADI_PID" ]] && kill "$POZADI_PID" 2>/dev/null
    POZADI_PID=""
    return 0
}

# ── Neznámá slovíčka ────────────────────────────────────────────
# neznama/<mateřský>-<cíl>.txt — id pojmů, jedno na řádek

_soubor_neznamych() {
    printf '%s/%s-%s%s.txt' "$ADRESAR_NEZNAMYCH" "$ZDROJ" "$1" "$([[ "$GR" == "1" ]] && printf -- '-gr')"
}

# _neznama_pridej cíl "řádek slovníku" ...   — přidá (bez duplicit)
_neznama_pridej() {
    local f r
    f=$(_soubor_neznamych "$1"); shift
    (( $# )) || return 0
    mkdir -p "$ADRESAR_NEZNAMYCH"
    { cat "$f" 2>/dev/null
      for r in "$@"; do [[ -n "${RADEK_ID[$r]:-}" ]] && printf '%s\n' "${RADEK_ID[$r]}"; done
    } | sort -u > "$f.tmp" && mv -f "$f.tmp" "$f"
}

# _neznama_odeber cíl "řádek slovníku" ...   — odebere; prázdný soubor smaže
_neznama_odeber() {
    local f r
    f=$(_soubor_neznamych "$1"); shift
    (( $# )) && [[ -f "$f" ]] || return 0
    grep -vxF -f <(for r in "$@"; do printf '%s\n' "${RADEK_ID[$r]:-}"; done) "$f" > "$f.tmp"
    mv -f "$f.tmp" "$f"
    [[ -s "$f" ]] || rm -f "$f"
}

# ── Nabídky (terminál, GTK, nebo rofi/fuzzel/wofi/zenity) ──────

# Výběr z nabídky. Vypíše pořadové číslo zvolené položky (1..N), při zrušení nic.
#   terminál → číslem; jinak GTK nabídka ze slovicka-view.py (každý Wayland i X11);
#   bez uv záložně rofi, fuzzel, wofi nebo zenity (podle toho, co je nainstalované).
_vyber() {
    local vyzva="$1"; shift
    if [[ -t 0 ]]; then
        echo -e "\n\e[1;34m$vyzva\e[0m" >&2
        local n=1 polozka
        for polozka in "$@"; do printf '  %d) %s\n' "$n" "$polozka" >&2; (( ++n )); done
        printf '%s' "$(_t nabidka.volba "$#")" >&2
        local volba; read -r volba
        echo "${volba:-1}"
    elif _lze_gtk; then
        local vystup index token
        vystup=$(_s_tokenem uv run --quiet --script "$VIEW_PY" --vyber "$vyzva" "$@" 2>/dev/null) \
            || return 0
        { IFS= read -r index; IFS= read -r token; } <<< "$vystup"
        [[ -n "$token" ]] && printf '%s' "$token" > "$TOKEN_SOUBOR"
        echo "$index"
    else
        _vyber_dmenu "$vyzva" "$@"
    fi
}

# Záložní nabídka přes dmenu-styl program. Vypíše 1..N, při zrušení nic.
_vyber_dmenu() {
    local vyzva="$1"; shift
    local text="" i=1 polozka
    if command -v rofi &>/dev/null; then
        printf '%s\n' "$@" | rofi -dmenu -i -no-custom -format d -p "$vyzva"
        return 0
    elif command -v fuzzel &>/dev/null; then
        text=$(printf '%s\n' "$@" | fuzzel --dmenu --prompt "$vyzva: ")
    elif command -v wofi &>/dev/null; then
        text=$(printf '%s\n' "$@" | wofi --dmenu --insensitive --prompt "$vyzva")
    elif command -v zenity &>/dev/null; then
        text=$(zenity --list --title="$(_t app)" --text="$vyzva" --column="$vyzva" "$@" 2>/dev/null)
    else
        _chyba "$(_t nabidka.neni)"
    fi
    [[ -n "$text" ]] || return 0
    for polozka in "$@"; do
        [[ "$polozka" == "$text" ]] && { echo "$i"; return 0; }
        (( ++i ))
    done
}

# Číslo volby z nabídky → položka pole; zrušení = konec skriptu
_volba_z() {
    local volba="$1"; shift
    [[ -z "$volba" ]] && exit 0
    if [[ "$volba" =~ ^[0-9]+$ ]] && (( volba >= 1 && volba <= $# )); then
        printf '%s' "${!volba}"
    else
        _chyba "$(_t nabidka.neplatna "$volba")"
    fi
}

# Vybere jazyk (mateřský nebo rozhraní) a uloží ho: _vyber_nastaveni zdroj|locale
_vyber_nastaveni() {
    local co="$1" j aktualni
    local -a polozky=()
    [[ "$co" == "zdroj" ]] && aktualni="$ZDROJ" || aktualni="$LOCALE"
    for j in "${JAZYKY[@]}"; do
        polozky+=("$(_nazev_jazyka "$j" vlajka)$([[ "$j" == "$aktualni" ]] && echo "  ✓")")
    done
    local volba
    volba=$(_volba_z "$(_vyber "$(_t "nastaveni.$co.vyzva")" "${polozky[@]}")" "${JAZYKY[@]}") || exit $?
    _nastaveni_zapis "$co" "$volba"
}

# Vypíše cílový klíč, u uložených neznámých slovíček "neznama:<klíč>",
# po změně nastavení "nastaveni" (volající nabídku zobrazí znovu). Esc = konec skriptu.
_vyber_jazyk() {
    local -a klice=() polozky=() cile
    local j f n
    mapfile -t cile < <(_cile)
    for j in "${cile[@]}"; do
        klice+=("$j"); polozky+=("$(_nazev "$j")")
    done
    for j in "${cile[@]}"; do
        f=$(_soubor_neznamych "$j")
        [[ -s "$f" ]] || continue
        n=$(wc -l < "$f")
        klice+=("neznama:$j"); polozky+=("$(_t neznama.polozka "$(_nazev "$j")" "$n")")
    done
    klice+=("nastaveni:zdroj" "nastaveni:locale")
    polozky+=("$(_t nastaveni.zdroj "$(_nazev_jazyka "$ZDROJ" vlajka)")"
              "$(_t nastaveni.locale "$(_nazev_jazyka "$LOCALE" vlajka)")")

    local klic
    klic=$(_volba_z "$(_vyber "$(_t vyber.jazyk)" "${polozky[@]}")" "${klice[@]}") || exit $?
    if [[ "$klic" == nastaveni:* ]]; then
        _vyber_nastaveni "${klic#nastaveni:}"
        echo "nastaveni"
    else
        echo "$klic"
    fi
}

# Nabídka jazyka v cyklu — po změně nastavení se znovu načtou jazyky a texty.
# Výsledek v proměnné VYBRANY_CIL (volat bez $( ), aby platilo i nové nastavení).
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

# Vypíše 0 (cizí jazyk první) nebo 1 (mateřský první)
_vyber_poradi() {
    local cil="$1" a b
    a=$(_nazev_jazyka "$(_kod "$cil")")
    b=$(_nazev_jazyka "$ZDROJ")
    local volba
    volba=$(_vyber "$(_t vyber.poradi)" "$a → $b" "$b → $a")
    case "$volba" in
        1) echo "0" ;;
        2) echo "1" ;;
        "") exit 0 ;;
        *) _chyba "$(_t nabidka.neplatna "$volba")" ;;
    esac
}

# Společné volby obou skriptů (--z, --locale) — vrací 0, když volbu zpracovala.
# _spolecna_volba "$volba" "$hodnota"; posun indexu řeší volající podle návratové hodnoty 2.
_spolecna_volba() {
    case "$1" in
        --z|--from|-f)
            _je_kod "${2:-}" || _chyba "$(_t chyba.jazyk "${2:-}" "${JAZYKY[*]}")"
            _nastav_jazyky "$2" ""; return 2 ;;
        --locale|-l)
            _je_kod "${2:-}" || _chyba "$(_t chyba.jazyk "${2:-}" "${JAZYKY[*]}")"
            _nastav_jazyky "" "$2"; return 2 ;;
    esac
    return 1
}

# Kontrola cíle po volbách: existuje a liší se od mateřského jazyka
_over_cil() {
    _je_jazyk "$1" || _chyba "$(_t chyba.jazyk "$1" "$(_seznam_jazyku)")"
    [[ "$(_kod "$1")" != "$ZDROJ" ]] || _chyba "$(_t chyba.stejny "$(_nazev_jazyka "$ZDROJ")")"
}
