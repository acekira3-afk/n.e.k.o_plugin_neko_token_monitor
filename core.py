"""Official balance reads only. No chat requests, no guessed token limits."""

import datetime as dt
import json
import math
import os
import threading
import time
import urllib.error
import urllib.request
from decimal import Decimal, InvalidOperation
from pathlib import Path

from .providers import query, validate_endpoint


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def query_balance(key):
    request = urllib.request.Request(
        "https://api.deepseek.com/user/balance", headers={"Authorization": "Bearer " + key}
    )
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=12) as response:
            return json.loads(response.read(65537))
    except urllib.error.HTTPError as exc:
        raise ValueError(
            {401: "密钥无效，请重新填写", 403: "账户无权查询余额", 429: "查询过于频繁，请稍后再试"}.get(
                exc.code, "余额接口暂不可用"
            )
        ) from None
    except Exception:
        raise ValueError("未能连接 DeepSeek，保留上次结果") from None


def parse_balance(payload):
    if type(payload.get("is_available")) is not bool:
        raise ValueError("余额接口返回了无法识别的数据")
    rows = []
    try:
        for item in payload["balance_infos"]:
            currency = item["currency"]
            amount = Decimal(item["total_balance"])
            if currency not in ("CNY", "USD") or not amount.is_finite():
                raise ValueError()
            if any(row["currency"] == currency for row in rows):
                raise ValueError()
            rows.append({"currency": currency, "balance": str(amount)})
        if not rows:
            raise ValueError()
    except (KeyError, TypeError, InvalidOperation, ValueError):
        raise ValueError("余额接口返回了无法识别的数据") from None
    return rows


class Monitor:
    def __init__(self, directory, fetch=query_balance, announce=None):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.lock = threading.RLock()
        self.fetch, self.announce = fetch, announce
        self.stop = threading.Event()
        self.thread = None
        self.last_attempt = 0
        self.last_alert = 0
        self.config = {
            "source": "deepseek",
            "model": "",
            "budget": 0,
            "budget_start": dt.date.today().replace(day=1).isoformat(),
            "endpoint": "",
            "value_path": "balance",
            "api_key": "",
            "price_per_million": None,
            "currency": "CNY",
            "low_balance": 2.0,
            "interval": 300,
            "alerts": True,
        }
        self.config.update(self.read("config.json", {}))
        self.state = self.read("state.json", {})

    def read(self, name, default):
        try:
            value = json.loads((self.directory / name).read_text())
            return value if isinstance(value, dict) else default
        except (OSError, ValueError):
            return default

    def write(self, name, value):
        path = self.directory / name
        temp = path.with_suffix(".tmp")
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, ensure_ascii=False)
        os.chmod(temp, 0o600)
        temp.replace(path)

    def configure(self, values):
        with self.lock:
            cfg = dict(self.config)
            source = values.get("source", cfg["source"])
            if source not in ("deepseek", "openai", "anthropic", "custom", "manual"):
                raise ValueError("查询方式无效")
            # Never reuse a previous provider's secret at a new destination.
            if source != cfg["source"] or values.get("endpoint", cfg["endpoint"]) != cfg["endpoint"]:
                cfg["api_key"] = ""
            cfg["source"] = source
            for field in ("model", "endpoint", "value_path", "budget_start"):
                if field in values:
                    if not isinstance(values[field], str) or len(values[field]) > 500:
                        raise ValueError("设置格式无效")
                    cfg[field] = values[field].strip()
            dt.date.fromisoformat(cfg["budget_start"])
            if source == "custom":
                validate_endpoint(cfg["endpoint"])
                if not cfg["value_path"] or any(
                    not part or not all(c.isalnum() or c == "_" for c in part) for part in cfg["value_path"].split(".")
                ):
                    raise ValueError("余额字段路径无效")
            if "api_key" in values and values["api_key"]:
                key = values["api_key"].strip()
                if not 8 <= len(key) <= 512 or not key.isascii() or any(c.isspace() for c in key):
                    raise ValueError("API Key 格式不正确")
                cfg["api_key"] = key
            for field, minimum, maximum in [
                ("budget", 0, 1000000000),
                ("price_per_million", 0.000001, 1000000),
                ("low_balance", 0, 1000000),
                ("interval", 60, 86400),
            ]:
                if field in values:
                    if field == "price_per_million" and values[field] in (None, ""):
                        cfg[field] = None
                        continue
                    number = float(values[field])
                    if not math.isfinite(number) or not minimum <= number <= maximum:
                        raise ValueError("价格、阈值或刷新间隔超出允许范围")
                    cfg[field] = number
            if "currency" in values:
                if values["currency"] not in ("CNY", "USD"):
                    raise ValueError("请选择 CNY 或 USD")
                cfg["currency"] = values["currency"]
            if "alerts" in values:
                if type(values["alerts"]) is not bool:
                    raise ValueError("提醒设置无效")
                cfg["alerts"] = values["alerts"]
            if source in ("openai", "anthropic"):
                cfg["currency"] = "USD"
            changed_key = any(
                cfg[k] != self.config[k]
                for k in ("source", "endpoint", "value_path", "api_key", "currency", "budget", "budget_start")
            )
            self.write("config.json", cfg)
            self.config = cfg
            if changed_key:
                self.state = {}
                self.last_attempt = self.last_alert = 0
                self.write("state.json", {})
        return self.snapshot()

    def snapshot(self):
        with self.lock:
            cfg = {k: v for k, v in self.config.items() if k != "api_key"}
            row = next((r for r in self.state.get("balances", []) if r["currency"] == cfg["currency"]), None)
            updated = self.state.get("updated_at")
            error = self.state.get("error")
            current = bool(updated and not error and time.time() - updated <= cfg["interval"] * 2)
            estimate = None
            if row and cfg["price_per_million"] and current:
                estimate = int(
                    max(Decimal(row["balance"]), Decimal(0)) * 1000000 / Decimal(str(cfg["price_per_million"]))
                )
            return {
                "config": cfg,
                "basis": self.state.get("basis", "官方账户余额"),
                "configured": self.config["source"] == "manual" or bool(self.config["api_key"]),
                "balances": self.state.get("balances", []),
                "selected": row,
                "updated_at": updated,
                "error": error,
                "stale": not current,
                "is_available": self.state.get("is_available") if current else None,
                "estimated_tokens": estimate,
                "estimate_only": True,
                "observed_net_change": self.state.get("daily", {}).get(cfg["currency"])
                if self.state.get("day") == dt.date.today().isoformat()
                else None,
            }

    def refresh(self):
        # Serialize refreshes and key changes; never send a stale key's results to a new account.
        with self.lock:
            if not self.config["api_key"] and self.config["source"] != "manual":
                return self.snapshot()
            if self.last_attempt and time.monotonic() - self.last_attempt < 60:
                return self.snapshot()
            self.last_attempt = time.monotonic()
            try:
                payload = (
                    self.fetch(self.config["api_key"]) if self.config["source"] == "deepseek" else query(self.config)
                )
                rows = parse_balance(payload)
                day = dt.date.today().isoformat()
                baseline = self.state.get("baseline", {}) if self.state.get("day") == day else {}
                daily = {}
                for row in rows:
                    currency = row["currency"]
                    baseline.setdefault(currency, row["balance"])
                    daily[currency] = str(Decimal(baseline[currency]) - Decimal(row["balance"]))
                self.state = {
                    "balances": rows,
                    "is_available": payload["is_available"],
                    "updated_at": time.time(),
                    "error": None,
                    "day": day,
                    "basis": payload.get("basis", "官方账户余额"),
                    "baseline": baseline,
                    "daily": daily,
                }
                self.write("state.json", self.state)
            except Exception as exc:
                self.state["error"] = str(exc) if isinstance(exc, ValueError) else "查询或保存失败，请稍后再试"
                return self.snapshot()
            snapshot = self.snapshot()
            row = snapshot["selected"]
            low = not payload["is_available"] or (
                row and Decimal(row["balance"]) <= Decimal(str(self.config["low_balance"]))
            )
            if (
                low
                and self.config["alerts"]
                and self.announce
                and (not self.last_alert or time.monotonic() - self.last_alert >= 3600)
            ):
                text = (
                    f"碳基生物，猫粮余额只剩 {row['balance']} {row['currency']} 了喵～"
                    if row
                    else "碳基生物，猫粮余额不足了喵～"
                )
                try:
                    if self.announce(text):
                        self.last_alert = time.monotonic()
                except Exception:
                    pass
            return snapshot

    def start(self):
        if self.thread and self.thread.is_alive():
            return

        def worker():
            while not self.stop.is_set():
                self.refresh()
                self.stop.wait(self.config["interval"])

        self.thread = threading.Thread(target=worker, daemon=True)
        self.thread.start()

    def close(self):
        self.stop.set()
        if self.thread:
            self.thread.join(14)
