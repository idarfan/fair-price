"""
Unit tests for leaps_scraper.py — three-way classification logic.

Covers:
  _wait_for_grid: None (timeout), [] (immediate empty), populated list
  _confirm_empty: stability check outcomes
  main() opts None  → session_expired vs page_load_timeout (via _wait_for_grid mock)
  main() opts []    → confirmed empty → skip / data-appeared (via _confirm_empty mock)
  main() vg  None   → session_expired vs page_load_timeout
  main() vg  []     → confirmed empty (non-fatal) / data-appeared
  main() happy path → success with rows
"""
import asyncio
import io
import json
import sys
import types
import unittest
from unittest.mock import AsyncMock, MagicMock, patch
import importlib.util


# ---------------------------------------------------------------------------
# Load scraper module with cdp_helper stubbed out
# ---------------------------------------------------------------------------
def _load_scraper():
    stub = types.ModuleType("cdp_helper")
    for name in ("prepare_page", "cdp_eval", "cdp_navigate", "activate_target"):
        setattr(stub, name, AsyncMock())
    sys.modules["cdp_helper"] = stub

    spec = importlib.util.spec_from_file_location(
        "leaps_scraper",
        __file__.replace("test_leaps_scraper.py", "leaps_scraper.py"),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["leaps_scraper"] = mod   # ← required so patch() can find it
    spec.loader.exec_module(mod)
    return mod


scraper = _load_scraper()


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
GOOD_NEAR_MONEY = [
    {"strike": 6.5, "delta": 0.70, "strikePrice": 6.5},
    {"strike": 7.0, "delta": 0.85, "strikePrice": 7.0},
    {"strike": 7.5, "delta": 0.60, "strikePrice": 7.5},
]
GOOD_EXPIRATIONS = [{"value": "2027-01-15-m", "text": "Jan 2027"}]
# Field names AFTER JS mapping (STACKED_OPTIONS_JS / LOCK_STRIKE_VG_JS produce these)
GOOD_OPTS = [
    {"strike": 7.0, "expiration_date": "2027-01-15", "dte": 197,
     "bid": 5.4, "ask": 5.6, "mid": 5.5, "last": 5.5,
     "volume": 100, "oi": 500, "delta": 0.90, "iv": 0.72, "moneyness": 0.58}
]
GOOD_VG = [
    {"strike": 7.0, "expiration_date": "2027-01-15", "dte": 197,
     "itm_prob": 0.85, "vol_oi": 0.2, "vega": 0.015}
]


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _capture_main(cdp_eval_mock, wait_mock=None, confirm_mock=None):
    """Run main("NOK", user_strike=7.0) with full mocks, return parsed JSON."""
    patches = [
        patch("leaps_scraper.prepare_page", new=AsyncMock(return_value=("tid", "ws://fake"))),
        patch("leaps_scraper.cdp_navigate", new=AsyncMock()),
        patch("leaps_scraper.activate_target", new=AsyncMock()),
        patch("leaps_scraper.cdp_eval", new=cdp_eval_mock),
    ]
    if wait_mock:
        patches.append(patch("leaps_scraper._wait_for_grid", new=wait_mock))
    if confirm_mock:
        patches.append(patch("leaps_scraper._confirm_empty", new=confirm_mock))

    buf = io.StringIO()
    for p in patches:
        p.start()
    try:
        with patch("sys.stdout", buf):
            _run(scraper.main("NOK", user_strike=7.0))
    finally:
        for p in patches:
            p.stop()
    out = buf.getvalue().strip()
    return json.loads(out) if out else None


# ---------------------------------------------------------------------------
# _wait_for_grid
# ---------------------------------------------------------------------------
class TestWaitForGrid(unittest.TestCase):

    def test_returns_data_immediately(self):
        rows = [{"strike": 7}]
        with patch("leaps_scraper.cdp_eval", new=AsyncMock(return_value=rows)):
            result = _run(scraper._wait_for_grid("ws://", "JS", max_wait_s=5))
        self.assertEqual(result, rows)

    def test_returns_empty_list_immediately(self):
        """[] is not None — returns immediately; caller must do stability check."""
        with patch("leaps_scraper.cdp_eval", new=AsyncMock(return_value=[])):
            result = _run(scraper._wait_for_grid("ws://", "JS", max_wait_s=2))
        self.assertEqual(result, [])

    def test_polls_until_data_arrives(self):
        responses = iter([None, None, [{"strike": 7}]])
        mock = AsyncMock(side_effect=lambda *_: next(responses))
        with patch("leaps_scraper.cdp_eval", new=mock):
            result = _run(scraper._wait_for_grid("ws://", "JS", max_wait_s=5, poll_s=0.01))
        self.assertEqual(result, [{"strike": 7}])

    def test_returns_none_on_timeout(self):
        with patch("leaps_scraper.cdp_eval", new=AsyncMock(return_value=None)):
            result = _run(scraper._wait_for_grid("ws://", "JS", max_wait_s=0.05, poll_s=0.01))
        self.assertIsNone(result)


# ---------------------------------------------------------------------------
# _confirm_empty
# ---------------------------------------------------------------------------
class TestConfirmEmpty(unittest.TestCase):

    def test_still_empty_after_delay(self):
        with patch("leaps_scraper.cdp_eval", new=AsyncMock(return_value=[])):
            result = _run(scraper._confirm_empty("ws://", "JS", delay_s=0.001))
        self.assertEqual(result, [])

    def test_data_appeared_after_delay(self):
        rows = [{"strike": 7, "dte": 400}]
        with patch("leaps_scraper.cdp_eval", new=AsyncMock(return_value=rows)):
            result = _run(scraper._confirm_empty("ws://", "JS", delay_s=0.001))
        self.assertEqual(result, rows)

    def test_grid_unmounted_returns_none(self):
        with patch("leaps_scraper.cdp_eval", new=AsyncMock(return_value=None)):
            result = _run(scraper._confirm_empty("ws://", "JS", delay_s=0.001))
        self.assertIsNone(result)


# ---------------------------------------------------------------------------
# Stage 1 base: cdp_eval for NEAR_MONEY / UNDERLYING / EXPIRATIONS
# ---------------------------------------------------------------------------
def _stage1_eval(session_expired=False):
    """Route cdp_eval calls by JS content; works with or without wait_mock patch."""
    async def side(ws, js, **kw):
        if "bc-overlay-modal" in js:
            return session_expired
        if "angular.element" in js:   # UNDERLYING_JS
            return 12.07
        if "querySelectorAll" in js:  # EXPIRATIONS_JS
            return GOOD_EXPIRATIONS
        if "symbolType" in js and "bidPrice" not in js and "itmProbability" not in js:
            return GOOD_NEAR_MONEY    # NEAR_MONEY_JS (used when wait_mock=None)
        return None
    return AsyncMock(side_effect=side)


# ---------------------------------------------------------------------------
# opts None paths
# ---------------------------------------------------------------------------
class TestOptsNone(unittest.TestCase):

    def test_page_load_timeout(self):
        """Stage 2 opts _wait_for_grid → None, SESSION_EXPIRED_JS → False → page_load_timeout."""
        async def wait_side(ws, js, max_wait_s=30, **kw):
            # Stage 1 NEAR_MONEY must succeed so we reach Stage 2
            if "bidPrice" not in js and "itmProbability" not in js:
                return GOOD_NEAR_MONEY
            return None  # Stage 2 opts/vg → timeout

        result = _capture_main(_stage1_eval(session_expired=False),
                               wait_mock=AsyncMock(side_effect=wait_side))
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["expired_layer"], "options_prices")
        self.assertEqual(result["reason"], "page_load_timeout")
        self.assertIn("skipped_strikes", result)

    def test_session_expired(self):
        """Stage 2 opts _wait_for_grid → None, SESSION_EXPIRED_JS → True → session_expired."""
        async def wait_side(ws, js, max_wait_s=30, **kw):
            if "bidPrice" not in js and "itmProbability" not in js:
                return GOOD_NEAR_MONEY  # Stage 1 → success
            return None  # Stage 2 opts → timeout → check SESSION_EXPIRED_JS → True

        result = _capture_main(_stage1_eval(session_expired=True),
                               wait_mock=AsyncMock(side_effect=wait_side))
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["reason"], "session_expired")


# ---------------------------------------------------------------------------
# opts [] paths
# ---------------------------------------------------------------------------
class TestOptsEmpty(unittest.TestCase):

    def test_confirmed_empty_skips_and_continues(self):
        """opts_rows=[] confirmed → skipped_strikes logged; loop finishes without partial."""
        async def wait_side(ws, js, max_wait_s=30, **kw):
            if "itmProbability" in js:
                return GOOD_VG        # vg → data (but opts skipped so vg never reached anyway)
            if "bidPrice" not in js and "itmProbability" not in js:
                return GOOD_NEAR_MONEY  # NEAR_MONEY_JS → Stage 1
            return []                 # STACKED_OPTIONS_JS → empty (triggers confirm)

        confirm_mock = AsyncMock(return_value=[])  # confirmed empty
        eval_mock = _stage1_eval()

        result = _capture_main(eval_mock,
                               wait_mock=AsyncMock(side_effect=wait_side),
                               confirm_mock=confirm_mock)
        self.assertIsNotNone(result)
        # All strikes skipped → skipped_strikes has entries
        skipped = result.get("skipped_strikes", [])
        self.assertTrue(len(skipped) > 0, f"Expected skipped entries, got: {skipped}")
        # Status is not partial (skipping empties is non-fatal)
        self.assertNotEqual(result.get("status"), "partial")

    def test_data_appears_after_stability_no_skip(self):
        """opts_rows=[] then data → strike NOT in skipped_strikes."""
        # _wait_for_grid → [] ; _confirm_empty → GOOD_OPTS
        # vg: _wait_for_grid → GOOD_VG
        async def wait_side(ws, js, max_wait_s=30, **kw):
            if "itmProbability" in js:
                return GOOD_VG      # V&G call → data
            if "bidPrice" in js:
                return []           # opts call → empty first (triggers _confirm_empty)
            return GOOD_NEAR_MONEY  # NEAR_MONEY_JS (Stage 1)

        confirm_mock = AsyncMock(return_value=GOOD_OPTS)  # data appeared

        eval_mock = _stage1_eval()
        result = _capture_main(eval_mock,
                               wait_mock=AsyncMock(side_effect=wait_side),
                               confirm_mock=confirm_mock)
        if result:
            skipped = result.get("skipped_strikes", [])
            opt_skips = [s for s in skipped if s.get("layer") == "options_prices"]
            self.assertEqual(opt_skips, [],
                             f"opts should not be skipped when data appeared: {skipped}")

    def test_confirm_returns_none_emits_partial(self):
        """opts_rows=[] → _confirm_empty → None → emit partial (grid unmounted)."""
        async def wait_side(ws, js, max_wait_s=30, **kw):
            if "bidPrice" not in js and "itmProbability" not in js:
                return GOOD_NEAR_MONEY  # NEAR_MONEY_JS
            return []                   # opts → empty (triggers confirm)

        result = _capture_main(_stage1_eval(session_expired=False),
                               wait_mock=AsyncMock(side_effect=wait_side),
                               confirm_mock=AsyncMock(return_value=None))
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["expired_layer"], "options_prices")


# ---------------------------------------------------------------------------
# vg None / [] paths
# ---------------------------------------------------------------------------
class TestVgPaths(unittest.TestCase):

    def _vg_run(self, vg_wait_return, vg_confirm_return=None, session_expired=False):
        """Run main() with opts always succeeding, vg controlled."""
        async def wait_side(ws, js, max_wait_s=30, **kw):
            if "itmProbability" in js:
                return vg_wait_return    # V&G call
            if "bidPrice" in js:
                return GOOD_OPTS         # Stage 2 opts call
            return GOOD_NEAR_MONEY       # NEAR_MONEY_JS (Stage 1)

        confirm_mock = AsyncMock(return_value=vg_confirm_return) if vg_confirm_return is not None else None

        return _capture_main(_stage1_eval(session_expired=session_expired),
                             wait_mock=AsyncMock(side_effect=wait_side),
                             confirm_mock=confirm_mock)

    def test_vg_none_page_load_timeout(self):
        result = self._vg_run(vg_wait_return=None, session_expired=False)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["expired_layer"], "volatility_greeks")
        self.assertEqual(result["reason"], "page_load_timeout")

    def test_vg_none_session_expired(self):
        result = self._vg_run(vg_wait_return=None, session_expired=True)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["reason"], "session_expired")

    def test_vg_empty_confirmed_non_fatal(self):
        """vg=[] confirmed → logged in skipped_strikes, loop continues (non-fatal)."""
        result = self._vg_run(vg_wait_return=[], vg_confirm_return=[])
        self.assertIsNotNone(result)
        self.assertIn(result["status"], ("success", "partial"))
        if result["status"] == "success":
            skipped = result.get("skipped_strikes", [])
            vg_skips = [s for s in skipped if s.get("layer") == "volatility_greeks"]
            self.assertTrue(len(vg_skips) > 0,
                            f"V&G skip should be logged; got skipped={skipped}")

    def test_vg_empty_data_appears(self):
        """vg=[] then data → NOT skipped, rows merged."""
        result = self._vg_run(vg_wait_return=[], vg_confirm_return=GOOD_VG)
        if result and result["status"] == "success":
            skipped = result.get("skipped_strikes", [])
            vg_skips = [s for s in skipped if s.get("layer") == "volatility_greeks"]
            self.assertEqual(vg_skips, [], f"V&G should not be skipped; got {skipped}")


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------
class TestHappyPath(unittest.TestCase):

    def test_success_produces_rows_and_no_skips(self):
        async def _wait(ws, js, max_wait_s=30, **kw):
            if "itmProbability" in js:
                return GOOD_VG
            if "bidPrice" in js:
                return GOOD_OPTS
            return GOOD_NEAR_MONEY    # NEAR_MONEY_JS (Stage 1)
        wait_mock = AsyncMock(side_effect=_wait)
        result = _capture_main(_stage1_eval(), wait_mock=wait_mock)
        self.assertIsNotNone(result)
        self.assertEqual(result["status"], "success")
        self.assertIn("rows", result)
        self.assertEqual(result.get("skipped_strikes", []), [])



# ---------------------------------------------------------------------------
# invalid_strike path (Stage 1 post-check)
# ---------------------------------------------------------------------------
class TestInvalidStrike(unittest.TestCase):

    def test_strike_out_of_range_emits_invalid_strike(self):
        """user_strike=2.0 is outside NOK range [6.5, 7.5] → invalid_strike status."""
        async def wait_s(ws, js, max_wait_s=30, **kw):
            return GOOD_NEAR_MONEY   # Stage 1 always succeeds (no Stage 2 reached)

        buf = io.StringIO()
        with (
            patch("leaps_scraper.prepare_page", new=AsyncMock(return_value=("tid", "ws://fake"))),
            patch("leaps_scraper.cdp_navigate", new=AsyncMock()),
            patch("leaps_scraper.activate_target", new=AsyncMock()),
            patch("leaps_scraper.cdp_eval", new=_stage1_eval()),
            patch("leaps_scraper._wait_for_grid", new=AsyncMock(side_effect=wait_s)),
            patch("sys.stdout", buf),
        ):
            _run(scraper.main("NOK", user_strike=2.0))

        result = json.loads(buf.getvalue().strip())
        self.assertEqual(result["status"], "invalid_strike")
        self.assertIn("chain_snapshot", result)
        self.assertIn("strikes", result["chain_snapshot"])
        self.assertIn("spot_price", result["chain_snapshot"])
        self.assertIn("message", result)
        self.assertIn("2.0", result["message"])

    def test_strike_in_range_does_not_abort(self):
        """user_strike=7.0 within [6.5, 7.5] → proceeds past validation (not invalid_strike)."""
        async def wait_s(ws, js, max_wait_s=30, **kw):
            if "itmProbability" in js:
                return GOOD_VG
            if "bidPrice" in js:
                return GOOD_OPTS
            return GOOD_NEAR_MONEY

        result = _capture_main(_stage1_eval(), wait_mock=AsyncMock(side_effect=wait_s))
        self.assertIsNotNone(result)
        self.assertNotEqual(result.get("status"), "invalid_strike")


class TestLeapsChainSnapshot(unittest.TestCase):
    """
    Regression tests for the 2026-07-07 NOK bug: chain_snapshot was built from
    the near-term (nearest weekly) near-money view, not the LEAPS-dated
    expiration — legitimate deep-ITM LEAPS strikes absent from the near-term
    ladder were falsely rejected as invalid_strike.
    """

    NEAR_TERM_ROWS = [
        {"strike": 8.0, "delta": 0.55, "strikePrice": 8.0},
        {"strike": 9.0, "delta": 0.45, "strikePrice": 9.0},
    ]
    # $7 exists only on the LEAPS chain (deep ITM, real Delta/OI) — absent
    # from NEAR_TERM_ROWS above, mirroring the live NOK repro.
    LEAPS_CHAIN_ROWS = [
        {"strike": 7.0, "delta": 0.85, "strikePrice": 7.0},
        {"strike": 10.0, "delta": 0.70, "strikePrice": 10.0},
        {"strike": 12.0, "delta": 0.60, "strikePrice": 12.0},
    ]

    def _run_with_two_near_money_calls(self, user_strike):
        near_money_calls = {"n": 0}

        # GOOD_EXPIRATIONS (2027-01-15) isn't reliably >= LEAPS_MIN_DTE relative
        # to "today" whenever this suite runs — compute a genuinely far-dated
        # expiration so the fix's happy path (LEAPS-dated fetch) is exercised.
        far_date = (scraper.date.today() + scraper.timedelta(days=scraper.LEAPS_MIN_DTE + 30))
        far_exp = [{"value": far_date.strftime("%Y-%m-%d") + "-m", "text": "far LEAPS"}]

        async def eval_side(ws, js, **kw):
            if "bc-overlay-modal" in js:
                return False
            if "angular.element" in js:
                return 12.07
            if "querySelectorAll" in js:
                return far_exp
            return None

        async def wait_s(ws, js, max_wait_s=30, **kw):
            if "symbolType" in js and "bidPrice" not in js and "itmProbability" not in js:
                near_money_calls["n"] += 1
                # 1st call = original NTM page (near-term expiration, no `expiration=` param)
                # 2nd call = new LEAPS-dated-expiration fetch (the fix)
                return self.NEAR_TERM_ROWS if near_money_calls["n"] == 1 else self.LEAPS_CHAIN_ROWS
            if "itmProbability" in js:
                return GOOD_VG
            if "bidPrice" in js:
                return GOOD_OPTS
            return None

        buf = io.StringIO()
        with (
            patch("leaps_scraper.prepare_page", new=AsyncMock(return_value=("tid", "ws://fake"))),
            patch("leaps_scraper.cdp_navigate", new=AsyncMock()),
            patch("leaps_scraper.activate_target", new=AsyncMock()),
            patch("leaps_scraper.cdp_eval", new=AsyncMock(side_effect=eval_side)),
            patch("leaps_scraper._wait_for_grid", new=AsyncMock(side_effect=wait_s)),
            patch("sys.stdout", buf),
        ):
            _run(scraper.main("NOK", user_strike=user_strike))
        return json.loads(buf.getvalue().strip()), near_money_calls["n"]

    def test_chain_snapshot_reflects_leaps_expiration_not_near_term(self):
        """chain_snapshot.strikes must be the LEAPS-dated chain (7/10/12), not
        the near-term ladder (8/9) — this is the root-cause fix itself."""
        result, calls = self._run_with_two_near_money_calls(user_strike=10.0)
        self.assertEqual(calls, 2, "expected two NEAR_MONEY_JS fetches: near-term + LEAPS-dated")
        self.assertEqual(result["chain_snapshot"]["strikes"], [7.0, 10.0, 12.0])

    def test_strike_absent_from_near_term_but_present_in_leaps_is_valid(self):
        """$7 exists only on the LEAPS chain — must NOT be rejected as invalid_strike
        even though it's absent from the near-term ladder (the exact NOK repro)."""
        result, _ = self._run_with_two_near_money_calls(user_strike=7.0)
        self.assertNotEqual(result.get("status"), "invalid_strike")

    def test_strike_absent_from_both_chains_is_invalid(self):
        """Sanity check: a strike outside BOTH ladders is still correctly rejected."""
        result, _ = self._run_with_two_near_money_calls(user_strike=2.0)
        self.assertEqual(result["status"], "invalid_strike")

    def test_no_leaps_dated_expiration_falls_back_to_near_term(self):
        """If no expiration is >= LEAPS_MIN_DTE out, fall back to the near-term
        near-money list rather than an empty chain_snapshot."""
        near_term_only_eval = AsyncMock(side_effect=lambda ws, js, **kw: (
            False if "bc-overlay-modal" in js else
            12.07 if "angular.element" in js else
            [{"value": "2026-07-10-w", "text": "near-term only"}] if "querySelectorAll" in js else
            None
        ))

        async def wait_s(ws, js, max_wait_s=30, **kw):
            if "symbolType" in js and "bidPrice" not in js and "itmProbability" not in js:
                return self.NEAR_TERM_ROWS
            return None

        buf = io.StringIO()
        with (
            patch("leaps_scraper.prepare_page", new=AsyncMock(return_value=("tid", "ws://fake"))),
            patch("leaps_scraper.cdp_navigate", new=AsyncMock()),
            patch("leaps_scraper.activate_target", new=AsyncMock()),
            patch("leaps_scraper.cdp_eval", new=near_term_only_eval),
            patch("leaps_scraper._wait_for_grid", new=AsyncMock(side_effect=wait_s)),
            patch("sys.stdout", buf),
        ):
            _run(scraper.main("NOK", user_strike=8.5))

        result = json.loads(buf.getvalue().strip())
        self.assertEqual(result["chain_snapshot"]["strikes"], [8.0, 9.0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
