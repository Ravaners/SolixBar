#!/usr/bin/env python3
"""Print a normalized SOLIX snapshot JSON for SolixBar.

Requirements:
  - Python 3.12+
  - thomluther/anker-solix-api installed in the active environment
  - ANKER_SOLIX_USER, ANKER_SOLIX_PASSWORD and ANKER_SOLIX_COUNTRY env vars
"""

import asyncio
import json
import os
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
            return _first_number(item.get("total"))
    return None


def _state_path():
    return Path(__file__).resolve().parents[1] / "work" / "solixbar-energy.json"


def _load_energy_state():
    try:
        return json.loads(_state_path().read_text(encoding="utf-8"))
    except Exception:
        return {}


def _save_energy_state(state):
    path = _state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, separators=(",", ":")), encoding="utf-8")


def _local_energy_totals(solar_watts, now):
    state = _load_energy_state()
    today_key = now.astimezone().date().isoformat()
    current_total = _first_number(state.get("totalKWh")) or 0
    current_today = _first_number(state.get("todayKWh")) or 0

    if state.get("today") != today_key:
        current_today = 0

    manual_total = _first_number(os.environ.get("SOLIXBAR_TOTAL_KWH_BASE"))
    has_manual_total = manual_total is not None
    if has_manual_total and manual_total > current_total:
        current_total = manual_total

    base_date = os.environ.get("SOLIXBAR_TODAY_KWH_DATE") or today_key
    manual_base = _first_number(os.environ.get("SOLIXBAR_TODAY_KWH_BASE"))
    if base_date == today_key and manual_base is not None and manual_base > current_today:
        if not has_manual_total:
            current_total += manual_base - current_today
        current_today = manual_base

    last_time_text = state.get("lastUpdatedAt")
    last_solar = _first_number(state.get("lastSolarWatts"))
    if last_time_text and last_solar is not None and solar_watts is not None:
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
            "lastSolarWatts": solar_watts,
            "lastUpdatedAt": now.isoformat(),
        }
    )
    _save_energy_state(state)
    return current_today, current_total


async def main():
    user = os.environ["ANKER_SOLIX_USER"]
    password = os.environ["ANKER_SOLIX_PASSWORD"]
    country = os.environ.get("ANKER_SOLIX_COUNTRY", "DE")

    async with ClientSession() as session:
        client = api.AnkerSolixApi(user, password, country, session)
        await client.update_sites()
        await client.update_device_details()

        today_kwh = None
        site = next(iter(client.sites.values()), {})
        site_id = next(iter(client.sites.keys()), "")
        devices = list(client.devices.values())
        solarbank = _first_solarbank(devices)
        device_sn = solarbank.get("device_sn") or ""
        site_info = _first_dict(site.get("site_info"))
        solarbank_info = _first_dict(site.get("solarbank_info"))
        solarbank_list = solarbank_info.get("solarbank_list") or []
        first_solarbank = solarbank_list[0] if solarbank_list else {}

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
        except Exception:
            today_kwh = None

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
        local_today_kwh, local_total_kwh = _local_energy_totals(solar_watts, now)
        api_today_kwh = _first_number(today_kwh, site.get("today_energy"), site.get("energy_today"))
        api_total_kwh = _first_number(
            site.get("total_energy"),
            site.get("energy_total"),
            _energy_total(site.get("statistics")),
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
            "totalKWh": max(api_total_kwh or 0, local_total_kwh),
            "status": site.get("status_desc") or solarbank.get("status_desc") or site.get("status") or solarbank.get("status") or "Online",
            "updatedAt": now.isoformat(),
        }

        print(json.dumps(snapshot, separators=(",", ":")))


if __name__ == "__main__":
    asyncio.run(main())
