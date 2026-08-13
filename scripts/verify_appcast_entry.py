#!/usr/bin/env python3
"""Fail closed unless one appcast item exactly matches a release artifact."""

from __future__ import annotations

import argparse
import xml.etree.ElementTree as ET
from pathlib import Path


def _local_name(name: str) -> str:
    return name.rsplit("}", 1)[-1]


def _child_text(item: ET.Element, name: str) -> str | None:
    for child in item:
        if _local_name(child.tag) == name:
            return (child.text or "").strip()
    return None


def verify_appcast_entry(
    appcast: Path,
    short_version: str,
    build_version: str,
    signature: str,
    length: str,
    url: str,
) -> None:
    root = ET.parse(appcast).getroot()
    items = [
        item
        for item in root.iter()
        if _local_name(item.tag) == "item"
        and _child_text(item, "shortVersionString") == short_version
    ]
    if len(items) != 1:
        raise ValueError(
            f"expected exactly one appcast item for {short_version}, found {len(items)}"
        )

    item = items[0]
    enclosures = [child for child in item if _local_name(child.tag) == "enclosure"]
    if len(enclosures) != 1:
        raise ValueError(f"expected exactly one enclosure for {short_version}")

    attributes = {
        _local_name(key): value for key, value in enclosures[0].attrib.items()
    }
    expected = {
        "version": (_child_text(item, "version"), build_version),
        "url": (attributes.get("url"), url),
        "length": (attributes.get("length"), length),
        "edSignature": (attributes.get("edSignature"), signature),
    }
    mismatches = [
        name for name, (actual, wanted) in expected.items() if actual != wanted
    ]
    if mismatches:
        details = ", ".join(
            f"{name}: appcast={expected[name][0]!r} dmg={expected[name][1]!r}"
            for name in mismatches
        )
        raise ValueError(f"existing appcast item does not match the DMG: {details}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("appcast", type=Path)
    parser.add_argument("short_version")
    parser.add_argument("build_version")
    parser.add_argument("signature")
    parser.add_argument("length")
    parser.add_argument("url")
    args = parser.parse_args()

    try:
        verify_appcast_entry(
            args.appcast,
            args.short_version,
            args.build_version,
            args.signature,
            args.length,
            args.url,
        )
    except (ET.ParseError, OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
