#!/usr/bin/env bash
# ================================================================
# slovicka-interaktivni.sh
# Interaktivní procvičování slovíček s TTS v průhledném okně (slovicka-view.py)
# Použití: ./slovicka-interaktivni.sh [cíl] [--z jazyk] [--locale jazyk] [--swap|--orig] [--neznama]
#                                     [--bez-frazi] [--bez-sumu] [--intro] [--gr]
# --gr = gramatika: procvičování gramatických tvarů (mateřský jazyk → cílový → doslovný překlad)
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

readonly POCET_KOLO=30
readonly PAUZA_PO_ORIG=1.0
readonly PAUZA_PO_PREKLADU=0.5
readonly PAUZA_PRED_FRAZI=0.8

# 1 = procvičují se jen uložená neznámá slovíčka (--neznama)
JEN_NEZNAMA=0
# 1 = nezobrazovat a nečíst vzorové fráze (--bez-frazi)
BEZ_FRAZI=0
# 1 = bez tichého šumu na pozadí (--bez-sumu)
BEZ_SUMU=0
# 1 = před procvičováním intro s obrázkem a hudbou (--intro)
INTRO=0

# GR (spolecne.sh) = 1: místo slovíček se procvičují gramatické tvary (--gr)

# Stav aktuálního slovíčka (čtení běží na pozadí, klávesy se obsluhují mezitím)
AKT_RADEK=""
AKT_JAZYK=""
AKT_OZNACENO=0
# Odpověď zadaná už během čtení ([Enter]/[n]/[q]); ODPOVED_ZADANA=1 = platí
ODPOVED=""
ODPOVED_ZADANA=0

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
        "--bez-sumu, --no-noise" "$(_t pomoc.bez_sumu)" \
        "--intro, intro" "$(_t pomoc.intro "$INTRO_DELKA" "$INTRO_PAUZA")" \
        "--gr, --gramatika, -g" "$(_t pomoc.gr)"
    echo
    _t pomoc.ovladani_i; echo
    exit "${1:-0}"
}

_uklid() {
    rm -f "$TOKEN_SOUBOR"     # nespotřebovaný aktivační token (zrušená nabídka)
    _intro_zastav
    _pozadi_zastav
    _signal_tts CONT
    _signal_tts TERM
    _uklid_tts
}

# Gramatika: 1. věta v mateřském jazyce, 2. v cílovém, 3. doslovný překlad (způsob myšlení)
_zobraz_gramatiku() {
    local id="$1" jazyk="$2" cislo="$3" celkem="$4"
    local zdroj="${GR_ZDROJ[$id]}" cil="${GR_CIL[$id]}" dosl="${GR_DOSL[$id]}"
    local titulek="${VLAJKY[$ZDROJ]} $cislo/$celkem  →  ${VLAJKY[$(_kod "$jazyk")]}"
    local nazev
    nazev="$(_t gr.nazev)  ·  ${GR_TVAR[$id]}"
    [[ "$JEN_NEZNAMA" == "1" ]] && nazev=$(_t neznama.nazev "$nazev")

    _view KARTA "$titulek  │  $nazev" "$zdroj" "$cil" "≈ $dosl" ""
    clear
    _vypis_kartu "$titulek" "$nazev" "$zdroj" "$cil" "≈ $dosl" ""
    _precti "$zdroj" "$ZDROJ" "$cil" "$jazyk" "$(_gr_dosl_tts "$dosl")" "$ZDROJ"
}

_zobraz_slovicko() {
    local radek="$1" jazyk="$2" swap="$3" cislo="$4" celkem="$5"
    if [[ "$GR" == "1" ]]; then _zobraz_gramatiku "$radek" "$jazyk" "$cislo" "$celkem"; return; fi
    local orig="${radek%% — *}" cz="${radek#* — }"
    local fraze="" fraze_cs=""
    if [[ "$BEZ_FRAZI" == "0" ]]; then
        fraze="${FRAZE[$radek]:-}"
        fraze_cs="${FRAZE_PREKLAD[$radek]:-}"
    fi
    local nazev
    nazev=$(_nazev "$jazyk")
    [[ "$JEN_NEZNAMA" == "1" ]] && nazev=$(_t neznama.nazev "$nazev")

    local prvni druhy prvni_jazyk druhy_jazyk titulek vlajka="${VLAJKY[$(_kod "$jazyk")]}"
    if [[ "$swap" == "1" ]]; then
        prvni="$cz";   prvni_jazyk="$ZDROJ"
        druhy="$orig"; druhy_jazyk="$jazyk"
        titulek="${VLAJKY[$ZDROJ]} $cislo/$celkem  →  $vlajka"
    else
        prvni="$orig"; prvni_jazyk="$jazyk"
        druhy="$cz";   druhy_jazyk="$ZDROJ"
        titulek="$vlajka $cislo/$celkem  →  ${VLAJKY[$ZDROJ]}"
    fi

    _view KARTA "$titulek  │  $nazev" "$prvni" "$druhy" "$fraze" "$fraze_cs"
    # printf: data v %s se nezpracovávají jako escape sekvence (na rozdíl od echo -e)
    clear
    _vypis_kartu "$titulek" "$nazev" "$prvni" "$druhy" "$fraze" "$fraze_cs"

    _precti "$prvni" "$prvni_jazyk" "$druhy" "$druhy_jazyk" "$fraze" "$jazyk"
}

# Přehraje aktuální slovíčko znovu (karta zůstává)
_precti_znovu() {
    local radek="$1" jazyk="$2" swap="$3"
    if [[ "$GR" == "1" ]]; then
        _precti "${GR_ZDROJ[$radek]}" "$ZDROJ" "${GR_CIL[$radek]}" "$jazyk" \
                "$(_gr_dosl_tts "${GR_DOSL[$radek]}")" "$ZDROJ"
        return
    fi
    local orig="${radek%% — *}" cz="${radek#* — }" fraze=""
    [[ "$BEZ_FRAZI" == "0" ]] && fraze="${FRAZE[$radek]:-}"
    if [[ "$swap" == "1" ]]; then
        _precti "$cz" "$ZDROJ" "$orig" "$jazyk" "$fraze" "$jazyk"
    else
        _precti "$orig" "$jazyk" "$cz" "$ZDROJ" "$fraze" "$jazyk"
    fi
}

# ── Nápověda a klávesy ──────────────────────────────────────────
# _napoveda stav — stav: cte (právě se čte), pauza, ceka (dočteno, čeká se na odpověď)
_napoveda() {
    local stav="$1" t v mezera
    mezera=$(_t k.mezera)
    case "$stav" in
        pauza) t="\e[1;33m⏸ $(_t w.pauza)\e[0;90m · [␣] $(_t w.dal)"
               v="*⏸ $(_t w.pauza_nadpis)* · [$mezera] $(_t w.play)" ;;
        cte)   t="[␣] $(_t w.pauza)"; v="[$mezera] $(_t w.pauza)" ;;
        *)     t="[␣] $(_t w.znovu)"; v="[$mezera] $(_t w.play)" ;;
    esac
    # terminál: zkráceně, aby se vešla i do úzkého terminálu
    t+=" · [⏎] $(_t w.znam) · [n] $(_t w.neznam)"
    v+=" · [Enter] $(_t w.znam) · [n] $(_t w.neznam) · [z] $(_t w.znovu)"
    if [[ -n "${FRAZE[$AKT_RADEK]:-}" ]]; then
        if (( AKT_OZNACENO )); then
            t+=" · \e[1;31m✗\e[0;90m"; v+=" · *✗ $(_t w.fraze_oznacena)*"
        else
            t+=" · [x] $(_t w.chyba)"; v+=" · [x] $(_t w.chybna_fraze)"
        fi
    fi
    _view NAPOVEDA "$v · [q] $(_t w.konec)"
    printf '\r\e[K\e[0;90m%b · [q] %s\e[0m' "$t" "$(_t w.konec)"
}

_oznac() {
    (( ! AKT_OZNACENO )) && _oznac_chybnou "$AKT_JAZYK" "$AKT_RADEK" && AKT_OZNACENO=1
    return 0
}

# Přečte slovíčko, překlad a frázi na pozadí a mezitím obsluhuje klávesy:
#   [mezera] pauza / pokračovat · [z] od začátku · [x] chybná fráze
#   [Enter] / [n] / [q] odpověď hned (čtení se přeruší) → ODPOVED, ODPOVED_ZADANA=1
_precti() {
    local prvni="$1" prvni_jazyk="$2" druhy="$3" druhy_jazyk="$4" fraze="$5" jazyk="$6"
    local klavesa pozastaveno znovu
    while :; do
        (
            trap _uklid_tts EXIT       # podproces nedědí trapy hlavního skriptu
            _tts_reci "$prvni" "$prvni_jazyk"
            sleep "$PAUZA_PO_ORIG"
            _tts_reci "$druhy" "$druhy_jazyk"
            if [[ -n "$fraze" ]]; then
                sleep "$PAUZA_PRED_FRAZI"
                _tts_reci "$fraze" "$jazyk"
            fi
            sleep "$PAUZA_PO_PREKLADU"
        ) </dev/null 2>/dev/null &     # 2>/dev/null: bez hlášky „Terminated“
        TTS_PID=$!
        pozastaveno=0 znovu=0
        _napoveda cte
        while kill -0 "$TTS_PID" 2>/dev/null; do
            IFS= read -r -t 0.1 klavesa
            case $? in
                0) ;;
                1) klavesa=q ;;                 # konec vstupu (zavřené okno)
                *) continue ;;                  # vypršel čas, nic nestisknuto
            esac
            case "${klavesa,,}" in
                " ")
                    if (( pozastaveno )); then
                        _signal_tts CONT; pozastaveno=0; _napoveda cte
                    else
                        _signal_tts STOP; pozastaveno=1; _napoveda pauza
                    fi ;;
                z) znovu=1; _signal_tts CONT; _signal_tts TERM ;;
                x) _oznac; _napoveda "$( (( pozastaveno )) && echo pauza || echo cte)" ;;
                *) ODPOVED="$klavesa"; ODPOVED_ZADANA=1
                   _signal_tts CONT; _signal_tts TERM ;;
            esac
        done
        wait "$TTS_PID" 2>/dev/null
        TTS_PID=""
        (( znovu )) || return 0       # [z]: číst znovu od začátku
    done
}

# Uloží výsledky kola: neznámá přidá do neznama/<mateřský>-<cíl>.txt,
# v režimu --neznama v 1. kole známá ze souboru odebere.
# _zapis_vysledky jazyk cislo_kola jmeno_pole_neznamych jmeno_pole_znamych
_zapis_vysledky() {
    local jazyk="$1" kolo="$2"
    local -n _nez="$3" _zn="$4"
    _neznama_pridej "$jazyk" "${_nez[@]}"
    if [[ "$JEN_NEZNAMA" == "1" && "$kolo" == "1" ]]; then
        _neznama_odeber "$jazyk" "${_zn[@]}"
    fi
}

# _kolo jazyk swap jmeno_pole [cislo_kola]
_kolo() {
    local jazyk="$1" swap="$2" kolo="${4:-1}"
    local -n _vstup="$3"            # nameref: alias pro pole volajícího
    local -a pole_slov=("${_vstup[@]}")
    local celkem=${#pole_slov[@]}
    local -a neznama=() znama=()

    _view ZPRAVA "$(_t kolo.zacinam "$kolo")" "$(_t kolo.slovicek "$celkem")"
    echo -e "\e[1;32m\n$(_t kolo.zacinam "$kolo"): $(_t kolo.slovicek "$celkem")\e[0m"
    echo -e "\e[0;90m  [Enter] = $(_t w.znam) │ [n] = $(_t w.neznam) │ [q] = $(_t w.konec)\e[0m\n"
    sleep 0.5

    local i=1 radek odpoved
    for radek in "${pole_slov[@]}"; do
        AKT_RADEK="$radek" AKT_JAZYK="$jazyk" AKT_OZNACENO=0 ODPOVED_ZADANA=0
        _zobraz_slovicko "$radek" "$jazyk" "$swap" "$i" "$celkem"

        # Dočteno: čeká se na odpověď. [mezera] / [z] přehraje slovíčko znovu,
        # [x] označí frázi jako chybnou; pak se čeká dál.
        while :; do
            if (( ODPOVED_ZADANA )); then        # odpověď přišla už během čtení
                odpoved="$ODPOVED"; ODPOVED_ZADANA=0
            else
                _napoveda ceka
                IFS= read -r odpoved || odpoved=q      # konec vstupu (zavřené okno)
            fi
            case "${odpoved,,}" in
                " "|z) _precti_znovu "$radek" "$jazyk" "$swap"; continue ;;
                x) _oznac; printf '\e[1A'; continue ;;   # zpět na řádek s nápovědou
            esac
            break
        done

        case "${odpoved,,}" in
            q) _zapis_vysledky "$jazyk" "$kolo" neznama znama
               echo -e "\n\e[1;31m$(_t ukonceno $((i-1)))\e[0m"
               exit 0 ;;
            n|ne) neznama+=("$radek") ;;
            *) znama+=("$radek") ;;
        esac

        (( ++i ))
    done

    _zapis_vysledky "$jazyk" "$kolo" neznama znama
    clear

    local pocet_znamych=$(( celkem - ${#neznama[@]} ))
    echo -e "\e[1;32m\n$(_t kolo.hotovo)\e[0m"
    printf "  \e[1;32m%s\e[0m\n" "$(_t kolo.znam "$pocet_znamych" "$celkem")"
    printf "  \e[1;31m%s\e[0m\n" "$(_t kolo.neznam "${#neznama[@]}" "$celkem")"

    local souhrn
    souhrn="$(_t kolo.znam "$pocet_znamych" "$celkem")\n$(_t kolo.neznam "${#neznama[@]}" "$celkem")"
    if [[ ${#neznama[@]} -gt 0 ]]; then
        _view ZPRAVA "$(_t kolo.hotovo)" "$souhrn" "$(_t kolo.opakovat "${#neznama[@]}") $(_t kolo.ano_ne)"
        echo -en "\n\e[1;33m  $(_t kolo.opakovat "${#neznama[@]}") $(_t kolo.ano_ne_term): \e[0m"
        local volba
        read -r volba || volba=n
        if [[ "${volba,,}" != "n" ]]; then
            local -a zamichana
            # shellcheck disable=SC2034  # předává se jménem (nameref)
            mapfile -t zamichana < <(printf '%s\n' "${neznama[@]}" | shuf)
            _kolo "$jazyk" "$swap" zamichana $(( kolo + 1 ))
        fi
    else
        _view ZPRAVA "$(_t kolo.hotovo)" "$souhrn\n\n$(_t kolo.vyborne)"
        sleep 2
        echo -e "\n\e[1;32m  $(_t kolo.vyborne)\e[0m"
    fi
}

_na_preruseni() {
    echo -e "\n\n\e[1;33m$(_t preruseno)\e[0m"
    exit 0
}
trap _na_preruseni INT TERM HUP    # HUP = zavřené okno
trap _uklid EXIT

main() {
    local jazyk="" swap="0" poradi_zadano="0" kod
    local i=0
    local -a args=("$@")
    while (( i < ${#args[@]} )); do
        _spolecna_volba "${args[i]}" "${args[i+1]:-}"
        kod=$?
        if (( kod == 2 )); then (( i += 2 )); continue; fi
        case "${args[i]}" in
            --swap|-s) swap="1"; poradi_zadano="1" ;;
            --orig|-o) swap="0"; poradi_zadano="1" ;;
            --neznama|--unknown|-u) JEN_NEZNAMA=1 ;;
            --bez-frazi|--no-phrases) BEZ_FRAZI=1 ;;
            --pruhledne|-t) ;;   # dřív volba průhledného okna, teď výchozí
            --bez-sumu|--no-noise) BEZ_SUMU=1 ;;
            --intro|intro) INTRO=1 ;;
            --gr|gr|--gramatika|--grammar|-g) GR=1 ;;
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

    # Gramatika: pořadí je pevné (mateřský → cílový → doslovně), cíl podle dostupných dat
    if [[ "$GR" == "1" ]]; then
        swap="0"; poradi_zadano="1"
        [[ -n "$jazyk" ]] || jazyk=$(_gr_vyber_cil) || exit $?
        [[ -n "$jazyk" ]] || exit 0
    fi

    # Výběr jazyka (terminál, GTK nebo rofi…), včetně uložených neznámých a nastavení
    if [[ -z "$jazyk" ]]; then
        _vyber_cil
        jazyk="$VYBRANY_CIL"
        if [[ "$jazyk" == neznama:* ]]; then
            jazyk="${jazyk#neznama:}"
            JEN_NEZNAMA=1
        fi
    fi
    _over_cil "$jazyk"

    if [[ "$poradi_zadano" == "0" && "$V_OKNE" == "0" ]]; then
        swap=$(_vyber_poradi "$jazyk") || exit $?
        [[ -z "$swap" ]] && exit 0
    fi

    if [[ "$GR" == "1" ]]; then
        [[ "$jazyk" == "$(_kod "$jazyk")" && -f "$(_gr_soubor "$jazyk")" ]] \
            || _chyba "$(_t gr.neni "$(_nazev_jazyka "$ZDROJ")")"
        _nacti_gramatiku "$jazyk"
    else
        _nacti_slovnik "$jazyk"
    fi
    (( ${#RADKY[@]} )) || _chyba "$(_t chyba.prazdny "$(_nazev "$jazyk")" "$(_nazev_jazyka "$ZDROJ")")"
    if [[ "$JEN_NEZNAMA" == "1" && ! -s "$(_soubor_neznamych "$jazyk")" ]]; then
        _chyba "$(_t chyba.zadna_neznama "$(_nazev "$jazyk")")"
    fi

    # Mimo okno: otevřít průhledné okno a spustit procvičování v něm
    local -a argumenty=("$jazyk" --z "$ZDROJ" --locale "$LOCALE")
    if [[ "$swap" == "1" ]]; then argumenty+=(--swap); else argumenty+=(--orig); fi
    [[ "$JEN_NEZNAMA" == "1" ]] && argumenty+=(--neznama)
    [[ "$BEZ_FRAZI" == "1" ]] && argumenty+=(--bez-frazi)
    [[ "$BEZ_SUMU" == "1" ]] && argumenty+=(--bez-sumu)
    [[ "$INTRO" == "1" ]] && argumenty+=(--intro)
    [[ "$GR" == "1" ]] && argumenty+=(--gr)
    if _lze_otevrit_okno; then
        _spust_v_okne radky "${argumenty[@]}"
        trap - EXIT
        exit 0
    fi

    [[ "$INTRO" == "1" ]] && _intro_spust
    [[ "$BEZ_FRAZI" == "0" && "$GR" == "0" ]] && _nacti_fraze "$jazyk"
    _pozadi_spust "$BEZ_SUMU"

    local -a slovicka
    if [[ "$JEN_NEZNAMA" == "1" ]]; then
        mapfile -t slovicka < <(_slovicka "$jazyk" neznama | shuf | head -n "$POCET_KOLO")
    else
        mapfile -t slovicka < <(_slovicka "$jazyk" | shuf | head -n "$POCET_KOLO")
    fi

    echo -e "\n\e[1;32m$(_t nacteno "${#slovicka[@]}" "$(_nazev "$jazyk") → $(_nazev_jazyka "$ZDROJ" vlajka)")\e[0m"
    sleep 0.8

    clear
    _kolo "$jazyk" "$swap" slovicka

    _view ZPRAVA "$(_t trenink.hotovo)" "" "*$(_t zavrit.enter)*"
    echo -e "\n\e[1;32m$(_t trenink.hotovo)\e[0m"
    if [[ "$V_OKNE" != "0" ]]; then
        echo -en "\e[0;90m$(_t zavrit.enter)\e[0m"
        read -r
    fi
}

main "$@"
