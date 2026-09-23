from test_providers import load

recording = load("recording")


def test_history_restart_and_failed_memory_never_block_new_session(tmp_path):
    r = recording.Recording(tmp_path, importer=lambda row: False)
    first = r.action("start")
    r.action("pet", "click-1", first["id"])
    r.action("pet", "click-1", first["id"])
    r.action("ask", "click-2", first["id"])
    r.action("end")
    r.flush_pending()
    assert r.snapshot()["pending_memory"] == 1
    assert r.action("start")["active"]
    r.action("pet", "click-3")
    restarted = recording.Recording(tmp_path)
    assert restarted.snapshot()["active"]
    assert restarted.snapshot()["totals"] == {"pet": 2, "ask": 1, "sessions": 2}
    restarted.action("end")
    assert len(restarted.snapshot()["history"]) == 2


def test_migrate_v1_and_retry_all_pending(tmp_path):
    import json

    (tmp_path / "recording.json").write_text(
        json.dumps(
            {
                "id": "old",
                "active": False,
                "pet": 5,
                "ask": 2,
                "start": "yesterday",
                "end": "today",
                "summary": "old summary",
                "memory_saved": False,
            }
        )
    )
    imported = []

    def importer(row):
        imported.append(row["id"])
        return True

    r = recording.Recording(tmp_path, importer=importer)
    r.action("start")
    r.action("end")
    r.flush_pending()
    assert len(imported) == 2
    assert r.snapshot()["pending_memory"] == 0
    assert r.snapshot()["totals"]["pet"] == 5
    r.flush_pending()
    assert len(imported) == 2


def test_slow_memory_does_not_block_counts_or_exit(tmp_path):
    import threading

    gate = threading.Event()
    entered = threading.Event()

    def importer(row):
        entered.set()
        gate.wait(3)
        return True

    r = recording.Recording(tmp_path, importer=importer)
    r.action("start")
    r.action("end")
    r.start()
    assert entered.wait(1)
    r.action("start")
    assert r.action("pet")["pet"] == 1
    assert not r.action("end")["active"]
    gate.set()
    r.close()


def test_corrupt_primary_recovers_backup_without_resetting_counts(tmp_path):
    r = recording.Recording(tmp_path)
    r.action("start")
    r.action("pet")
    r.path.write_text("damaged")
    recovered = recording.Recording(tmp_path)
    assert recovered.snapshot()["pet"] == 1
    recovered.action("ask")
    assert recording.Recording(tmp_path).snapshot()["totals"]["ask"] == 1


def test_unreadable_records_are_not_overwritten(tmp_path):
    (tmp_path / "recording.json").write_text("damaged")
    r = recording.Recording(tmp_path)
    assert r.action("start")["error"]
    assert r.path.read_text() == "damaged"
