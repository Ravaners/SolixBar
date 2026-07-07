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

        battery_discharge = _first_number(
            solarbank_info.get("battery_discharge_power"),
            first_solarbank.get("bat_discharge_power"),
            solarbank.get("bat_discharge_power"),
        )
        battery_charge = _first_number(
            solarbank_info.get("grid_to_battery_power"),
            solarbank_info.get("total_charging_power"),
            first_solarbank.get("bat_charge_power"),
            solarbank.get("bat_charge_power"),
        )
        battery_watts = None
        if battery_discharge is not None and battery_discharge > 0:
            battery_watts = -battery_discharge
        elif battery_charge is not None:
            battery_watts = battery_charge

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
            "solarWatts": _as_int(
                solarbank_info.get("total_photovoltaic_power"),
                solarbank.get("input_power"),
                first_solarbank.get("photovoltaic_power"),
                site.get("solar_power"),
                site.get("photovoltaic_power"),
                site.get("pv_power"),
            ),
            "homeWatts": _as_int(
                solarbank_info.get("to_home_load"),
                solarbank_info.get("total_output_power"),
                solarbank.get("output_power"),
                first_solarbank.get("output_power"),
                site.get("home_load"),
                site.get("load_power"),
                site.get("home_power"),
            ),
            "gridWatts": _as_int(
                site.get("grid_connected_power_v2"),
                site.get("grid_power"),
                site.get("to_grid_power"),
            ),
            "batteryWatts": _as_int(battery_watts),
            "todayKWh": _first_number(today_kwh, site.get("today_energy"), site.get("energy_today"), 0),
            "totalKWh": _first_number(
                site.get("total_energy"),
                site.get("energy_total"),
                _energy_total(site.get("statistics")),
            ),
            "status": site.get("status_desc") or solarbank.get("status_desc") or site.get("status") or solarbank.get("status") or "Online",
            "updatedAt": datetime.now(timezone.utc).isoformat(),
        }

        print(json.dumps(snapshot, separators=(",", ":")))


if __name__ == "__main__":
    asyncio.run(main())
