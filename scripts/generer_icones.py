"""Génère toutes les icônes depuis le code vectoriel du logo (43.8, DES-15, DES-37).

Le rendu est fait par Chrome ou Edge sans interface (aucune icône dessinée à la main).
Usage : python scripts/generer_icones.py
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
APP = RACINE / "app"

VIOLET = "#6C4DFF"
# Symbole complet (5-logo-et-icone.html).
SYMBOLE = """<rect width="200" height="200" rx="46" fill="#6C4DFF"/>
<rect x="76" y="34" width="48" height="86" rx="24" fill="#FFFFFF"/>
<path d="M88 62H112M88 78H112M88 94H112" stroke="#FF5C8A" stroke-width="7" stroke-linecap="round"/>
<path d="M56 100a44 44 0 0 0 88 0" fill="none" stroke="#FFFFFF" stroke-width="11" stroke-linecap="round"/>
<path d="M100 144V164M76 166H124" stroke="#FFFFFF" stroke-width="11" stroke-linecap="round"/>
<path d="M36 74Q28 94 36 114M164 74Q172 94 164 114" fill="none" stroke="#FFC93C" stroke-width="9" stroke-linecap="round"/>"""
# Premier plan sans le carré (icône adaptative Android, maskable).
PREMIER_PLAN = SYMBOLE.split("\n", 1)[1]
# Petites tailles : carré violet sans les arcs jaunes (moins de 28 px).
SANS_ARCS = SYMBOLE.rsplit("\n", 1)[0]
MONOCHROME = """<rect x="76" y="34" width="48" height="86" rx="24" fill="#FFFFFF"/>
<path d="M56 100a44 44 0 0 0 88 0" fill="none" stroke="#FFFFFF" stroke-width="11" stroke-linecap="round"/>
<path d="M100 144V164M76 166H124" stroke="#FFFFFF" stroke-width="11" stroke-linecap="round"/>"""


def svg(contenu: str, taille: int, fond: str | None = None, echelle: float = 1.0) -> str:
    """SVG carré ; `echelle` < 1 ajoute une marge de sécurité (maskable, zone sûre)."""
    marge = 200 * (1 - echelle) / 2
    fond_svg = f'<rect width="200" height="200" fill="{fond}"/>' if fond else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{taille}" height="{taille}" '
            f'viewBox="0 0 200 200">{fond_svg}<g transform="translate({marge} {marge}) '
            f'scale({echelle})">{contenu}</g></svg>')


def navigateur() -> str:
    candidats = [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        shutil.which("chrome") or "", shutil.which("chromium") or "",
        shutil.which("google-chrome") or "", shutil.which("msedge") or "",
    ]
    for c in candidats:
        if c and Path(c).exists():
            return c
    sys.exit("Chrome ou Edge introuvable : installe l'un des deux pour générer les icônes.")


def rendre(code_svg: str, taille: int, sortie: Path, exe: str) -> None:
    sortie.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as dossier:
        page = Path(dossier) / "icone.html"
        page.write_text(f'<!doctype html><html><body style="margin:0;background:transparent">'
                        f'{code_svg}</body></html>', encoding="utf-8")
        subprocess.run([exe, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--default-background-color=00000000", f"--window-size={taille},{taille}",
                        f"--screenshot={sortie}", page.as_uri()],
                       check=True, capture_output=True, timeout=60)


def main() -> None:
    exe = navigateur()
    web = APP / "web"
    rendus = [
        (svg(SYMBOLE, 192), 192, web / "icons" / "Icon-192.png"),
        (svg(SYMBOLE, 512), 512, web / "icons" / "Icon-512.png"),
        (svg(PREMIER_PLAN, 192, VIOLET, 0.8), 192, web / "icons" / "Icon-maskable-192.png"),
        (svg(PREMIER_PLAN, 512, VIOLET, 0.8), 512, web / "icons" / "Icon-maskable-512.png"),
        (svg(SYMBOLE, 32), 32, web / "favicon.png"),
        (svg(SYMBOLE, 48), 48, web / "favicon-48.png"),
        (svg(SANS_ARCS, 16), 16, web / "favicon-16.png"),
    ]
    res = APP / "android" / "app" / "src" / "main" / "res"
    densites = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for nom, facteur in densites.items():
        lanceur = round(48 * facteur)
        adaptatif = round(108 * facteur)
        rendus.append((svg(SYMBOLE, lanceur), lanceur, res / f"mipmap-{nom}" / "ic_launcher.png"))
        # Zone sûre centrale de 66 % du côté (43.8).
        rendus.append((svg(PREMIER_PLAN, adaptatif, None, 0.66), adaptatif,
                       res / f"mipmap-{nom}" / "ic_launcher_foreground.png"))
        rendus.append((svg(MONOCHROME, adaptatif, None, 0.66), adaptatif,
                       res / f"mipmap-{nom}" / "ic_launcher_monochrome.png"))
    for code, taille, sortie in rendus:
        rendre(code, taille, sortie, exe)
        print(f"{sortie.relative_to(RACINE)} ({taille} px)")


if __name__ == "__main__":
    main()
