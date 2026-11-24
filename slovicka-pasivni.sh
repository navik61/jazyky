#!/usr/bin/env bash
# ================================================================
# slovicka-pasivni.sh
# Pasivní poslech slovíček se vzorovými frázemi v průhledném okně (slovicka-view.py)
# Ovládání v okně: [mezera] pauza / pokračovat · [z] znovu · [x] chybná fráze · [q] konec
# Použití: ./slovicka-pasivni.sh [cíl] [--z jazyk] [--locale jazyk] [--swap|--orig] [--neznama]
#                                [--bez-frazi] [--vsechna] [--pocet N] [--pauza N] [--bez-sumu] [--intro]
# ================================================================

# Bez grafické relace (cron, systemd) by mpv nenašel PipeWire
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
export XDG_RUNTIME_DIR

# ── Konfigurace ─────────────────────────────────────────────────
SKRIPT=$(readlink -f "${BASH_SOURCE[0]}")
readonly SKRIPT
CESTA_SLOVNIKU=$(dirname "$SKRIPT")
readonly CESTA_SLOVNIKU
# shellcheck source=spolecne.sh
source "$CESTA_SLOVNIKU/spolecne.sh" || { echo "Chybí $CESTA_SLOVNIKU/spolecne.sh" >&2; exit 1; }

readonly PAUZA_MEZI_JAZYKY=1.2
readonly PAUZA_PRED_FRAZI=0.8

# Právě zobrazené slovíčko — pro označení chybné fráze klávesou [x]
AKT_RADEK=""
AKT_JAZYK=""
AKT_OZNACENO=0
# 1 = uživatel stiskl [z], aktuální slovíčko se přehraje znovu od začátku
ZOPAKOVAT=0

# ── Funkce ──────────────────────────────────────────────────────

_pouziti() {
    _t pomoc.pouziti "$0"; echo; echo
    _t pomoc.jazyky "$(_seznam_jazyku)"; echo; echo
    _t pomoc.volby; echo
    printf '  %-26s %s\n' \
        "--z, --from, -f X" "$(_t pomoc.z "${JAZYKY[*]}" "$ZDROJ")" \
        "--locale, -l X" "$(_t pomoc.locale "$LOCALE")" \
        "--swap, -s" "$(_t pomoc.swap)" \
        "--orig, -o" "$(_t pomoc.orig)" \
        "--neznama, --unknown, -u" "$(_t pomoc.neznama)" \
        "--bez-frazi, --no-phrases" "$(_t pomoc.bez_frazi)" \
        "--vsechna, --all, -a" "$(_t pomoc.vsechna)" \
        "--pocet, --count, -n N" "$(_t pomoc.pocet)" \
        "--pauza, --pause, -p N" "$(_t pomoc.pauza)" \
        "--bez-sumu, --no-noise" "$(_t pomoc.bez_sumu)" \
        "--intro, intro" "$(_t pomoc.intro "$INTRO_DELKA" "$INTRO_PAUZA")"
    echo
    _t pomoc.ovladani_p; echo
    echo
    _t pomoc.priklady; echo
    printf '  %-34s # %s\n' "$0 de" "$(_t pomoc.priklad1)" \
        "$0 en --swap --pocet 50" "$(_t pomoc.priklad2)" \
        "$0 es --z de --vsechna" "$(_t pomoc.priklad3)"
    exit "${1:-0}"
}

# ── Ovládání klávesami ──────────────────────────────────────────

# Část nápovědy ke klávese [x] — jen když má slovíčko frázi
_napoveda_x() {
    [[ -n "$AKT_RADEK" && -n "${FRAZE[$AKT_RADEK]:-}" ]] || return 0
    if (( AKT_OZNACENO )); then
        printf ' · \e[1;31m✗ %s\e[0;90m' "$(_t w.oznaceno)"
    else
        printf ' · [x] %s' "$(_t w.chyba)"
    fi
}

# Totéž pro průhledné okno (*…* = zvýraznit)
_napoveda_x_view() {
    [[ -n "$AKT_RADEK" && -n "${FRAZE[$AKT_RADEK]:-}" ]] || return 0
    if (( AKT_OZNACENO )); then
        printf ' · *✗ %s*' "$(_t w.fraze_oznacena)"
    else
        printf ' · [x] %s' "$(_t w.chybna_fraze)"
    fi
}

_napoveda_klaves() {
    local zaklad
    zaklad="[$(_t k.mezera)] $(_t w.pauza) · [z] $(_t w.znovu)"
    _view NAPOVEDA "$zaklad$(_napoveda_x_view) · [q] $(_t w.konec)"
    printf '\r\e[K\e[0;90m%s%s · [q] %s\e[0m' "$zaklad" "$(_napoveda_x)" "$(_t w.konec)"
}

_radek_pauzy() {
    local dal
    dal="[$(_t k.mezera)] $(_t w.dal) · [z] $(_t w.znovu)"
    _view NAPOVEDA "*⏸ $(_t w.pauza_nadpis)* · $dal$(_napoveda_x_view) · [q] $(_t w.konec)"
    printf '\r\e[K\e[1;33m⏸ %s\e[0;90m · %s%s · [q] %s\e[0m' \
        "$(_t w.pauza_nadpis)" "$dal" "$(_napoveda_x)" "$(_t w.konec)"
}

# [x]: uloží větu aktuálního slovíčka do fraze/chybne.tsv
_oznac() {
    [[ -n "$AKT_RADEK" ]] && (( ! AKT_OZNACENO )) || return 0
    _oznac_chybnou "$AKT_JAZYK" "$AKT_RADEK" && AKT_OZNACENO=1
    return 0
}

# [z]: přeruší čtení a nechá aktuální slovíčko přehrát znovu od začátku
_zopakuj() {
    ZOPAKOVAT=1
    _signal_tts CONT      # zmrazený proces musí běžet, aby přijal TERM
    _signal_tts TERM
}

# Pauza: zmrazí rozpracované čtení a čeká na mezeru (q = konec)
_pauza() {
    local klavesa
    _signal_tts STOP
    _radek_pauzy
    while :; do
        IFS= read -rsn1 klavesa || exit 0      # konec vstupu (zavřené okno)
        case "$klavesa" in
            " ") break ;;
            z|Z) _zopakuj; break ;;
            x|X) _oznac; _radek_pauzy ;;
            q|Q) _signal_tts CONT; exit 0 ;;
        esac
    done
    _signal_tts CONT
    _napoveda_klaves
}

_zpracuj_klavesu() {
    case "$1" in
        " ") _pauza ;;
        z|Z) _zopakuj ;;
        x|X) _oznac; _napoveda_klaves ;;
        q|Q) exit 0 ;;
    esac
}

# Přečte text a mezitím reaguje na klávesy (čtení běží na pozadí)
_mluv() {
    local klavesa
    (
        # vlastní úklid mp3 — podproces nedědí trapy hlavního skriptu
        trap _uklid_tts EXIT
        _tts_reci "$1" "$2"
    ) </dev/null 2>/dev/null &      # 2>/dev/null: bez hlášky „Terminated“ po [z]/[q]
    TTS_PID=$!
    while kill -0 "$TTS_PID" 2>/dev/null; do
        if IFS= read -rsn1 -t 0.1 klavesa; then
            _zpracuj_klavesu "$klavesa"
        fi
    done
    wait "$TTS_PID" 2>/dev/null
    TTS_PID=""
}

# Čeká N sekund (lze i desetinná) a mezitím reaguje na klávesy.
# ${EPOCHREALTIME/,/.}: v českém prostředí má čas desetinnou čárku, awk chce tečku.
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

# ── Zobrazení ───────────────────────────────────────────────────

_zobraz() {
    local titulek="$1" nazev="$2" prvni="$3" druhy="$4" fraze="$5" fraze_cs="$6"
    _view KARTA "$titulek  │  $nazev" "$prvni" "$druhy" "$fraze" "$fraze_cs"
    clear
    _vypis_kartu "$titulek" "$nazev" "$prvni" "$druhy" "$fraze" "$fraze_cs"
    _napoveda_klaves
}

_uklid() {
    rm -f "$TOKEN_SOUBOR"     # nespotřebovaný aktivační token (zrušená nabídka)
    _intro_zastav
    _pozadi_zastav
    _signal_tts CONT
    _signal_tts TERM
    _uklid_tts
}

_na_preruseni() {
    echo -e "\n\n\e[1;33m$(_t preruseno)\e[0m"
    exit 0
}
trap _na_preruseni INT TERM HUP    # HUP = zavřené okno
trap _uklid EXIT

main() {
    local jazyk="" swap="0" poradi_zadano="0" jen_neznama="0" bez_frazi="0"
    local vsechna="0" pocet=30 pauza=3 bez_sumu="0" intro="0" kod

    local i=0
    local -a args=("$@")
    while (( i < ${#args[@]} )); do
        _spolecna_volba "${args[i]}" "${args[i+1]:-}"
        kod=$?
        if (( kod == 2 )); then (( i += 2 )); continue; fi
        case "${args[i]}" in
            --swap|-s) swap="1"; poradi_zadano="1" ;;
            --orig|-o) swap="0"; poradi_zadano="1" ;;
            --neznama|--unknown|-u) jen_neznama="1" ;;
            --bez-frazi|--no-phrases) bez_frazi="1" ;;
            --vsechna|--all|-a) vsechna="1" ;;
            --pruhledne|-t) ;;   # dřív volba průhledného okna, teď výchozí
            --bez-sumu|--no-noise) bez_sumu="1" ;;
            --intro|intro) intro="1" ;;
            --pocet|--count|-n) (( ++i )); pocet="${args[i]:-}" ;;
            --pauza|--pause|-p) (( ++i )); pauza="${args[i]:-}" ;;
            -h|--help) _pouziti 0 ;;
            *)
                if _je_jazyk "${args[i]}"; then
                    jazyk="${args[i]}"
                else
                    { _t chyba.argument "${args[i]}"; echo; } >&2
                    _pouziti 1 >&2
                fi ;;
        esac
        (( ++i ))
    done

    [[ "$pocet" =~ ^[1-9][0-9]*$ ]] || _chyba "$(_t chyba.pocet "$pocet")"
    [[ "$pauza" =~ ^[0-9]+([.][0-9]+)?$ ]] || _chyba "$(_t chyba.pauza "$pauza")"

    # Výběr jazyka (terminál, GTK nebo rofi…), včetně uložených neznámých a nastavení
    if [[ -z "$jazyk" ]]; then
        _vyber_cil
        jazyk="$VYBRANY_CIL"
        if [[ "$jazyk" == neznama:* ]]; then
            jazyk="${jazyk#neznama:}"
            jen_neznama="1"
        fi
    fi
    _over_cil "$jazyk"

    # Výběr pořadí, pokud nebylo zadáno --swap / --orig
    if [[ "$poradi_zadano" == "0" && "$V_OKNE" == "0" ]]; then
        swap=$(_vyber_poradi "$jazyk") || exit $?
        [[ -z "$swap" ]] && exit 0
    fi

    _nacti_slovnik "$jazyk"
    (( ${#RADKY[@]} )) || _chyba "$(_t chyba.prazdny "$(_nazev "$jazyk")" "$(_nazev_jazyka "$ZDROJ")")"
    local nazev
    nazev=$(_nazev "$jazyk")
    if [[ "$jen_neznama" == "1" ]]; then
        [[ -s "$(_soubor_neznamych "$jazyk")" ]] || _chyba "$(_t chyba.zadna_neznama "$nazev")"
        nazev=$(_t neznama.nazev "$nazev")
    fi

    # Mimo okno: otevřít průhledné okno a spustit poslech v něm
    local -a argumenty=("$jazyk" --z "$ZDROJ" --locale "$LOCALE" --pocet "$pocet" --pauza "$pauza")
    if [[ "$swap" == "1" ]]; then argumenty+=(--swap); else argumenty+=(--orig); fi
    [[ "$jen_neznama" == "1" ]] && argumenty+=(--neznama)
    [[ "$bez_frazi" == "1" ]] && argumenty+=(--bez-frazi)
    [[ "$vsechna" == "1" ]] && argumenty+=(--vsechna)
    [[ "$bez_sumu" == "1" ]] && argumenty+=(--bez-sumu)
    [[ "$intro" == "1" ]] && argumenty+=(--intro)
    if _lze_otevrit_okno; then
        _spust_v_okne znaky "${argumenty[@]}"
        trap - EXIT
        exit 0
    fi

    [[ "$intro" == "1" ]] && _intro_spust
    [[ "$bez_frazi" == "0" ]] && _nacti_fraze "$jazyk"
    _pozadi_spust "$bez_sumu"

    local -a slovicka
    local neznama_arg=""
    [[ "$jen_neznama" == "1" ]] && neznama_arg="neznama"
    if [[ "$vsechna" == "1" ]]; then
        mapfile -t slovicka < <(_slovicka "$jazyk" $neznama_arg | shuf)
    else
        mapfile -t slovicka < <(_slovicka "$jazyk" $neznama_arg | shuf | head -n "$pocet")
    fi

    local celkem=${#slovicka[@]}
    local rezim cizi vlastni
    cizi=$(_nazev_jazyka "$(_kod "$jazyk")"); vlastni=$(_nazev_jazyka "$ZDROJ")
    if [[ "$swap" == "1" ]]; then rezim="$vlastni → $cizi"; else rezim="$cizi → $vlastni"; fi

    _view ZPRAVA "$(_t pasivni.nadpis "$nazev")" "$(_t pasivni.info "$celkem" "$rezim" "$pauza")"
    clear
    echo -e "\n\e[1;32m$(_t pasivni.nadpis "$nazev")\e[0m"
    printf "  %s\n" "$(_t pasivni.info_term "$celkem" "$rezim" "$pauza")"
    _napoveda_klaves
    _cekej 1.5

    local radek orig cz prvni druhy prvni_jazyk druhy_jazyk titulek fraze fraze_cs vlajka
    vlajka="${VLAJKY[$(_kod "$jazyk")]}"
    i=1
    for radek in "${slovicka[@]}"; do
        orig="${radek%% — *}"
        cz="${radek#* — }"
        fraze="${FRAZE[$radek]:-}"
        fraze_cs="${FRAZE_PREKLAD[$radek]:-}"
        AKT_RADEK="$radek"; AKT_JAZYK="$jazyk"; AKT_OZNACENO=0

        if [[ "$swap" == "1" ]]; then
            prvni="$cz";   prvni_jazyk="$ZDROJ"
            druhy="$orig"; druhy_jazyk="$jazyk"
            titulek="${VLAJKY[$ZDROJ]} $i/$celkem  →  $vlajka"
        else
            prvni="$orig"; prvni_jazyk="$jazyk"
            druhy="$cz";   druhy_jazyk="$ZDROJ"
            titulek="$vlajka $i/$celkem  →  ${VLAJKY[$ZDROJ]}"
        fi

        # Přehrání slovíčka; [z] kdykoli během něj skočí zpět na začátek
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

        (( ++i ))
    done

    _view ZPRAVA "$(_t hotovo)" "$(_t hotovo.prehrano "$celkem")" "$(_t zavrit.klavesa)"
    clear
    echo -e "\n\e[1;32m$(_t hotovo) $(_t hotovo.prehrano "$celkem")\e[0m"
    if [[ "$V_OKNE" != "0" ]]; then
        printf '\e[0;90m%s\e[0m' "$(_t zavrit.klavesa)"
        read -rsn1 -t 10
    fi
}

main "$@"
