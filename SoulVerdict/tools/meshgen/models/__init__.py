"""Mesh registry: name -> ModelSpec factory (names follow docs/SPEC.md section 18)."""
from __future__ import annotations


def registry():
    from models import blaster, sans

    return {
        "SansSkullClassic": sans.classic,
        "SansSkullFell": sans.fell,
        "SansSkullEclipse": sans.eclipse,
        "BlasterSkullClassic": lambda: blaster.skull("Classic"),
        "BlasterJawClassic": lambda: blaster.jaw("Classic"),
        "BlasterSkullFell": lambda: blaster.skull("Fell"),
        "BlasterJawFell": lambda: blaster.jaw("Fell"),
        "BlasterSkullEclipse": lambda: blaster.skull("Eclipse"),
        "BlasterJawEclipse": lambda: blaster.jaw("Eclipse"),
    }


ORDER = [
    "SansSkullClassic",
    "SansSkullFell",
    "SansSkullEclipse",
    "BlasterSkullClassic",
    "BlasterJawClassic",
    "BlasterSkullFell",
    "BlasterJawFell",
    "BlasterSkullEclipse",
    "BlasterJawEclipse",
]
