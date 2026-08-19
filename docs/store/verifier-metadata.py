#!/usr/bin/env python3
"""Vérifie les limites de caractères App Store des fiches de `app-store-metadata.md`.

Apple tronque sans prévenir : un sous-titre à 31 caractères est refusé à la saisie, et un champ
mots-clés trop long fait perdre les derniers termes. Ce script relit le markdown (source unique)
et échoue si un champ dépasse. À rejouer après toute retouche des textes.

    python3 docs/store/verifier-metadata.py
"""
import re
import sys
from pathlib import Path

LIMITES = {"Nom": 30, "Sous-titre": 30, "Mots-clés": 100, "Texte promotionnel": 170}

doc = Path(__file__).with_name("app-store-metadata.md").read_text(encoding="utf-8")

# Les descriptions sont dans des blocs ``` ; on ne veut que les puces `- **Champ** : ...`
sans_blocs = re.sub(r"```.*?```", "", doc, flags=re.S)

erreurs, contrôlés = [], 0
locale = "?"
for ligne in sans_blocs.splitlines():
    if ligne.startswith("## ") and "(" in ligne:
        locale = ligne[3:].strip()
    m = re.match(r"- \*\*(.+?)\*\* : `?(.+?)`?$", ligne.strip())
    if not m:
        continue
    champ, valeur = m.group(1), m.group(2).strip("`")
    if champ not in LIMITES:
        continue
    contrôlés += 1
    n, maxi = len(valeur), LIMITES[champ]
    état = "OK " if n <= maxi else "TROP LONG"
    print(f"{état:9} {locale:32} {champ:20} {n:3}/{maxi}")
    if n > maxi:
        erreurs.append(f"{locale} — {champ} : {n} caractères (max {maxi})")
    if champ == "Mots-clés" and ", " in valeur:
        erreurs.append(f"{locale} — Mots-clés : espace après une virgule (caractères gaspillés)")

# Les descriptions (blocs ```) sont plafonnées à 4000 caractères.
for i, bloc in enumerate(re.findall(r"```\n(.*?)```", doc, flags=re.S), 1):
    n = len(bloc)
    état = "OK " if n <= 4000 else "TROP LONG"
    print(f"{état:9} description #{i:<20}                      {n:4}/4000")
    if n > 4000:
        erreurs.append(f"description #{i} : {n} caractères (max 4000)")

print(f"\n{contrôlés} champs contrôlés.")
if erreurs:
    print("\n".join("✗ " + e for e in erreurs))
    sys.exit(1)
print("✓ toutes les limites App Store sont respectées.")
