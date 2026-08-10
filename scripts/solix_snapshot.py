#!/usr/bin/env python3
"""Print a normalized SOLIX snapshot JSON for SolixBar.

Requirements:
  - Python 3.12+
  - thomluther/anker-solix-api installed in the active environment
  - ANKER_SOLIX_USER, ANKER_SOLIX_PASSWORD and ANKER_SOLIX_COUNTRY env vars
"""

import asyncio
import argparse
import json
import os
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path


def _first_number(*values):
    for value in values:
        if isinstance(value, (int, float)):
            return value
        if isinstance(value, str):
            try:
                cleaned = (
                    value.strip()
                    .lower()
                    .replace("kwh", "")
                    .replace("wh", "")
                    .replace("w", "")
                    .replace(",", ".")
                )
                if cleaned:
                    return float(cleaned)
            except ValueError:
                pass
    return None


def _first_positive_number(*values):
    for value in values:
        number = _first_number(value)
        if number is not None and number > 0:
            return number
    return None


def _first_text(*values):
    for value in values:
        if value is not None and str(value).strip():
            return str(value).strip()
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


def _mqtt_snapshot(device):
    mqtt_data = device.get("mqtt_data")
    return dict(mqtt_data) if isinstance(mqtt_data, dict) else {}


def _battery_percent(mqtt_solarbank, solarbank, first_solarbank, site):
    return _as_int(
        mqtt_solarbank.get("battery_soc"),
        first_solarbank.get("battery_power"),
        solarbank.get("battery_soc"),
        solarbank.get("battery_percentage"),
        site.get("battery_soc"),
        site.get("soc"),
    )


async def _trigger_realtime_devices(client):
    """Ask every supported site device for fresh telemetry."""
    devices = [
        device
        for device in client.devices.values()
        if device.get("mqtt_supported")
        and not device.get("is_passive")
    ]
    if not devices:
        return {}, False

    mqtt_session = None
    try:
        mqtt_session = await asyncio.wait_for(client.startMqttSession(), timeout=6)
        if not mqtt_session or not mqtt_session.is_connected():
            return {}, False

        subscribed = []
        for device in devices:
            topic_prefix = mqtt_session.get_topic_prefix(deviceDict=device)
            if not topic_prefix:
                continue
            response = mqtt_session.subscribe(f"{topic_prefix}#")
            if response is None or not response.is_failure:
                subscribed.append(device)
        if not subscribed:
            return {}, False

        await asyncio.sleep(0.25)
        realtime_requested = False
        for device in subscribed:
            try:
                mqtt_session.realtime_trigger(
                    deviceDict=device,
                    timeout=300,
                    wait_for_publish=2,
                )
                realtime_requested = True
                if device.get("mqtt_status_request"):
                    mqtt_session.status_request(
                        deviceDict=device,
                        wait_for_publish=2,
                    )
            except Exception:
                continue
        if not realtime_requested:
            return {}, False

        earliest_cloud_refresh = time.monotonic() + 3
        deadline = time.monotonic() + 5
        freshest_solarbank = {}
        while time.monotonic() < deadline:
            await asyncio.sleep(0.25)
            for device in subscribed:
                candidate = _mqtt_snapshot(device)
                device_type = str(device.get("type", "")).lower()
                is_solarbank = "solarbank" in device_type or "battery" in device_type
                if is_solarbank and candidate.get("last_update"):
                    freshest_solarbank = candidate
                    if (
                        candidate.get("battery_soc") is not None
                        and time.monotonic() >= earliest_cloud_refresh
                    ):
                        return candidate, True
        return freshest_solarbank, True
    except Exception:
        # MQTT is an optional freshness path. The regular cloud response remains
        # available when a device, account, or network does not support it.
        return {}, False
    finally:
        if mqtt_session is not None:
            client.stopMqttSession()


def _energy_total(statistics, stat_type="1"):
    if not isinstance(statistics, list):
        return None
    for item in statistics or []:
        if str(item.get("type")) == stat_type:
            return _first_positive_number(item.get("total"))
    return None


def _period_solar_total(analysis):
    total = _energy_total(analysis.get("statistics"))
    if total is not None:
        return total
    power = analysis.get("power")
    if not isinstance(power, list) or not power:
        return None
    values = [_first_number(item.get("value")) for item in power if isinstance(item, dict)]
    return sum(value for value in values if value is not None) if any(value is not None for value in values) else None


def _installation_start_year(devices, current_year):
    years = []
    for device in devices:
        timestamp = _first_number(device.get("create_time"))
        if timestamp is None or timestamp <= 0:
            continue
        try:
            year = datetime.fromtimestamp(timestamp, timezone.utc).year
        except (OverflowError, OSError, ValueError):
            continue
        if 2020 <= year <= current_year:
            years.append(year)
    return min(years, default=current_year)


def _installation_start_date(devices, now):
    dates = []
    for device in devices:
        timestamp = _first_number(device.get("create_time"))
        if timestamp is None or timestamp <= 0:
            continue
        try:
            date = datetime.fromtimestamp(timestamp, timezone.utc).astimezone()
        except (OverflowError, OSError, ValueError):
            continue
        if 2020 <= date.year <= now.astimezone().year:
            dates.append(date.replace(hour=0, minute=0, second=0, microsecond=0))
    return min(dates, default=now.astimezone().replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0))


def _device_pv_period_total(statistics):
    total = _first_number(
        statistics.get("solarGeneraion"),
        statistics.get("solarGeneration"),
    )
    if total is not None:
        return total
    energy = statistics.get("energy")
    if not isinstance(energy, list) or not energy:
        return None
    values = [_first_number(item.get("energy")) for item in energy if isinstance(item, dict)]
    return sum(value for value in values if value is not None) if any(value is not None for value in values) else None


def _daily_history_solar_total(history):
    if not isinstance(history, dict) or not history:
        return None
    values = [
        _first_number(item.get("solar_production"))
        for item in history.values()
        if isinstance(item, dict)
    ]
    return sum(value for value in values if value is not None) if any(value is not None for value in values) else None


async def _historical_daily_solar_total(client, site_id, devices, now):
    start = _installation_start_date(devices, now)
    end = now.astimezone()
    total = 0.0
    found_value = False
    while start.date() <= end.date():
        days = min(366, (end.date() - start.date()).days + 1)
        history = await client.energy_daily(
            siteId=site_id,
            deviceSn="",
            startDay=start,
            numDays=days,
            dayTotals=False,
        )
        period_total = _daily_history_solar_total(history)
        if period_total is not None:
            total += max(0, period_total)
            found_value = True
        start += timedelta(days=days)
    return total if found_value else None


async def _lifetime_solar_total(client, site_id, devices, now):
    """Sum authoritative Anker solar totals for every installation year."""
    current_year = now.astimezone().year
    inverter_serials = _inverter_serials(next(iter(client.sites.values()), {}), devices)
    if inverter_serials:
        devices_by_serial = {
            str(device.get("device_sn")): device
            for device in devices
            if device.get("device_sn")
        }
        device_total = 0.0
        device_totals_complete = True
        try:
            for inverter_serial in inverter_serials:
                start_year = _installation_start_year(
                    [devices_by_serial.get(inverter_serial, {})],
                    current_year,
                )
                for year in range(start_year, current_year + 1):
                    statistics = await client.get_device_pv_statistics(
                        deviceSn=inverter_serial,
                        rangeType="year",
                        startDay=datetime(year, 1, 1),
                        endDay=datetime(year, 12, 31),
                    )
                    year_total = _device_pv_period_total(statistics)
                    if year_total is None:
                        device_totals_complete = False
                        break
                    device_total += max(0, year_total)
                if not device_totals_complete:
                    break
        except Exception:
            device_totals_complete = False
        if device_totals_complete and device_total > 0:
            return device_total

    # Some systems expose no PV-device statistics. Use the site-wide annual
    # analysis only when the device-specific endpoint is unavailable.
    try:
        start_year = _installation_start_year(devices, current_year)
        site_total = 0.0
        for year in range(start_year, current_year + 1):
            analysis = await client.energy_analysis(
                siteId=site_id,
                deviceSn="",
                rangeType="year",
                startDay=datetime(year, 1, 1),
                endDay=datetime(year, 12, 31),
                devType="solar_production",
            )
            year_total = _period_solar_total(analysis)
            if year_total is None:
                site_total = 0
                break
            site_total += max(0, year_total)
        if site_total > 0:
            return site_total
    except Exception:
        pass

    try:
        return await _historical_daily_solar_total(client, site_id, devices, now)
    except Exception:
        return None


def _state_path():
    configured = os.environ.get("SOLIXBAR_STATE_PATH")
    return Path(configured) if configured else Path(__file__).resolve().parents[1] / "work" / "solixbar-energy.json"


def _cache_path():
    configured = os.environ.get("SOLIXBAR_CACHE_PATH")
    return Path(configured) if configured else Path(__file__).resolve().parents[1] / "work" / "solixbar-api-cache.json"


def _load_cache():
    try:
        return json.loads(_cache_path().read_text(encoding="utf-8"))
    except Exception:
        return {}


def _write_private_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(value, separators=(",", ":")), encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(path)


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


def _fresh_cached_positive_value(cache, key, max_age_seconds):
    value = _fresh_cached_value(cache, key, max_age_seconds)
    return value if value is not None and value > 0 else None


def _realtime_refresh_needed(cache, key, now=None, max_age_seconds=240):
    item = cache.get(key)
    if not isinstance(item, dict):
        return True
    timestamp = _first_number(item.get("timestamp"))
    current_time = time.time() if now is None else now
    return timestamp is None or current_time - timestamp >= max_age_seconds


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
    has_manual_today = base_date == today_key and manual_base is not None
    previous_manual_today = _first_number(state.get("manualTodayBaseKWh"))
    previous_manual_today_date = state.get("manualTodayBaseDate")
    today_base_changed = has_manual_today and (
        previous_manual_today != manual_base or previous_manual_today_date != base_date
    )
    if today_base_changed:
        if not has_manual_total:
            current_total += manual_base - current_today
        current_today = manual_base

    last_time_text = state.get("lastUpdatedAt")
    last_solar = _first_number(state.get("lastSolarWatts"))
    if not total_base_changed and not today_base_changed and last_time_text and last_solar is not None and solar_watts is not None:
        try:
            last_time = datetime.fromisoformat(last_time_text)
            seconds = (now - last_time).total_seconds()
            is_regular_gap = 0 < seconds <= 30 * 60
            is_daytime_sleep_gap = (
                30 * 60 < seconds <= 8 * 60 * 60
                and min(last_solar, solar_watts) >= 50
                and last_time.astimezone().date() == now.astimezone().date()
            )
            if is_regular_gap or is_daytime_sleep_gap:
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
            "manualTodayBaseKWh": manual_base if has_manual_today else None,
            "manualTodayBaseDate": base_date if has_manual_today else None,
            "manualTotalBaseKWh": manual_total if has_manual_total else None,
            "lastSolarWatts": solar_watts,
            "lastUpdatedAt": now.isoformat(),
        }
    )
    _save_energy_state(state)
    return current_today, current_total, has_manual_today, has_manual_total


def _site_today_energy(site):
    energy_details = _first_dict(site.get("energy_details"))
    return _first_dict(energy_details.get("today"))


def _inverter_serials(site, devices):
    serials = []
    solar_list = site.get("solar_list") or []
    for item in solar_list:
        if isinstance(item, dict) and item.get("device_sn"):
            serials.append(str(item["device_sn"]))
    for device in devices:
        if str(device.get("type") or "").lower() == "inverter" and device.get("device_sn"):
            serials.append(str(device["device_sn"]))
    return list(dict.fromkeys(serials))


def _load_stdin_configuration():
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
    from aiohttp import ClientSession
    from anker_solix_api import api

    _load_stdin_configuration()
    user = os.environ["ANKER_SOLIX_USER"]
    password = os.environ["ANKER_SOLIX_PASSWORD"]
    country = os.environ.get("ANKER_SOLIX_COUNTRY", "DE")

    # The upstream client otherwise writes authentication and MQTT caches next
    # to its installed Python module. Keep every runtime artifact in the app's
    # private Application Support directory so the signed bundle stays sealed.
    private_runtime_dir = _cache_path().parent / "runtime"
    private_runtime_dir.mkdir(parents=True, exist_ok=True)
    private_runtime_dir.chmod(0o700)
    tempfile.tempdir = str(private_runtime_dir)
    os.umask(0o077)

    async with ClientSession() as session:
        client = api.AnkerSolixApi(user, password, country, session)
        client.apisession._authFile = str(private_runtime_dir / "auth-session.json")
        await client.update_sites()
        await client.update_device_details()
        cache = _load_cache()
        site_id = next(iter(client.sites.keys()), "")
        cache_namespace = site_id or "default-site"
        realtime_cache_key = f"{cache_namespace}:mqttRealtimeLease:v1"
        mqtt_solarbank = {}
        if _realtime_refresh_needed(cache, realtime_cache_key):
            mqtt_solarbank, realtime_requested = await _trigger_realtime_devices(client)
            if realtime_requested:
                # A real-time request keeps telemetry flowing for five minutes.
                # Refresh the cloud scene once after requesting it; subsequent
                # helper runs can use the already active stream without paying
                # for another MQTT setup and duplicate cloud request.
                await client.update_sites()
                _store_cached_value(cache, realtime_cache_key, 1)
                _save_cache(cache)

        site = next(iter(client.sites.values()), {})
        today_key = datetime.now().astimezone().date().isoformat()
        today_cache_key = f"{cache_namespace}:todayKWh:{today_key}"
        total_cache_key = f"{cache_namespace}:pvLifetimeTotalKWh:v6"
        today_kwh = _fresh_cached_positive_value(cache, today_cache_key, 10 * 60)
        devices = list(client.devices.values())
        solarbank = _first_solarbank(devices)
        site_info = _first_dict(site.get("site_info"))
        solarbank_info = _first_dict(site.get("solarbank_info"))
        solarbank_list = solarbank_info.get("solarbank_list") or []
        first_solarbank = solarbank_list[0] if solarbank_list else {}

        if today_kwh is None:
            try:
                today_analysis = await client.energy_analysis(
                    siteId=site_id,
                    deviceSn="",
                    rangeType="day",
                    startDay=datetime.today(),
                    endDay=datetime.today(),
                    devType="solar_production",
                )
                today_kwh = _first_positive_number(today_analysis.get("solar_total"))
                if today_kwh is None:
                    energy = await client.energy_daily(
                        siteId=site_id,
                        deviceSn="",
                        startDay=datetime.today(),
                        numDays=1,
                        dayTotals=False,
                    )
                    today = energy.get(datetime.today().strftime("%Y-%m-%d"), {})
                    today_kwh = _first_positive_number(today.get("solar_production"))
                _store_cached_value(cache, today_cache_key, today_kwh)
            except Exception:
                today_kwh = None

        cached_api_total = _fresh_cached_value(cache, total_cache_key, 6 * 60 * 60)
        if cached_api_total is None:
            api_total_kwh = await _lifetime_solar_total(
                client,
                site_id,
                devices,
                datetime.now(timezone.utc),
            )
            # Cache a negative sentinel as well. Accounts without a supported
            # total must not repeat all expensive fallback queries every cycle.
            _store_cached_value(cache, total_cache_key, api_total_kwh if api_total_kwh is not None else -1)
        else:
            api_total_kwh = cached_api_total if cached_api_total >= 0 else None
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
        local_today_kwh, _, has_manual_today, has_manual_total = _local_energy_totals(solar_watts, now)
        energy_today = _site_today_energy(site)
        api_today_kwh = _first_positive_number(
            today_kwh,
            energy_today.get("solar_production"),
            site.get("today_energy"),
            site.get("energy_today"),
        )
        api_total_kwh = _first_positive_number(
            api_total_kwh,
            site.get("total_energy"),
            site.get("energy_total"),
            _energy_total(site.get("statistics")),
        )
        manual_total_kwh = _first_number(os.environ.get("SOLIXBAR_TOTAL_KWH_BASE"))

        snapshot = {
            "siteName": _first_text(
                site_info.get("site_name"),
                site.get("site_name"),
                site.get("siteName"),
            ) or "Anker SOLIX",
            "batteryPercent": _battery_percent(
                mqtt_solarbank,
                solarbank,
                first_solarbank,
                site,
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
            "todayKWh": local_today_kwh if has_manual_today else (api_today_kwh if api_today_kwh is not None else local_today_kwh),
            "todayKWhIsAuthoritative": has_manual_today or api_today_kwh is not None,
            "totalKWh": manual_total_kwh if has_manual_total else api_total_kwh,
            "totalKWhIsAuthoritative": not has_manual_total and api_total_kwh is not None,
            "status": _first_text(
                site.get("status_desc"),
                solarbank.get("status_desc"),
                site.get("status"),
                solarbank.get("status"),
            ) or "Online",
            "updatedAt": now.isoformat(),
        }

        print(json.dumps(snapshot, separators=(",", ":")))


if __name__ == "__main__":
    asyncio.run(main())
