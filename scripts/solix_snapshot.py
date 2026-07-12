#!/usr/bin/env python3
"""Print a normalized SOLIX snapshot JSON for SolixBar.

Requirements:
  - Python 3.12+
  - thomluther/anker-solix-api installed in the active environment
  - ANKER_SOLIX_USER, ANKER_SOLIX_PASSWORD and ANKER_SOLIX_COUNTRY env vars
"""

import argparse
import asyncio
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from aiohttp import ClientSession
from anker_solix_api import api


def _first_number(*values):
    for value in values:
        if isinstance(value, (int, float)):
            return value
        if isinstance(value, str):
            try:
                cleaned = value.strip().replace("W", "").replace("kWh", "").replace(",", ".")
                if cleaned:
                    return float(cleaned)
            except ValueError:
                pass
    return None


def _first_positive_number(*values):
    number = _first_number(*values)
    return number if number and number > 0 else None


def _as_int(*values):
    number = _first_number(*values)
    return None if number is None else int(round(number))


def _signed_grid_watts(site):
    grid_info = _first_dict(site.get("grid_info"))
    imported = _first_number(
        grid_info.get("grid_to_home_power"),
        site.get("grid_to_home_power"),
    )
    exported = _first_number(
        grid_info.get("photovoltaic_to_grid_power"),
        site.get("to_grid_power"),
    )
    if imported is not None or exported is not None:
        return int(round((imported or 0) - (exported or 0)))
    return _as_int(
        site.get("grid_connected_power_v2"),
        site.get("grid_power"),
    )


def _signed_battery_watts(solarbank_info, solarbank, first_solarbank):
    charge = _first_number(
        solarbank_info.get("total_charging_power"),
        first_solarbank.get("charging_power"),
        solarbank.get("charging_power"),
        first_solarbank.get("bat_charge_power"),
        solarbank.get("bat_charge_power"),
    )
    discharge = _first_number(
        solarbank_info.get("battery_discharge_power"),
        first_solarbank.get("bat_discharge_power"),
        solarbank.get("bat_discharge_power"),
    )
    if charge and charge > 0:
        return int(round(charge))
    if discharge and discharge > 0:
        return -int(round(discharge))
    return 0 if charge == 0 or discharge == 0 else None


def _first_dict(*values):
    for value in values:
        if isinstance(value, dict):
            return value
    return {}


def _pv_channel_watts(solarbank, first_solarbank):
    """Leistung je MPPT-Eingang (solar_power_1..4), sofern das Modell sie meldet.

    Solarbank 2 Pro / Solarbank 3 melden 4 Kanäle, Solarbank 2 Plus/AC 2,
    die erste Solarbank-Generation keine. Ohne Kanal-Reporting: None.
    (Feldnamen laut anker-solix-api; mangels Hardware unverifiziert.)
    """
    channels = []
    for index in range(1, 5):
        key = f"solar_power_{index}"
        value = _as_int(solarbank.get(key), first_solarbank.get(key))
        if value is None:
            break
        channels.append(value)
    return channels or None


def _first_solarbank(devices):
    return next(
        (
            device
            for device in devices
            if "solarbank" in str(device.get("type", "")).lower()
            or "battery" in str(device.get("type", "")).lower()
        ),
        {},
    )


def _energy_total(statistics, stat_type="1"):
    for item in statistics or []:
        if str(item.get("type")) == stat_type:
            return _first_positive_number(item.get("total"))
    return None


def _state_path():
    configured = os.environ.get("SOLIXBAR_STATE_PATH")
    if configured:
        return Path(configured)
    return Path(__file__).resolve().parents[1] / "work" / "solixbar-energy.json"


def _cache_path():
    configured = os.environ.get("SOLIXBAR_CACHE_PATH")
    if configured:
        return Path(configured)
    return Path(__file__).resolve().parents[1] / "work" / "solixbar-api-cache.json"


def _write_private_json(path, value):
    """Atomar schreiben mit 0600: Zustand/Cache liegen im Klartext auf Platte."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(value, separators=(",", ":")), encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(path)


def _load_cache():
    try:
        return json.loads(_cache_path().read_text(encoding="utf-8"))
    except Exception:
        return {}


def _save_cache(cache):
    _write_private_json(_cache_path(), cache)


def _fresh_cached_value(cache, key, max_age_seconds):
    item = cache.get(key)
    if not isinstance(item, dict):
        return None
    timestamp = _first_number(item.get("timestamp"))
    if timestamp is None or time.time() - timestamp > max_age_seconds:
        return None
    return _first_number(item.get("value"))


def _store_cached_value(cache, key, value):
    if value is not None:
        cache[key] = {"timestamp": time.time(), "value": value}


def _load_energy_state():
    try:
        return json.loads(_state_path().read_text(encoding="utf-8"))
    except Exception:
        return {}


def _save_energy_state(state):
    _write_private_json(_state_path(), state)


def _local_energy_totals(solar_watts, now):
    state = _load_energy_state()
    today_key = now.astimezone().date().isoformat()
    current_total = _first_number(state.get("totalKWh")) or 0
    current_today = _first_number(state.get("todayKWh")) or 0

    if state.get("today") != today_key:
        current_today = 0

    manual_total = _first_number(os.environ.get("SOLIXBAR_TOTAL_KWH_BASE"))
    has_manual_total = manual_total is not None
    previous_manual_total = _first_number(state.get("manualTotalBaseKWh"))
    total_base_changed = has_manual_total and previous_manual_total != manual_total
    if total_base_changed:
        current_total = manual_total
    elif has_manual_total and manual_total > current_total:
        current_total = manual_total

    base_date = os.environ.get("SOLIXBAR_TODAY_KWH_DATE") or today_key
    manual_base = _first_number(os.environ.get("SOLIXBAR_TODAY_KWH_BASE"))
    if base_date == today_key and manual_base is not None and manual_base > current_today:
        if not has_manual_total:
            current_total += manual_base - current_today
        current_today = manual_base

    last_time_text = state.get("lastUpdatedAt")
    last_solar = _first_number(state.get("lastSolarWatts"))
    if not total_base_changed and last_time_text and last_solar is not None and solar_watts is not None:
        try:
            last_time = datetime.fromisoformat(last_time_text)
            seconds = (now - last_time).total_seconds()
            if 0 < seconds <= 30 * 60:
                kwh = ((last_solar + solar_watts) / 2) * seconds / 3_600_000
                current_today += kwh
                current_total += kwh
        except ValueError:
            pass

    state.update(
        {
            "today": today_key,
            "todayKWh": current_today,
            "totalKWh": current_total,
            "manualTotalBaseKWh": manual_total if has_manual_total else None,
            "lastSolarWatts": solar_watts,
            "lastUpdatedAt": now.isoformat(),
        }
    )
    _save_energy_state(state)
    return current_today, current_total, has_manual_total


def _load_stdin_configuration():
    """Zugangsdaten per stdin-JSON statt Umgebungsvariablen.

    Umgebungsvariablen sind für gleichnamige Nutzerprozesse via `ps e`
    sichtbar; die App übergibt Mail/Passwort daher als eine JSON-Zeile.
    """
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--stdin-config", action="store_true")
    args, _ = parser.parse_known_args()
    if not args.stdin_config:
        return
    request = json.loads(sys.stdin.readline())
    os.environ["ANKER_SOLIX_USER"] = str(request.get("email") or "")
    os.environ["ANKER_SOLIX_PASSWORD"] = str(request.get("password") or "")
    os.environ["ANKER_SOLIX_COUNTRY"] = str(request.get("country") or "DE")
    if request.get("todayBaseKWh") is not None:
        os.environ["SOLIXBAR_TODAY_KWH_BASE"] = str(request["todayBaseKWh"])
        os.environ["SOLIXBAR_TODAY_KWH_DATE"] = datetime.now().astimezone().date().isoformat()
    if request.get("totalBaseKWh") is not None:
        os.environ["SOLIXBAR_TOTAL_KWH_BASE"] = str(request["totalBaseKWh"])


async def main():
    _load_stdin_configuration()
    user = os.environ["ANKER_SOLIX_USER"]
    password = os.environ["ANKER_SOLIX_PASSWORD"]
    country = os.environ.get("ANKER_SOLIX_COUNTRY", "DE")

    async with ClientSession() as session:
        client = api.AnkerSolixApi(user, password, country, session)
        await client.update_sites()
        await client.update_device_details()

        cache = _load_cache()
        site = next(iter(client.sites.values()), {})
        site_id = next(iter(client.sites.keys()), "")
        cache_namespace = site_id or "default-site"
        today_key = datetime.now().astimezone().date().isoformat()
        today_cache_key = f"{cache_namespace}:todayKWh:{today_key}"
        statistics_cache_key = f"{cache_namespace}:statisticsTotalKWh"
        # Teure Statistik-Abfragen drosseln: Tages-kWh 10 min, Gesamt 15 min.
        # Die Live-Leistungswerte kommen weiterhin bei jedem Abruf frisch.
        today_kwh = _fresh_cached_value(cache, today_cache_key, 10 * 60)
        devices = list(client.devices.values())
        solarbank = _first_solarbank(devices)
        device_sn = solarbank.get("device_sn") or ""
        site_info = _first_dict(site.get("site_info"))
        solarbank_info = _first_dict(site.get("solarbank_info"))
        solarbank_list = solarbank_info.get("solarbank_list") or []
        first_solarbank = solarbank_list[0] if solarbank_list else {}

        if today_kwh is None:
            try:
                energy = await client.energy_daily(
                    siteId=site_id,
                    deviceSn=device_sn,
                    startDay=datetime.today(),
                    numDays=1,
                    dayTotals=True,
                    devTypes={"solarbank"},
                )
                today = energy.get(datetime.today().strftime("%Y-%m-%d"), {})
                today_kwh = _first_number(today.get("solar_production"))
                _store_cached_value(cache, today_cache_key, today_kwh)
            except Exception:
                today_kwh = None

        api_statistics_total = _fresh_cached_value(cache, statistics_cache_key, 15 * 60)
        if api_statistics_total is None:
            try:
                energy_stats = await client.energy_statistics(
                    siteId=site_id,
                    rangeType="year",
                    sourceType="solar",
                )
                api_statistics_total = _energy_total(energy_stats.get("statistics"))
                _store_cached_value(cache, statistics_cache_key, api_statistics_total)
            except Exception:
                api_statistics_total = None
        _save_cache(cache)

        battery_watts = _signed_battery_watts(solarbank_info, solarbank, first_solarbank)
        now = datetime.now(timezone.utc)
        solar_watts = _as_int(
            solarbank_info.get("total_photovoltaic_power"),
            solarbank.get("input_power"),
            first_solarbank.get("photovoltaic_power"),
            site.get("solar_power"),
            site.get("photovoltaic_power"),
            site.get("pv_power"),
        )
        local_today_kwh, local_total_kwh, _ = _local_energy_totals(solar_watts, now)
        api_today_kwh = _first_positive_number(today_kwh, site.get("today_energy"), site.get("energy_today"))
        api_total_kwh = _first_positive_number(
            site.get("total_energy"),
            site.get("energy_total"),
            _energy_total(site.get("statistics")),
            api_statistics_total,
        )

        snapshot = {
            "siteName": site_info.get("site_name")
            or site.get("site_name")
            or site.get("siteName")
            or "Anker SOLIX",
            "batteryPercent": _as_int(
                solarbank.get("battery_soc"),
                first_solarbank.get("battery_power"),
                solarbank.get("battery_percentage"),
                site.get("battery_soc"),
                site.get("soc"),
            ),
            "solarWatts": solar_watts,
            "homeWatts": _as_int(
                site.get("home_load_power"),
                site.get("other_loads_power"),
                site.get("home_load"),
                site.get("load_power"),
                site.get("home_power"),
                first_solarbank.get("current_home_load"),
                solarbank.get("current_home_load"),
                solarbank_info.get("to_home_load"),
                solarbank_info.get("total_output_power"),
                solarbank.get("output_power"),
                first_solarbank.get("output_power"),
            ),
            "gridWatts": _signed_grid_watts(site),
            "batteryWatts": battery_watts,
            "todayKWh": max(api_today_kwh or 0, local_today_kwh),
            "totalKWh": api_total_kwh if api_total_kwh is not None else local_total_kwh,
            "status": site.get("status_desc") or solarbank.get("status_desc") or site.get("status") or solarbank.get("status") or "Online",
            "updatedAt": now.isoformat(),
        }

        pv_watts = _pv_channel_watts(solarbank, first_solarbank)
        if pv_watts is not None:
            snapshot["pvWatts"] = pv_watts

        print(json.dumps(snapshot, separators=(",", ":")))


if __name__ == "__main__":
    asyncio.run(main())
