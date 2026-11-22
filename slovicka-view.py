#!/usr/bin/env python3
"""Průhledné okno pro procvičování slovíček ve stylu poznámek (pozt z ~/Projects/Pango-view).

Použití: slovicka-view.py --rezim znaky|radky -- <skript> [argumenty …]

Spustí <skript> (slovicka-pasivni.sh / slovicka-interaktivni.sh) s proměnnou SLOVICKA_V_OKNE=2.
Skript posílá příkazy na deskriptor $SLOVICKA_FD (řádek, pole oddělená tabulátorem):
  KARTA     hlavička  první  druhý  fráze  fráze_cs
  NAPOVEDA  text                     (*text* = zvýraznit)
  ZPRAVA    nadpis  text  [nápověda]  (\\n v textu = nový řádek)
Stisknuté klávesy jdou skriptu na stdin: v režimu „znaky“ jako znak (pasivní poslech, read -n1),
v režimu „radky“ jako řádek (interaktivní, read -r; Enter = prázdný řádek).

Ovládání okna: = / - / 0 zoom · tažení myší přesun · zavření okna = konec skriptu.
Proměnné: SLOVICKA_STYL (0–9, barvy jako styly poznámek, výchozí 0), SLOVICKA_ALFA (hex 00–ff,
výchozí POZNAMKA_ALFA nebo b3), SLOVICKA_ZOOM (výchozí 1), SLOVICKA_SIRKA (výchozí 760).
"""
import locale
import os
import re
import signal
import subprocess
import sys

# Nevygenerované locale → GTK hlásí „Locale not supported by C library“
try:
    locale.setlocale(locale.LC_ALL, "")
except locale.Error:
    os.environ["LC_ALL"] = "C.UTF-8"
    locale.setlocale(locale.LC_ALL, "C.UTF-8")

# Vykreslovat jen na integrovaném AMD GPU (jako poznamka-view.py), aby se dGPU mohlo uspat
os.environ.setdefault("VK_DRIVER_FILES", "/usr/share/vulkan/icd.d/radeon_icd.json")
os.environ.setdefault("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json")

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

CSS = b"window, window.background { background: transparent; box-shadow: none; }"
KROK = 1.2

# Styly 0–9 podle poznamka.zsh: pozadí, text, zvýraznění (slovíčko), fráze, font
STYLY = {
    0: ("#071e22", "#f4c095", "#ffd166", "#7fd1c7", "monospace"),
    1: ("#fff176", "#3e2723", "#bf360c", "#1b5e20", "Sans"),
    2: ("#5A0E24", "#f4c095", "#ffd166", "#f7a8b8", "monospace"),
    3: ("#001F3D", "#cfe3ff", "#ffd166", "#7fdbff", "JetBrainsMono NF"),
    4: ("#2e3440", "#a3be8c", "#ebcb8b", "#88c0d0", "JetBrainsMono NF Light"),
    5: ("#f5ecd7", "#3b2f2f", "#8b1e1e", "#2e5e4e", "DejaVu Serif"),
    6: ("#c8f7dc", "#1b4332", "#9d0208", "#1d3557", "Sans"),
    7: ("#ffb3c7", "#4a0e2e", "#7b002c", "#3d0066", "Sans"),
    8: ("#b71c1c", "#ffffff", "#ffeb3b", "#ffe0b2", "Sans"),
    9: ("#111111", "#fafafa", "#ffd54f", "#80deea", "AtkynsonMono NF"),
}

# Klávesy předávané skriptu: keyval → znak
KLAVESY = {"space": " ", "z": "z", "Z": "z", "x": "x", "X": "x", "n": "n", "N": "n",
           "q": "q", "Q": "q", "Escape": "q", "Return": "", "KP_Enter": ""}


def esc(text):
    return GLib.markup_escape_text(text or "")


def rgb(hex_barva):
    h = hex_barva.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


class Karta(Gtk.ApplicationWindow):
    def __init__(self, app, rezim, prikaz):
        super().__init__(application=app, decorated=False, resizable=False)
        self.set_title("Slovíčka")
        self.rezim = rezim
        styl = int(os.environ.get("SLOVICKA_STYL", "0") or 0)
        self.bg, self.fg, self.akcent, self.fraze, self.font = STYLY.get(styl, STYLY[0])
        alfa = os.environ.get("SLOVICKA_ALFA") or os.environ.get("POZNAMKA_ALFA") or "b3"
        self.alfa = int(alfa, 16) / 255
        self.zoom = float(os.environ.get("SLOVICKA_ZOOM", "1") or 1)
        self.sirka = int(os.environ.get("SLOVICKA_SIRKA", "760") or 760)
        self.obsah, self.napoveda = "", ""

        self.plocha = Gtk.DrawingArea()
        self.plocha.set_draw_func(self.kresli)
        self.set_child(self.plocha)

        klavesy = Gtk.EventControllerKey()
        klavesy.connect("key-pressed", self.klavesa)
        self.add_controller(klavesy)
        tazeni = Gtk.GestureClick()
        tazeni.connect("pressed", self.presun)
        self.plocha.add_controller(tazeni)
        self.connect("close-request", self.zavrit)

        self.zprava("Slovíčka", "Načítám…")
        self.spust(prikaz)

    # ── Skript ───────────────────────────────────────────────────
    def spust(self, prikaz):
        cti, pis = os.pipe()
        env = dict(os.environ, SLOVICKA_V_OKNE="2", SLOVICKA_FD=str(pis))
        # vlastní skupina procesů → při zavření okna jde ukončit i piper/mpv
        self.proces = subprocess.Popen(prikaz, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                       pass_fds=(pis,), env=env, start_new_session=True)
        os.close(pis)
        self.kanal = GLib.IOChannel.unix_new(cti)
        self.kanal.set_encoding("utf-8")
        GLib.io_add_watch(self.kanal, GLib.PRIORITY_DEFAULT,
                          GLib.IOCondition.IN | GLib.IOCondition.HUP, self.prijem)

    def prijem(self, kanal, podminka):
        if podminka & GLib.IOCondition.IN:
            try:
                radek = kanal.readline()
            except GLib.Error:
                radek = ""
            if radek:
                self.prikaz(radek.rstrip("\n").split("\t"))
                return True
        # konec skriptu → zavřít okno
        self.get_application().quit()
        return False

    def prikaz(self, pole):
        druh, *data = pole
        data += [""] * 6
        if druh == "KARTA":
            self.karta(*data[:5])
        elif druh == "NAPOVEDA":
            self.napoveda = data[0]
            self.prekresli()
        elif druh == "ZPRAVA":
            self.zprava(data[0], data[1], data[2])

    def posli(self, znak):
        text = znak + "\n" if self.rezim == "radky" else (znak or "\n")
        try:
            self.proces.stdin.write(text.encode())
            self.proces.stdin.flush()
        except (BrokenPipeError, ValueError, OSError):
            pass

    def ukonci_skript(self):
        if self.proces.poll() is None:
            try:
                os.killpg(self.proces.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    def zavrit(self, *_):
        self.ukonci_skript()
        return False

    # ── Obsah ────────────────────────────────────────────────────
    def velikost(self, body):
        return f'size="{round(body * 1024 * self.zoom)}"'

    def karta(self, hlavicka, prvni, druhy, fraze, fraze_cs):
        casti = [
            f'<span {self.velikost(10)} alpha="65%">{esc(hlavicka)}</span>',
            "",
            f'<span {self.velikost(22)} weight="bold" foreground="{self.akcent}">{esc(prvni)}</span>',
            f'<span {self.velikost(16)}>{esc(druhy)}</span>',
        ]
        if fraze:
            casti += ["", f'<span {self.velikost(13)} style="italic" foreground="{self.fraze}">{esc(fraze)}</span>',
                      f'<span {self.velikost(12)} alpha="70%">{esc(fraze_cs)}</span>']
        self.obsah, self.napoveda = "\n".join(casti), ""
        self.prekresli()

    def zprava(self, nadpis, text, napoveda=""):
        radky = esc(text).replace("\\n", "\n")
        self.obsah = (f'<span {self.velikost(18)} weight="bold" foreground="{self.akcent}">{esc(nadpis)}</span>'
                      f'\n\n<span {self.velikost(13)}>{radky}</span>')
        self.napoveda = napoveda
        self.prekresli()

    def markup_napovedy(self):
        text = re.sub(r"\*([^*]+)\*", rf'<span weight="bold" foreground="{self.akcent}">\1</span>',
                      esc(self.napoveda))
        return f'<span {self.velikost(10)} alpha="60%">{text}</span>'

    # ── Vykreslení ───────────────────────────────────────────────
    def okraj(self):
        return round(28 * self.zoom)

    def layouty(self):
        sirka_textu = round(self.sirka * self.zoom) - 2 * self.okraj()
        vysledek = []
        for markup in (self.obsah, self.markup_napovedy() if self.napoveda else ""):
            lay = self.plocha.create_pango_layout(None)
            lay.set_font_description(Pango.FontDescription.from_string(self.font))
            lay.set_width(sirka_textu * Pango.SCALE)
            lay.set_wrap(Pango.WrapMode.WORD_CHAR)
            lay.set_markup(markup, -1)
            vysledek.append(lay)
        return vysledek

    def prekresli(self):
        obsah, napoveda = self.layouty()
        m = self.okraj()
        vyska = 2 * m + obsah.get_pixel_size()[1]
        if self.napoveda:
            vyska += round(18 * self.zoom) + napoveda.get_pixel_size()[1]
        vyska = max(vyska, round(260 * self.zoom))
        self.plocha.set_content_width(round(self.sirka * self.zoom))
        self.plocha.set_content_height(vyska)
        self.plocha.queue_draw()

    def kresli(self, _plocha, cr, sirka, vyska):
        r, g, b = rgb(self.bg)
        cr.set_source_rgba(r, g, b, self.alfa)
        cr.paint()
        obsah, napoveda = self.layouty()
        m = self.okraj()
        r, g, b = rgb(self.fg)
        cr.set_source_rgb(r, g, b)
        cr.move_to(m, m)
        PangoCairo.show_layout(cr, obsah)
        if self.napoveda:
            cr.move_to(m, vyska - m - napoveda.get_pixel_size()[1])
            PangoCairo.show_layout(cr, napoveda)

    # ── Ovládání ─────────────────────────────────────────────────
    def klavesa(self, _ctl, keyval, _code, _stav):
        k = Gdk.keyval_name(keyval)
        if k in ("equal", "plus", "KP_Add"):
            self.zoom *= KROK
        elif k in ("minus", "KP_Subtract"):
            self.zoom /= KROK
        elif k in ("0", "KP_0"):
            self.zoom = 1.0
        elif k in KLAVESY:
            self.posli(KLAVESY[k])
            return True
        else:
            return False
        self.prekresli()
        return True

    def presun(self, gesto, _n, x, y):
        povrch = self.get_surface()
        if isinstance(povrch, Gdk.Toplevel):
            povrch.begin_move(gesto.get_device(), gesto.get_current_button(), x, y,
                              gesto.get_current_event_time())


def main():
    argv = sys.argv[1:]
    rezim = "znaky"
    if len(argv) >= 2 and argv[0] == "--rezim":
        rezim, argv = argv[1], argv[2:]
    if argv[:1] == ["--"]:
        argv = argv[1:]
    if not argv:
        print((__doc__ or "").strip(), file=sys.stderr)
        return 1

    app = Gtk.Application(application_id="cz.slovicka.view", flags=Gio.ApplicationFlags.NON_UNIQUE)
    okno = []

    def start(app):
        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        okno.append(Karta(app, rezim, argv))
        okno[0].present()

    app.connect("activate", start)
    kod = app.run([sys.argv[0]])
    if okno:
        okno[0].ukonci_skript()
    return kod


if __name__ == "__main__":
    sys.exit(main())
