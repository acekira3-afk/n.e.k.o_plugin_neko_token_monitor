import importlib.util
import sys
import tempfile
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
pkg = types.ModuleType("_catfood_test")
pkg.__path__ = [str(ROOT)]
sys.modules["_catfood_test"] = pkg


def load(name):
    spec = importlib.util.spec_from_file_location("_catfood_test." + name, ROOT / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


providers = load("providers")
core = load("core")


def test_openai_pagination_and_usd():
    pages = [
        {
            "data": [{"results": [{"amount": {"value": "1.25", "currency": "usd"}}]}],
            "has_more": True,
            "next_page": "p2",
        },
        {"data": [{"results": [{"amount": {"value": "2.00", "currency": "usd"}}]}], "has_more": False},
    ]
    calls = []

    def request(url, headers):
        calls.append(url)
        assert headers["Authorization"] == "Bearer fake"
        return pages.pop(0)

    result = providers.query(
        dict(source="openai", budget=10, budget_start="2026-01-01", currency="USD", api_key="fake"), request
    )
    assert result["balance_infos"][0]["total_balance"] == "6.75"
    assert "page=p2" in calls[1]
    assert "非平台余额" in result["basis"]


def test_claude_cents_to_dollars():
    result = providers.query(
        dict(source="anthropic", budget=10, budget_start="2026-01-01", currency="USD", api_key="fake"),
        lambda u, h: {"data": [{"results": [{"amount": "125", "currency": "USD"}]}], "has_more": False},
    )
    assert result["balance_infos"][0]["total_balance"] == "8.75"


def test_custom_nested_path():
    cfg = dict(
        source="custom",
        endpoint="https://example.com/balance",
        value_path="data.accounts.0.balance",
        currency="CNY",
        api_key="fake",
    )
    result = providers.query(cfg, lambda u, h: {"data": {"accounts": [{"balance": "12.50"}]}})
    assert result["balance_infos"][0]["total_balance"] == "12.50"


def test_switch_does_not_send_old_key():
    with tempfile.TemporaryDirectory() as d:
        monitor = core.Monitor(d)
        monitor.configure({"api_key": "fake-test-secret"})
        monitor.configure({"source": "custom", "endpoint": "https://example.com/balance"})
        assert monitor.config["api_key"] == ""
        assert not monitor.snapshot()["configured"]
        monitor.configure({"source": "manual", "budget": 12, "model": "any model"})
        state = monitor.refresh()
        assert state["selected"]["balance"] == "12.0"
        assert state["basis"] == "手动填写 · 不自动扣减"
        assert "api_key" not in state["config"]


def test_reject_non_https_and_nonfinite():
    for url in ["http://example.com", "https://user:secret@example.com", "https://example.com?k=secret"]:
        try:
            providers.validate_endpoint(url)
        except ValueError:
            pass
        else:
            raise AssertionError(url)
    for value in ["NaN", "Infinity", True]:
        try:
            providers.money(value)
        except ValueError:
            pass
        else:
            raise AssertionError(value)
