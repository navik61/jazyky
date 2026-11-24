#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pygobject"]
# ///
"""Průhledné okno pro procvičování slovíček ve stylu poznámek (pozt z ~/Projects/Pango-view).

Použití: slovicka-view.py --rezim znaky|radky -- <skript> [argumenty …]
         slovicka-view.py --vyber "Výzva" položka1 položka2 …

Spustí <skript> (slovicka-pasivni.sh / slovicka-interaktivni.sh) s proměnnou SLOVICKA_V_OKNE=2.
Skript posílá příkazy na deskriptor $SLOVICKA_FD (řádek, pole oddělená tabulátorem):
  KARTA     hlavička  první  druhý  fráze  fráze_cs
  NAPOVEDA  text                     (*text* = zvýraznit)
  ZPRAVA    nadpis  text  [nápověda]  (\\n v textu = nový řádek)
  INTRO     cesta_k_obrázku  šířka    (dialog s obrázkem; q/Esc/mezera/Enter = přeskočit)
  INTRO_KONEC                         (zavře dialog s obrázkem)
Stisknuté klávesy jdou skriptu na stdin: v režimu „znaky“ jako znak (pasivní poslech, read -n1),
v režimu „radky“ jako řádek (interaktivní, read -r; Enter = prázdný řádek).
Přeskočení intra pošle skriptu Enter.

--vyber: nabídka ve stejném stylu (náhrada rofi -dmenu, funguje na každém Waylandu i X11).
Šipky / j k / číslice 1–9 / myš, Enter = vybrat, Esc / q = zrušit. Vypíše pořadové číslo
volby (1..N) a na druhý řádek aktivační token (xdg-activation), aby další okno dostalo fokus.
Při zrušení nevypíše nic a skončí kódem 1.

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

# Vykreslovat jen na integrovaném AMD GPU (jako poznamka-view.py), aby se dGPU mohlo uspat.
# Jen když ty ovladače v systému jsou — jinde (Intel, jen Nvidia) by GTK nemělo čím kreslit.
for _promenna, _soubor in (("VK_DRIVER_FILES", "/usr/share/vulkan/icd.d/radeon_icd.json"),
                           ("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json")):
    if os.path.exists(_soubor):
        os.environ.setdefault(_promenna, _soubor)

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

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


def nacti_texty():
    """Texty rozhraní z locale/<SLOVICKA_LOCALE>.tsv (chybějící klíče z angličtiny)."""
    texty = {}
    adresar = os.path.join(os.path.dirname(os.path.realpath(__file__)), "locale")
    for kod in ("en", os.environ.get("SLOVICKA_LOCALE", "en")):
        try:
            with open(os.path.join(adresar, f"{kod}.tsv"), encoding="utf-8") as f:
                for radek in f:
                    if radek.strip() and not radek.startswith("#") and "\t" in radek:
                        klic, text = radek.rstrip("\n").split("\t", 1)
                        texty[klic] = text
        except OSError:
            pass
    return texty


TEXTY = nacti_texty()


def t(klic):
    return TEXTY.get(klic, klic)


def esc(text):
    return GLib.markup_escape_text(text or "")


def rgb(hex_barva):
    h = hex_barva.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


class Styl:
    """Barvy, písmo a zoom podle SLOVICKA_STYL / SLOVICKA_ALFA / SLOVICKA_ZOOM (karta i nabídka)."""

    def nacti_styl(self):
        styl = int(os.environ.get("SLOVICKA_STYL", "0") or 0)
        self.bg, self.fg, self.akcent, self.fraze, self.font = STYLY.get(styl, STYLY[0])
        alfa = os.environ.get("SLOVICKA_ALFA") or os.environ.get("POZNAMKA_ALFA") or "b3"
        self.alfa = int(alfa, 16) / 255
        self.zoom = float(os.environ.get("SLOVICKA_ZOOM", "1") or 1)
        self.sirka = int(os.environ.get("SLOVICKA_SIRKA", "760") or 760)

    def velikost(self, body):
        return f'size="{round(body * 1024 * self.zoom)}"'

    def okraj(self):
        return round(28 * self.zoom)

    def layout(self, plocha, markup, sirka):
        lay = plocha.create_pango_layout(None)
        lay.set_font_description(Pango.FontDescription.from_string(self.font))
        lay.set_width(sirka * Pango.SCALE)
        lay.set_wrap(Pango.WrapMode.WORD_CHAR)
        lay.set_markup(markup, -1)
        return lay

    def pozadi(self, cr):
        r, g, b = rgb(self.bg)
        cr.set_source_rgba(r, g, b, self.alfa)
        cr.paint()

    def presun(self, gesto, _n, x, y):
        povrch = self.get_surface()
        if isinstance(povrch, Gdk.Toplevel):
            povrch.begin_move(gesto.get_device(), gesto.get_current_button(), x, y,
                              gesto.get_current_event_time())


class Intro(Gtk.Window):
    """Úvodní obrázek. Je to dialog (transient) nad kartou, takže ho všechny kompozitory —
    i dlaždicové (niri, sway, Hyprland) — otevřou jako plovoucí, bez pravidel v konfiguraci."""

    def __init__(self, karta, cesta, sirka):
        super().__init__(transient_for=karta, decorated=False, resizable=False)
        self.set_title(f"{t('app')} – intro")
        self.karta = karta
        # Obrázek zmenšit předem: okno bez změny velikosti má přirozenou velikost obsahu,
        # a ta by jinak byla rozměr fotky (1920×1080)
        vyska = sirka * 9 // 16
        pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(cesta, sirka, vyska, True)
        _ok, png = pixbuf.save_to_bufferv("png", [], [])
        obraz = Gtk.Picture.new_for_paintable(Gdk.Texture.new_from_bytes(GLib.Bytes.new(png)))
        obraz.set_content_fit(Gtk.ContentFit.COVER)
        obraz.set_size_request(sirka, vyska)
        self.set_child(obraz)
        klavesy = Gtk.EventControllerKey()
        klavesy.connect("key-pressed", self.klavesa)
        self.add_controller(klavesy)
        self.connect("close-request", self.zavreno)
        self.preskoceno = False

    def klavesa(self, _ctl, keyval, _code, _stav):
        if Gdk.keyval_name(keyval) in ("q", "Q", "Escape", "space", "Return", "KP_Enter"):
            self.close()
            return True
        return False

    def zavreno(self, *_):
        # Zavřel ho uživatel (klávesou nebo křížkem v kompozitoru) → skript má intro ukončit
        if not self.preskoceno:
            self.karta.posli("")
        self.karta.intro = None
        self.karta.present()
        return False

    def ukonci(self):
        self.preskoceno = True   # ukončuje skript, není co posílat
        self.close()


class Karta(Gtk.ApplicationWindow, Styl):
    def __init__(self, app, rezim, prikaz):
        super().__init__(application=app, decorated=False, resizable=False)
        self.set_title(t("app"))
        self.rezim = rezim
        self.nacti_styl()
        self.obsah, self.napoveda = "", ""
        self.intro = None

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

        self.zprava(t("app"), t("view.nacitam"))
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
        elif druh == "INTRO" and os.path.exists(data[0]):
            if self.intro:
                self.intro.ukonci()
            self.intro = Intro(self, data[0], int(data[1] or 1280))
            self.intro.present()
        elif druh == "INTRO_KONEC" and self.intro:
            self.intro.ukonci()

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
    def layouty(self):
        sirka_textu = round(self.sirka * self.zoom) - 2 * self.okraj()
        return [self.layout(self.plocha, markup, sirka_textu)
                for markup in (self.obsah, self.markup_napovedy() if self.napoveda else "")]

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
        self.pozadi(cr)
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


class Vyber(Gtk.ApplicationWindow, Styl):
    """Nabídka (náhrada rofi -dmenu) ve stylu karty."""

    def __init__(self, app, vyzva, polozky, vysledek):
        super().__init__(application=app, decorated=False, resizable=False)
        self.set_title(f"{t('app')} – {vyzva}")
        self.nacti_styl()
        self.vyzva, self.polozky, self.vysledek = vyzva, polozky, vysledek
        self.zvolena = 0
        self.radky = []          # (y_od, y_do) každé položky po vykreslení — pro klik myší

        self.plocha = Gtk.DrawingArea()
        self.plocha.set_draw_func(self.kresli)
        self.set_child(self.plocha)
        klavesy = Gtk.EventControllerKey()
        klavesy.connect("key-pressed", self.klavesa)
        self.add_controller(klavesy)
        klik = Gtk.GestureClick()
        klik.connect("pressed", self.klik)
        self.plocha.add_controller(klik)
        self.prekresli()

    def markupy(self):
        hlavicka = f'<span {self.velikost(16)} weight="bold" foreground="{self.akcent}">{esc(self.vyzva)}</span>'
        polozky = []
        for i, text in enumerate(self.polozky):
            cislo = f"{i + 1}  " if i < 9 else "   "
            if i == self.zvolena:
                polozky.append(f'<span {self.velikost(14)} weight="bold" foreground="{self.akcent}">'
                               f'▶ {cislo}{esc(text)}</span>')
            else:
                polozky.append(f'<span {self.velikost(14)}>   {cislo}{esc(text)}</span>')
        napoveda = f'<span {self.velikost(10)} alpha="60%">{esc(t("view.vyber_napoveda"))}</span>'
        return hlavicka, polozky, napoveda

    def rozvrh(self):
        sirka_textu = round(self.sirka * self.zoom) - 2 * self.okraj()
        hlavicka, polozky, napoveda = self.markupy()
        return (self.layout(self.plocha, hlavicka, sirka_textu),
                [self.layout(self.plocha, p, sirka_textu) for p in polozky],
                self.layout(self.plocha, napoveda, sirka_textu))

    def prekresli(self):
        hlavicka, polozky, napoveda = self.rozvrh()
        m = self.okraj()
        mezera = round(8 * self.zoom)
        vyska = (2 * m + hlavicka.get_pixel_size()[1] + 2 * mezera
                 + sum(p.get_pixel_size()[1] + mezera for p in polozky)
                 + mezera + napoveda.get_pixel_size()[1])
        self.plocha.set_content_width(round(self.sirka * self.zoom))
        self.plocha.set_content_height(vyska)
        self.plocha.queue_draw()

    def kresli(self, _plocha, cr, _sirka, vyska):
        self.pozadi(cr)
        hlavicka, polozky, napoveda = self.rozvrh()
        m = self.okraj()
        mezera = round(8 * self.zoom)
        cr.set_source_rgb(*rgb(self.fg))
        cr.move_to(m, m)
        PangoCairo.show_layout(cr, hlavicka)
        y = m + hlavicka.get_pixel_size()[1] + 2 * mezera
        self.radky = []
        for p in polozky:
            v = p.get_pixel_size()[1]
            cr.move_to(m, y)
            PangoCairo.show_layout(cr, p)
            self.radky.append((y, y + v + mezera))
            y += v + mezera
        cr.move_to(m, vyska - m - napoveda.get_pixel_size()[1])
        PangoCairo.show_layout(cr, napoveda)

    def potvrd(self, index):
        self.vysledek.append(index + 1)
        # Token pro další okno (xdg-activation): to se pak otevře navrchu a s fokusem i v GNOME/KDE.
        # Musí se vyžádat, dokud má tohle okno fokus.
        try:
            token = self.get_display().get_app_launch_context().get_startup_notify_id(None, [])
        except (TypeError, GLib.Error):
            token = None
        self.vysledek.append(token or "")
        self.close()

    def klavesa(self, _ctl, keyval, _code, _stav):
        k = Gdk.keyval_name(keyval)
        if k in ("Down", "j", "Tab"):
            self.zvolena = (self.zvolena + 1) % len(self.polozky)
        elif k in ("Up", "k", "ISO_Left_Tab"):
            self.zvolena = (self.zvolena - 1) % len(self.polozky)
        elif k in ("Return", "KP_Enter", "space"):
            self.potvrd(self.zvolena)
            return True
        elif k in ("Escape", "q", "Q"):
            self.close()
            return True
        elif k and len(k) == 1 and k.isdigit() and 1 <= int(k) <= min(9, len(self.polozky)):
            self.potvrd(int(k) - 1)
            return True
        else:
            return False
        self.prekresli()
        return True

    def klik(self, gesto, _n, _x, y):
        for i, (od, do) in enumerate(self.radky):
            if od <= y < do:
                self.potvrd(i)
                return
        self.presun(gesto, _n, _x, y)    # mimo položky = přesun okna


def css_pruhledne():
    css = Gtk.CssProvider()
    css.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def hlavni_vyber(vyzva, polozky):
    if not polozky:
        return 1
    app = Gtk.Application(application_id="cz.slovicka.vyber", flags=Gio.ApplicationFlags.NON_UNIQUE)
    vysledek = []

    def start(app):
        css_pruhledne()
        Vyber(app, vyzva, polozky, vysledek).present()

    app.connect("activate", start)
    app.run([sys.argv[0]])
    if not vysledek:
        return 1
    print(vysledek[0])
    print(vysledek[1] if len(vysledek) > 1 else "")
    return 0


def main():
    argv = sys.argv[1:]
    if argv[:1] == ["--vyber"]:
        return hlavni_vyber(argv[1] if len(argv) > 1 else "Vyber", argv[2:])
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
        css_pruhledne()
        okno.append(Karta(app, rezim, argv))
        okno[0].present()

    app.connect("activate", start)
    kod = app.run([sys.argv[0]])
    if okno:
        okno[0].ukonci_skript()
    return kod


if __name__ == "__main__":
    sys.exit(main())
