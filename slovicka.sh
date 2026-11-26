#!/usr/bin/env bash
# ================================================================
# slovicka.sh — společný spouštěč (alias jaz)
# Výchozí je interaktivní procvičování; pasivní poslech volbou --pasivni / --passive (nebo jen „pasivni“).
# Ostatní argumenty se předají vybranému skriptu beze změny.
#   slovicka.sh de --intro           → slovicka-interaktivni.sh de --intro
#   slovicka.sh --pasivni it -n 50   → slovicka-pasivni.sh it -n 50
#   slovicka.sh gr                   → gramatika (jen interaktivní; zatím en↔cs)
# ================================================================

adresar=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
skript="$adresar/slovicka-interaktivni.sh"
argumenty=()

for arg in "$@"; do
    case "$arg" in
        --pasivni|pasivni|--passive|passive|-P) skript="$adresar/slovicka-pasivni.sh" ;;
        --interaktivni|interaktivni|--interactive|interactive|-I) skript="$adresar/slovicka-interaktivni.sh" ;;
        *) argumenty+=("$arg") ;;
    esac
done

exec "$skript" "${argumenty[@]}"
