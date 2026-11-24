#!/usr/bin/env bash
# ================================================================
# slovicka-interaktivni.sh
# Interaktivní procvičování slovíček s TTS v průhledném okně (slovicka-view.py)
# Použití: ./slovicka-interaktivni.sh [jazyk] [--swap|--orig] [--neznama] [--bez-frazi] [--bez-sumu] [--intro]
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
readonly PAUZA_PO_CZ=0.5
readonly PAUZA_PRED_FRAZI=0.8

# 1 = procvičují se jen uložená neznámá slovíčka (--neznama)
JEN_NEZNAMA=0
# 1 = nezobrazovat a nečíst vzorové fráze (--bez-frazi)
BEZ_FRAZI=0
# 1 = bez tichého šumu na pozadí (--bez-sumu)
BEZ_SUMU=0
# 1 = před procvičováním intro s obrázkem a hudbou (--intro)
INTRO=0

# Stav aktuálního slovíčka (čtení běží na pozadí, klávesy se obsluhují mezitím)
AKT_RADEK=""
AKT_JAZYK=""
AKT_OZNACENO=0
# Odpověď zadaná už během čtení ([Enter]/[n]/[q]); ODPOVED_ZADANA=1 = platí
ODPOVED=""
ODPOVED_ZADANA=0

# ── Funkce ──────────────────────────────────────────────────────

_pouziti() {
    echo "Použití: $0 [jazyk] [volby]"
    echo ""
    echo "Jazyky: $(_seznam_jazyku)"
    echo ""
    echo "Volby:"
    echo "  --swap, -s      Nejdříve česky, pak originál"
    echo "  --orig, -o      Nejdříve originál, pak česky (bez dotazu)"
    echo "  --neznama, -u   Procvičit jen dříve neznámá slovíčka"
    echo "  --bez-frazi     Nezobrazovat a nečíst vzorové fráze"
    echo "  --bez-sumu      Bez tichého šumu na pozadí (drží BT reproduktor vzhůru)"
    echo "  --intro, intro  Před procvičováním ${INTRO_DELKA} s úvodní obrázek s hudbou, pak ${INTRO_PAUZA} s pauza"
    echo ""
    echo "Ovládání v okně: [Enter] znám · [n] neznám · [z] zopakovat slovíčko · [x] chybná fráze · [q] konec"
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

_zobraz_slovicko() {
    local radek="$1" jazyk="$2" swap="$3" cislo="$4" celkem="$5"
    local orig="${radek%% — *}" cz="${radek#* — }"
    local fraze="" fraze_cs=""
    if [[ "$BEZ_FRAZI" == "0" ]]; then
        fraze="${FRAZE[$radek]:-}"
        fraze_cs="${FRAZE_CS[$radek]:-}"
    fi
    local nazev="${NAZVY[$jazyk]}"
    [[ "$JEN_NEZNAMA" == "1" ]] && nazev="Neznámá: $nazev"

    local prvni druhy prvni_jazyk druhy_jazyk titulek
    if [[ "$swap" == "1" ]]; then
        prvni="$cz";   prvni_jazyk="cs"
        druhy="$orig"; druhy_jazyk="$jazyk"
        titulek="🇨🇿 $cislo/$celkem  →  ${VLAJKY[$jazyk]}"
    else
        prvni="$orig"; prvni_jazyk="$jazyk"
        druhy="$cz";   druhy_jazyk="cs"
        titulek="${VLAJKY[$jazyk]} $cislo/$celkem  →  🇨🇿"
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
    local orig="${radek%% — *}" cz="${radek#* — }" fraze=""
    [[ "$BEZ_FRAZI" == "0" ]] && fraze="${FRAZE[$radek]:-}"
    if [[ "$swap" == "1" ]]; then
        _precti "$cz" cs "$orig" "$jazyk" "$fraze" "$jazyk"
    else
        _precti "$orig" "$jazyk" "$cz" cs "$fraze" "$jazyk"
    fi
}

# ── Nápověda a klávesy ──────────────────────────────────────────
# _napoveda stav — stav: cte (právě se čte), pauza, ceka (dočteno, čeká se na odpověď)
_napoveda() {
    local stav="$1" t v
    case "$stav" in
        pauza) t="\e[1;33m⏸ pauza\e[0;90m · [␣] dál"; v="*⏸ Pauza* · [mezera] play" ;;
        cte)   t="[␣] pauza"; v="[mezera] pauza" ;;
        *)     t="[␣] znovu"; v="[mezera] play" ;;
    esac
    # terminál: zkráceně, aby se vešla i do úzkého terminálu
    t+=" · [⏎] znám · [n] neznám"
    v+=" · [Enter] znám · [n] neznám · [z] znovu"
    if [[ -n "${FRAZE[$AKT_RADEK]:-}" ]]; then
        if (( AKT_OZNACENO )); then
            t+=" · \e[1;31m✗\e[0;90m"; v+=" · *✗ fráze označena*"
        else
            t+=" · [x] chyba"; v+=" · [x] chybná fráze"
        fi
    fi
    _view NAPOVEDA "$v · [q] konec"
    printf '\r\e[K\e[0;90m%b · [q] konec\e[0m' "$t"
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
            sleep "$PAUZA_PO_CZ"
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

# Uloží výsledky kola: neznámá přidá do neznama_<jazyk>.txt,
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

    _view ZPRAVA "▶ Začínám kolo $kolo" "$celkem slovíček"
    echo -e "\e[1;32m\n▶ Začínám kolo: $celkem slovíček\e[0m"
    echo -e "\e[0;90m  [Enter] = znám │ [n/N] = neznám │ [q/Q] = konec\e[0m\n"
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
               echo -e "\n\e[1;31mUkončeno po $((i-1)) slovíčkách.\e[0m"
               exit 0 ;;
            n|ne) neznama+=("$radek") ;;
            *) znama+=("$radek") ;;
        esac

        (( ++i ))
    done

    _zapis_vysledky "$jazyk" "$kolo" neznama znama
    clear

    local pocet_znamych=$(( celkem - ${#neznama[@]} ))
    echo -e "\e[1;32m\n✓ Kolo dokončeno!\e[0m"
    printf "  Znám:   \e[1;32m%d/%d\e[0m\n" "$pocet_znamych" "$celkem"
    printf "  Neznám: \e[1;31m%d/%d\e[0m\n" "${#neznama[@]}" "$celkem"

    local souhrn="Znám: $pocet_znamych/$celkem\nNeznám: ${#neznama[@]}/$celkem"
    if [[ ${#neznama[@]} -gt 0 ]]; then
        _view ZPRAVA "✓ Kolo dokončeno!" "$souhrn" "Opakovat ${#neznama[@]} neznámých? *[Enter] ano* · [n] ne"
        echo -en "\n\e[1;33m  Opakovat ${#neznama[@]} neznámých? [Enter=ano / n=ne]: \e[0m"
        local volba
        read -r volba || volba=n
        if [[ "${volba,,}" != "n" ]]; then
            local -a zamichana
            # shellcheck disable=SC2034  # předává se jménem (nameref)
            mapfile -t zamichana < <(printf '%s\n' "${neznama[@]}" | shuf)
            _kolo "$jazyk" "$swap" zamichana $(( kolo + 1 ))
        fi
    else
        _view ZPRAVA "✓ Kolo dokončeno!" "$souhrn\n\n🎉 Výborně! Znáš všechna slovíčka!"
        sleep 2
        echo -e "\n\e[1;32m  🎉 Výborně! Znáš všechna slovíčka!\e[0m"
    fi
}

_na_preruseni() {
    echo -e "\n\n\e[1;33mPřerušeno.\e[0m"
    exit 0
}
trap _na_preruseni INT TERM HUP    # HUP = zavřené okno
trap _uklid EXIT

main() {
    local jazyk="" swap="0" poradi_zadano="0" arg

    for arg in "$@"; do
        case "$arg" in
            --swap|-s) swap="1"; poradi_zadano="1" ;;
            --orig|-o) swap="0"; poradi_zadano="1" ;;
            --neznama|-u) JEN_NEZNAMA=1 ;;
            --bez-frazi) BEZ_FRAZI=1 ;;
            --pruhledne|-t) ;;   # dřív volba průhledného okna, teď výchozí
            --bez-sumu) BEZ_SUMU=1 ;;
            --intro|intro) INTRO=1 ;;
            -h|--help) _pouziti 0 ;;
            *)
                if _je_jazyk "$arg"; then
                    jazyk="$arg"
                else
                    echo "Neznámý argument: $arg" >&2
                    _pouziti 1 >&2
                fi ;;
        esac
    done

    # Výběr jazyka (terminál nebo rofi), včetně uložených neznámých
    if [[ -z "$jazyk" ]]; then
        jazyk=$(_vyber_jazyk) || exit $?
        [[ -z "$jazyk" ]] && exit 0
        if [[ "$jazyk" == neznama:* ]]; then
            jazyk="${jazyk#neznama:}"
            JEN_NEZNAMA=1
        fi
    fi

    if [[ "$poradi_zadano" == "0" && "$V_OKNE" == "0" ]]; then
        swap=$(_vyber_poradi) || exit $?
        [[ -z "$swap" ]] && exit 0
    fi

    local soubor
    if [[ "$JEN_NEZNAMA" == "1" ]]; then
        soubor=$(_soubor_neznamych "$jazyk")
        [[ -s "$soubor" ]] || _chyba "Zatím nemáš uložená žádná neznámá slovíčka (${NAZVY[$jazyk]})."
    else
        soubor="${SOUBORY[$jazyk]}"
        [[ -f "$soubor" ]] || _chyba "Soubor nenalezen: $soubor"
    fi

    # Mimo okno: otevřít průhledné okno a spustit procvičování v něm
    local -a argumenty=("$jazyk")
    if [[ "$swap" == "1" ]]; then argumenty+=(--swap); else argumenty+=(--orig); fi
    [[ "$JEN_NEZNAMA" == "1" ]] && argumenty+=(--neznama)
    [[ "$BEZ_FRAZI" == "1" ]] && argumenty+=(--bez-frazi)
    [[ "$BEZ_SUMU" == "1" ]] && argumenty+=(--bez-sumu)
    [[ "$INTRO" == "1" ]] && argumenty+=(--intro)
    if _lze_otevrit_okno; then
        _spust_v_okne radky "${argumenty[@]}"
        trap - EXIT
        exit 0
    fi

    [[ "$INTRO" == "1" ]] && _intro_spust
    [[ "$BEZ_FRAZI" == "0" ]] && _nacti_fraze "$jazyk"
    _pozadi_spust "$BEZ_SUMU"

    local -a slovicka
    mapfile -t slovicka < <(grep ' — ' "$soubor" | shuf | head -n "$POCET_KOLO")

    echo -e "\n\e[1;32mNačteno ${#slovicka[@]} slovíček z: $soubor\e[0m"
    sleep 0.8

    clear
    _kolo "$jazyk" "$swap" slovicka

    _view ZPRAVA "✓ Trénink dokončen." "" "*[Enter]* zavřít okno"
    echo -e "\n\e[1;32m✓ Trénink dokončen.\e[0m"
    if [[ "$V_OKNE" != "0" ]]; then
        echo -en "\e[0;90m[Enter] zavřít okno\e[0m"
        read -r
    fi
}

main "$@"
