#!/usr/bin/env python3
"""Validate SolixBar's source-localized UI catalog without loading user data."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "Sources" / "SolixBar"
LOCALIZED_TEXT = SOURCE_DIR / "LocalizedText.swift"
APP_SETTINGS = SOURCE_DIR / "AppSettings.swift"

DIRECT_LANGUAGES = [
    "french", "spanish", "italian", "dutch", "polish", "portuguese",
    "czech", "danish", "swedish", "norwegian", "finnish", "russian",
    "simplifiedChinese", "japanese", "korean", "turkish", "romanian",
]
ALL_LANGUAGES = ["german", "english", *DIRECT_LANGUAGES[:13], "traditionalChinese", *DIRECT_LANGUAGES[13:]]


def fail(message: str) -> None:
    raise SystemExit(f"localization check failed: {message}")


localized_source = LOCALIZED_TEXT.read_text(encoding="utf-8")
settings_source = APP_SETTINGS.read_text(encoding="utf-8")
all_source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCE_DIR.glob("*.swift"))

table_match = re.search(
    r'private static let translationTable = #"""\n(.*?)\n    """#',
    localized_source,
    flags=re.DOTALL,
)
if not table_match:
    fail("translation table not found")

rows: dict[str, list[str]] = {}
for line_number, line in enumerate(table_match.group(1).splitlines(), start=1):
    columns = line.strip().split("\t")
    if len(columns) != len(DIRECT_LANGUAGES) + 1:
        fail(f"row {line_number} has {len(columns) - 1} translations")
    key, *values = columns
    if key in rows:
        fail(f"duplicate key: {key}")
    if any(not value.strip() for value in values):
        fail(f"empty translation: {key}")
    expected_placeholders = sorted(re.findall(r"\{[^}]+\}", key))
    for language, value in zip(DIRECT_LANGUAGES, values):
        if sorted(re.findall(r"\{[^}]+\}", value)) != expected_placeholders:
            fail(f"placeholder mismatch: {key} ({language})")
    rows[key] = values

if "ZXQPLACE" in localized_source:
    fail("temporary placeholder token remains")

pair_pattern = re.compile(
    r'LocalizedText\.(?:text|format)\(\s*"(?:\\.|[^"\\])*"\s*,\s*"((?:\\.|[^"\\])*)"',
    flags=re.DOTALL,
)
required_keys = set(pair_pattern.findall(all_source))
required_keys.update(
    {
        "Battery", "Batt", "PV", "Home Load", "Load", "Grid Import", "Grid",
        "Battery Flow", "Flow", "Energy Flow", "Today's Yield", "Yield",
        "Total Yield", "Total", "Status", "Current", "Now", "24 Hours",
        "7 Days", "30 Days", "Custom", "{value} seconds ago",
        "{value} minutes ago", "{value} hours ago", "{value} days ago",
        "Online", "Offline", "Unknown",
    }
)
missing = sorted(required_keys.difference(rows))
if missing:
    fail("missing keys: " + ", ".join(missing))

language_block = settings_source.split("enum AppLanguage", 1)[1].split("enum BarMetric", 1)[0]
declared_languages = re.findall(r"^    case ([A-Za-z]+)$", language_block, flags=re.MULTILINE)
if declared_languages != ALL_LANGUAGES:
    fail(f"AppLanguage order mismatch: {declared_languages}")

direct_branch = re.search(r"appLanguage\s*[!=]=\s*\.english|guard .*\.english", all_source)
if direct_branch:
    fail("direct English-only language branch remains")

print(f"Localization OK: {len(rows)} keys, {len(ALL_LANGUAGES)} languages, placeholders intact.")
