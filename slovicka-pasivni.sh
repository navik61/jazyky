#!/usr/bin/env bash
# ================================================================
# slovicka-pasivni.sh
# Pasivní poslech slovíček se vzorovými frázemi v průhledném okně (slovicka-view.py)
# Ovládání v okně: [mezera] pauza / pokračovat · [z] znovu · [x] chybná fráze · [q] konec
# Použití: ./slovicka-pasivni.sh [jazyk] [--swap|--orig] [--neznama] [--bez-frazi]
#                                [--vsechna] [--pocet N] [--pauza N] [--bez-sumu] [--intro]
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
    echo "Použití: $0 [jazyk] [volby]"
    echo ""
    echo "Jazyky: $(_seznam_jazyku)"
    echo ""
    echo "Volby:"
    echo "  --swap, -s      Nejdříve česky, pak originál"
    echo "  --orig, -o      Nejdříve originál, pak česky (bez dotazu)"
    echo "  --neznama, -u   Jen uložená neznámá slovíčka (z interaktivního režimu)"
    echo "  --bez-frazi     Nezobrazovat a nečíst vzorové fráze"
    echo "  --vsechna, -a   Projít celý slovník"
    echo "  --pocet N, -n   Počet slovíček (výchozí: 30)"
    echo "  --pauza N, -p   Pauza mezi slovíčky v sekundách (výchozí: 3)"
    echo "  --bez-sumu      Bez tichého šumu na pozadí (drží BT reproduktor vzhůru)"
    echo "  --intro, intro  Před procvičováním ${INTRO_DELKA} s úvodní obrázek s hudbou, pak ${INTRO_PAUZA} s pauza"
    echo ""
    echo "Ovládání v okně: [mezera] pauza / pokračovat · [z] zopakovat slovíčko · [x] chybná fráze · [q] konec"
    echo ""
    echo "Příklady:"
    echo "  $0 de                    # 30 německých, zeptá se na pořadí"
    echo "  $0 en --swap --pocet 50  # 50 anglických, česky první"
    echo "  $0 it --vsechna --pauza 4"
    exit "${1:-0}"
}

# ── Ovládání klávesami ──────────────────────────────────────────

# Část nápovědy ke klávese [x] — jen když má slovíčko frázi
_napoveda_x() {
    [[ -n "$AKT_RADEK" && -n "${FRAZE[$AKT_RADEK]:-}" ]] || return 0
    if (( AKT_OZNACENO )); then
        printf ' · \e[1;31m✗ označeno\e[0;90m'
    else
        printf ' · [x] chyba'
    fi
}

# Totéž pro průhledné okno (*…* = zvýraznit)
_napoveda_x_view() {
    [[ -n "$AKT_RADEK" && -n "${FRAZE[$AKT_RADEK]:-}" ]] || return 0
    if (( AKT_OZNACENO )); then printf ' · *✗ fráze označena*'; else printf ' · [x] chybná fráze'; fi
}

_napoveda_klaves() {
    _view NAPOVEDA "[mezera] pauza · [z] znovu$(_napoveda_x_view) · [q] konec"
    printf '\r\e[K\e[0;90m[mezera] pauza · [z] znovu%s · [q] konec\e[0m' "$(_napoveda_x)"
}

_radek_pauzy() {
    _view NAPOVEDA "*⏸ Pauza* · [mezera] dál · [z] znovu$(_napoveda_x_view) · [q] konec"
    printf '\r\e[K\e[1;33m⏸ Pauza\e[0;90m · [mezera] dál · [z] znovu%s · [q] konec\e[0m' "$(_napoveda_x)"
}

# [x]: uloží frázi aktuálního slovíčka do fraze/chybne.tsv
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
    echo -e "\n\n\e[1;33mPřerušeno.\e[0m"
    exit 0
}
trap _na_preruseni INT TERM HUP    # HUP = zavřené okno
trap _uklid EXIT

main() {
    local jazyk="" swap="0" poradi_zadano="0" jen_neznama="0" bez_frazi="0"
    local vsechna="0" pocet=30 pauza=3 bez_sumu="0" intro="0"

    local i=0
    local -a args=("$@")
    while (( i < ${#args[@]} )); do
        case "${args[i]}" in
            --swap|-s) swap="1"; poradi_zadano="1" ;;
            --orig|-o) swap="0"; poradi_zadano="1" ;;
            --neznama|-u) jen_neznama="1" ;;
            --bez-frazi) bez_frazi="1" ;;
            --vsechna|-a) vsechna="1" ;;
            --pruhledne|-t) ;;   # dřív volba průhledného okna, teď výchozí
            --bez-sumu) bez_sumu="1" ;;
            --intro|intro) intro="1" ;;
            --pocet|-n) (( ++i )); pocet="${args[i]:-}" ;;
            --pauza|-p) (( ++i )); pauza="${args[i]:-}" ;;
            -h|--help) _pouziti 0 ;;
            *)
                if _je_jazyk "${args[i]}"; then
                    jazyk="${args[i]}"
                else
                    echo "Neznámý argument: ${args[i]}" >&2
                    _pouziti 1 >&2
                fi ;;
        esac
        (( ++i ))
    done

    if ! [[ "$pocet" =~ ^[1-9][0-9]*$ ]]; then
        _chyba "--pocet musí být kladné celé číslo (zadáno: '$pocet')"
    fi
    if ! [[ "$pauza" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        _chyba "--pauza musí být číslo v sekundách (zadáno: '$pauza')"
    fi

    # Výběr jazyka (terminál nebo rofi), včetně uložených neznámých
    if [[ -z "$jazyk" ]]; then
        jazyk=$(_vyber_jazyk) || exit $?
        [[ -z "$jazyk" ]] && exit 0
        if [[ "$jazyk" == neznama:* ]]; then
            jazyk="${jazyk#neznama:}"
            jen_neznama="1"
        fi
    fi

    # Výběr pořadí, pokud nebylo zadáno --swap / --orig
    if [[ "$poradi_zadano" == "0" && "$V_OKNE" == "0" ]]; then
        swap=$(_vyber_poradi) || exit $?
        [[ -z "$swap" ]] && exit 0
    fi

    local soubor nazev="${NAZVY[$jazyk]}"
    if [[ "$jen_neznama" == "1" ]]; then
        soubor=$(_soubor_neznamych "$jazyk")
        nazev="Neznámá: $nazev"
        [[ -s "$soubor" ]] || _chyba "Zatím nemáš uložená žádná neznámá slovíčka (${NAZVY[$jazyk]})."
    else
        soubor="${SOUBORY[$jazyk]}"
        [[ -f "$soubor" ]] || _chyba "Soubor nenalezen: $soubor"
    fi

    # Mimo okno: otevřít průhledné okno a spustit poslech v něm
    local -a argumenty=("$jazyk" --pocet "$pocet" --pauza "$pauza")
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
    if [[ "$vsechna" == "1" ]]; then
        mapfile -t slovicka < <(grep ' — ' "$soubor" | shuf)
    else
        mapfile -t slovicka < <(grep ' — ' "$soubor" | shuf | head -n "$pocet")
    fi

    local celkem=${#slovicka[@]}
    local rezim
    if [[ "$swap" == "1" ]]; then rezim="Česky → Originál"; else rezim="Originál → Česky"; fi

    _view ZPRAVA "▶ Pasivní poslech: $nazev" "Slovíček: $celkem\nPořadí: $rezim\nPauza: ${pauza} s"
    clear
    echo -e "\n\e[1;32m▶ Pasivní poslech: $nazev\e[0m"
    printf "  Slovíček: %d  │  Pořadí: %s  │  Pauza: %ss\n" "$celkem" "$rezim" "$pauza"
    _napoveda_klaves
    _cekej 1.5

    local radek orig cz prvni druhy prvni_jazyk druhy_jazyk titulek fraze fraze_cs
    i=1
    for radek in "${slovicka[@]}"; do
        orig="${radek%% — *}"
        cz="${radek#* — }"
        fraze="${FRAZE[$radek]:-}"
        fraze_cs="${FRAZE_CS[$radek]:-}"
        AKT_RADEK="$radek"; AKT_JAZYK="$jazyk"; AKT_OZNACENO=0

        if [[ "$swap" == "1" ]]; then
            prvni="$cz";   prvni_jazyk="cs"
            druhy="$orig"; druhy_jazyk="$jazyk"
            titulek="🇨🇿 $i/$celkem  →  ${VLAJKY[$jazyk]}"
        else
            prvni="$orig"; prvni_jazyk="$jazyk"
            druhy="$cz";   druhy_jazyk="cs"
            titulek="${VLAJKY[$jazyk]} $i/$celkem  →  🇨🇿"
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

    _view ZPRAVA "✓ Hotovo!" "Přehráno $celkem slovíček." "[libovolná klávesa] zavřít okno (jinak za 10 s)"
    clear
    echo -e "\n\e[1;32m✓ Hotovo! Přehráno $celkem slovíček.\e[0m"
    if [[ "$V_OKNE" != "0" ]]; then
        printf '\e[0;90m[libovolná klávesa] zavřít okno (jinak za 10 s)\e[0m'
        read -rsn1 -t 10
    fi
}

main "$@"
