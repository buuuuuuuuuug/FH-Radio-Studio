"""Explicit interchange units; game sample positions always use 48 kHz frames."""

from __future__ import annotations

import math
from decimal import Decimal, InvalidOperation

SAMPLE_RATE = 48000
TIME_UNITS = ("time", "samples")


def validate_units(unit="time", sample_rate=SAMPLE_RATE):
    if unit not in TIME_UNITS:
        raise ValueError("时间单位只能是时间或采样点")
    if isinstance(sample_rate, bool) or str(sample_rate).strip() != str(SAMPLE_RATE):
        raise ValueError("采样点数据的采样率必须为 48000 Hz")


def samples_to_seconds(value):
    if isinstance(value, bool):
        raise ValueError("采样点必须为非负整数")
    try:
        number = Decimal(str(value).strip())
    except InvalidOperation as error:
        raise ValueError("采样点必须为非负整数") from error
    if (
        not number.is_finite()
        or number < 0
        or number != number.to_integral_value()
        or number > 2**53 - 1
    ):
        raise ValueError("采样点必须为有效的非负整数")
    return int(number) / SAMPLE_RATE


def seconds_to_samples(value):
    position = value * SAMPLE_RATE
    if not math.isfinite(position) or position > 2**53 - 1:
        raise ValueError("时间点超出可导出的采样点范围")
    return int(math.floor(position + 0.5))


def row_time_unit(data, default="time"):
    rate = data.get("sample_rate")
    if "sample_rate" in data:
        # Spreadsheet numeric cells may arrive as 48000.0.
        try:
            valid = not isinstance(rate, bool) and Decimal(str(rate)) == SAMPLE_RATE
        except InvalidOperation:
            valid = False
        if not valid:
            raise ValueError("采样点数据的采样率必须为 48000 Hz")
    unit = data.get("time_unit")
    if unit is None or not str(unit).strip():
        return "samples" if "sample_rate" in data else default
    unit = str(unit).strip().casefold()
    if unit in ("samples", "sample", "采样点"):
        return "samples"
    if unit in ("time", "seconds", "second", "sec", "s", "时间", "秒"):
        return "time"
    raise ValueError("无法识别时间单位，请使用 time 或 samples")
