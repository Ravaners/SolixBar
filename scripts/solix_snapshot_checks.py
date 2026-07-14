#!/usr/bin/env python3
"""Dependency-free checks for the pure SOLIX snapshot helper logic."""

import importlib.util
import json
import os
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path


helper_path = Path(__file__).with_name("solix_snapshot.py")
spec = importlib.util.spec_from_file_location("solix_snapshot", helper_path)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

assert helper._first_positive_number(0, "0", "3.45") == 3.45
assert helper._first_positive_number("2,75 kWh") == 2.75
assert helper._first_positive_number(None, -1, "") is None
assert helper._site_today_energy({"energy_details": {"today": {"solar_production": "4.2"}}}) == {
    "solar_production": "4.2"
}
assert helper._first_inverter_serial(
    {"solar_list": [{"device_sn": "PV-1"}]},
    [{"type": "inverter", "device_sn": "PV-2"}],
) == "PV-1"
assert helper._first_inverter_serial(
    {},
    [{"type": "inverter", "device_sn": "PV-2"}],
) == "PV-2"

with tempfile.TemporaryDirectory() as temporary:
    state_path = Path(temporary) / "energy.json"
    os.environ["SOLIXBAR_STATE_PATH"] = str(state_path)
    start = datetime(2026, 7, 14, 10, tzinfo=timezone.utc)
    state_path.write_text(
        json.dumps(
            {
                "today": start.astimezone().date().isoformat(),
                "todayKWh": 1.0,
                "totalKWh": 10.0,
                "lastSolarWatts": 500,
                "lastUpdatedAt": start.isoformat(),
            }
        ),
        encoding="utf-8",
    )
    today, total, _, _ = helper._local_energy_totals(500, start + timedelta(hours=2))
    assert abs(today - 2.0) < 0.000_001
    assert abs(total - 11.0) < 0.000_001

    state_path.write_text(
        json.dumps(
            {
                "today": start.astimezone().date().isoformat(),
                "todayKWh": 1.0,
                "totalKWh": 10.0,
                "lastSolarWatts": 1_460,
                "lastUpdatedAt": start.isoformat(),
            }
        ),
        encoding="utf-8",
    )
    today, total, _, _ = helper._local_energy_totals(1_180, start + timedelta(hours=5, minutes=15))
    assert abs(today - 7.93) < 0.000_001
    assert abs(total - 16.93) < 0.000_001

    os.environ["SOLIXBAR_TODAY_KWH_BASE"] = "0.5"
    os.environ["SOLIXBAR_TODAY_KWH_DATE"] = start.astimezone().date().isoformat()
    today, _, has_manual_today, _ = helper._local_energy_totals(500, start + timedelta(hours=2, minutes=2))
    assert today == 0.5
    assert has_manual_today is True

    os.environ.pop("SOLIXBAR_STATE_PATH")
    os.environ.pop("SOLIXBAR_TODAY_KWH_BASE")
    os.environ.pop("SOLIXBAR_TODAY_KWH_DATE")

print("SOLIX snapshot checks passed.")
