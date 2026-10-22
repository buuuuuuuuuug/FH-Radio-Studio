import numpy as np
import pytest

from backend.fh_radio_studio_cli.ai_timepoints.providers.baseline_mir import _estimate_bpm
from backend.fh_radio_studio_cli.ai_timepoints.providers.beat_this import _estimate_bpm as beat_bpm


def test_neural_beat_tempo_uses_the_same_median_as_the_grid():
    assert beat_bpm([0, 0.4, 1]) == pytest.approx(120)


def test_bpm_reports_measured_period_not_nominal_scan_label():
    # A clean 24-frame period at 50 Hz is exactly 125 BPM. The former scanner
    # assigned the largest BPM sharing this lag (127.5) to the same evidence.
    envelope = np.zeros(24 * 30, dtype=np.float32)
    envelope[::24] = 1
    times = np.arange(envelope.size, dtype=np.float64) / 50
    bpm, confidence = _estimate_bpm({"novelty": envelope, "times": times}, 120)
    assert bpm == pytest.approx(125, abs=0.002)
    assert 0.1 <= confidence <= 0.75


@pytest.mark.parametrize("value", [0, 1, float("nan")])
def test_nonperiodic_or_invalid_input_keeps_fallback(value):
    bpm, confidence = _estimate_bpm(
        {
            "novelty": np.full(200, value),
            "times": np.arange(200) / 50,
        },
        137,
    )
    assert bpm == 137
    assert confidence == 0.1
