import json
import logging
import os
import tempfile
import unittest

import kcc_watch as kw


class FakeResult:
    def __init__(self, returncode=0):
        self.returncode = returncode


class FakeRunner:
    def __init__(self, archive_rc=0, convert_rc=0):
        self.archive_rc = archive_rc
        self.convert_rc = convert_rc
        self.calls = []

    def __call__(self, command, **kwargs):
        self.calls.append(list(command))
        if "l" in command:
            return FakeResult(self.archive_rc)
        return FakeResult(self.convert_rc)

    @property
    def conversions(self):
        return [c for c in self.calls if "l" not in c]


class Clock:
    def __init__(self, start=0.0):
        self.value = start

    def __call__(self):
        return self.value

    def advance(self, seconds):
        self.value += seconds


class ConfigTests(unittest.TestCase):
    def test_defaults(self):
        config = kw.load_config(env={})
        self.assertTrue(config.enabled)
        self.assertEqual(config.poll_seconds, 10.0)
        self.assertEqual(config.settle_seconds, 60.0)
        self.assertEqual(config.output, "/calibredrop")
        self.assertEqual(config.concurrency, 1)
        self.assertEqual(config.fail_threshold, 3)
        self.assertEqual({f.name for f in config.folders}, {"comics", "manga"})
        self.assertIn(".cbz", config.extensions)
        self.assertIn(".rar", config.extensions)
        self.assertEqual({f.options for f in config.folders}, {"-p KoLC"})

    def test_global_options_env_and_folder_override(self):
        config = kw.load_config(env={"KCC_WATCH_OPTIONS": "-p KV"})
        self.assertEqual({f.options for f in config.folders}, {"-p KV"})
        config = kw.load_config(
            env={"KCC_WATCH_OPTIONS": "-p KV", "C2E_COMICS_OPTIONS": "-p K1"}
        )
        by_name = {f.name: f for f in config.folders}
        self.assertEqual(by_name["comics"].options, "-p K1")
        self.assertEqual(by_name["manga"].options, "-p KV")

    def test_env_overrides_ini(self):
        with tempfile.TemporaryDirectory() as tmp:
            ini = os.path.join(tmp, "kcc-watch.ini")
            with open(ini, "w") as handle:
                handle.write("[kcc-watch]\nsettle_seconds = 5\noutput = /from-ini\n")
            env = {
                "KCC_WATCH_CONFIG": ini,
                "KCC_WATCH_SETTLE": "99",
            }
            config = kw.load_config(env=env)
            self.assertEqual(config.settle_seconds, 99.0)
            self.assertEqual(config.output, "/from-ini")

    def test_ini_folder_sections(self):
        with tempfile.TemporaryDirectory() as tmp:
            ini = os.path.join(tmp, "kcc-watch.ini")
            with open(ini, "w") as handle:
                handle.write(
                    "[kcc-watch]\noutput = /out\n"
                    "[comics]\npath = /data/comics\noptions = -p K1 -m\n"
                    "[manga]\npath = /data/manga\noutput = /manga-out\n"
                )
            config = kw.load_config(env={"KCC_WATCH_CONFIG": ini})
            by_name = {f.name: f for f in config.folders}
            self.assertEqual(set(by_name), {"comics", "manga"})
            self.assertEqual(by_name["comics"].path, "/data/comics")
            self.assertEqual(by_name["comics"].options, "-p K1 -m")
            self.assertEqual(by_name["comics"].resolved_output("/out"), "/out")
            self.assertEqual(by_name["manga"].resolved_output("/out"), "/manga-out")

    def test_per_folder_env_override(self):
        env = {
            "C2E_COMICS_OPTIONS": "-p K2",
            "C2E_MANGA_OUTPUT": "/manga",
        }
        config = kw.load_config(env=env)
        by_name = {f.name: f for f in config.folders}
        self.assertEqual(by_name["comics"].options, "-p K2")
        self.assertEqual(by_name["manga"].resolved_output(config.output), "/manga")

    def test_concurrency_clamped_to_one(self):
        config = kw.load_config(env={"KCC_WATCH_CONCURRENCY": "0"})
        self.assertEqual(config.concurrency, 1)


class HelperTests(unittest.TestCase):
    def test_as_bool(self):
        for value in ("1", "true", "TRUE", "yes", "on", True):
            self.assertTrue(kw.as_bool(value))
        for value in ("0", "false", "no", "off", False):
            self.assertFalse(kw.as_bool(value))
        self.assertTrue(kw.as_bool(None, default=True))
        self.assertFalse(kw.as_bool(None, default=False))

    def test_normalize_extensions(self):
        self.assertEqual(
            kw.normalize_extensions("CBZ, .cbr;7z"),
            {".cbz", ".cbr", ".7z"},
        )

    def test_is_candidate(self):
        extensions = {".cbz", ".cbr"}
        self.assertTrue(kw.is_candidate("book.cbz", extensions))
        self.assertTrue(kw.is_candidate("BOOK.CBR", extensions))
        self.assertFalse(kw.is_candidate("book.pdf", extensions))
        self.assertFalse(kw.is_candidate(".hidden.cbz", extensions))
        self.assertFalse(kw.is_candidate("book", extensions))


class StabilityTrackerTests(unittest.TestCase):
    def test_requires_two_observations_over_settle(self):
        clock = Clock()
        tracker = kw.StabilityTracker(60, now=clock)
        self.assertFalse(tracker.is_stable("/a.cbz", 100, 1.0))
        clock.advance(30)
        self.assertFalse(tracker.is_stable("/a.cbz", 100, 1.0))
        clock.advance(30)
        self.assertTrue(tracker.is_stable("/a.cbz", 100, 1.0))

    def test_resets_when_changed(self):
        clock = Clock()
        tracker = kw.StabilityTracker(60, now=clock)
        tracker.is_stable("/a.cbz", 100, 1.0)
        clock.advance(120)
        self.assertFalse(tracker.is_stable("/a.cbz", 200, 1.0))
        clock.advance(120)
        self.assertTrue(tracker.is_stable("/a.cbz", 200, 1.0))

    def test_prune_forgets_missing(self):
        tracker = kw.StabilityTracker(60, now=Clock())
        tracker.is_stable("/a.cbz", 1, 1.0)
        tracker.prune(set())
        self.assertFalse(tracker.is_stable("/a.cbz", 1, 1.0))


class StateStoreTests(unittest.TestCase):
    def test_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "state.json")
            store = kw.StateStore(path)
            store.set("/a.cbz", status="failed", attempts=2)
            store.save()
            reloaded = kw.StateStore(path)
            reloaded.load()
            self.assertEqual(reloaded.attempts("/a.cbz"), 2)
            self.assertEqual(reloaded.get("/a.cbz")["status"], "failed")

    def test_missing_file_is_empty(self):
        store = kw.StateStore("/nonexistent/state.json")
        store.load()
        self.assertEqual(store.attempts("/a.cbz"), 0)

    def test_prune(self):
        store = kw.StateStore("/tmp/ignored.json")
        store.set("/a.cbz", attempts=1)
        store.prune(set())
        self.assertEqual(store.attempts("/a.cbz"), 0)


class CommandTests(unittest.TestCase):
    def test_build_command_with_options(self):
        command = kw.build_command(
            "/usr/local/bin/kcc-c2e", '-p K1 -m --title "My Book"', "/out", "/in/a.cbz"
        )
        self.assertEqual(
            command,
            ["/usr/local/bin/kcc-c2e", "-p", "K1", "-m", "--title", "My Book", "-o", "/out", "/in/a.cbz"],
        )

    def test_build_command_without_options(self):
        command = kw.build_command("kcc-c2e", "   ", "/out", "/in/a.cbz")
        self.assertEqual(command, ["kcc-c2e", "-o", "/out", "/in/a.cbz"])

    def test_inotify_command(self):
        config = kw.Config(folders=[kw.Folder("comics", "/c2e_comics")], inotifywait="inotifywait")
        command = kw.inotify_command(config)
        self.assertEqual(command[0], "inotifywait")
        self.assertIn("/c2e_comics", command)
        self.assertEqual(command[-1], "/c2e_comics")


class ValidateArchiveTests(unittest.TestCase):
    def test_valid(self):
        self.assertTrue(kw.validate_archive("/a.cbz", "7z", runner=FakeRunner(archive_rc=0)))

    def test_invalid(self):
        self.assertFalse(kw.validate_archive("/a.cbz", "7z", runner=FakeRunner(archive_rc=2)))

    def test_missing_binary(self):
        def boom(*_args, **_kwargs):
            raise FileNotFoundError("7z")

        self.assertFalse(kw.validate_archive("/a.cbz", "7z", runner=boom))


class HandleFileTests(unittest.TestCase):
    def setUp(self):
        self.logger = logging.getLogger("test")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.source_dir = os.path.join(self.tmp.name, "src")
        self.output_dir = os.path.join(self.tmp.name, "out")
        os.makedirs(self.source_dir)
        self.state = kw.StateStore(os.path.join(self.tmp.name, "state.json"))
        self.folder = kw.Folder("comics", self.source_dir, options="-p K1")
        self.config = kw.Config(
            output=self.output_dir,
            sevenzip="7z",
            kcc_c2e="kcc-c2e",
            fail_threshold=3,
            folders=[self.folder],
        )

    def _source(self, name="a.cbz"):
        path = os.path.join(self.source_dir, name)
        with open(path, "wb") as handle:
            handle.write(b"data")
        return path

    def test_success_deletes_source_and_runs_kcc(self):
        source = self._source()
        runner = FakeRunner(archive_rc=0, convert_rc=0)
        result = kw.handle_file(source, self.folder, self.config, self.state, runner=runner, logger=self.logger)
        self.assertTrue(result)
        self.assertFalse(os.path.exists(source))
        self.assertEqual(len(runner.conversions), 1)
        self.assertEqual(
            runner.conversions[0],
            ["kcc-c2e", "-p", "K1", "-o", self.output_dir, source],
        )
        self.assertEqual(self.state.get(source)["status"], "done")

    def test_failure_moves_to_failed_after_threshold(self):
        source = self._source()
        runner = FakeRunner(archive_rc=0, convert_rc=1)
        for attempt in range(1, 3):
            self.assertFalse(
                kw.handle_file(source, self.folder, self.config, self.state, runner=runner, logger=self.logger)
            )
            self.assertTrue(os.path.exists(source))
            self.assertEqual(self.state.attempts(source), attempt)
        self.assertFalse(
            kw.handle_file(source, self.folder, self.config, self.state, runner=runner, logger=self.logger)
        )
        failed_path = os.path.join(self.source_dir, ".failed", "a.cbz")
        self.assertFalse(os.path.exists(source))
        self.assertTrue(os.path.exists(failed_path))
        self.assertEqual(self.state.get(source)["status"], "moved")

    def test_invalid_archive_does_not_run_conversion(self):
        source = self._source()
        runner = FakeRunner(archive_rc=2, convert_rc=0)
        kw.handle_file(source, self.folder, self.config, self.state, runner=runner, logger=self.logger)
        self.assertEqual(runner.conversions, [])

    def test_per_folder_output_used(self):
        folder = kw.Folder("manga", self.source_dir, output=os.path.join(self.tmp.name, "manga-out"))
        source = self._source()
        runner = FakeRunner()
        kw.handle_file(source, folder, self.config, self.state, runner=runner, logger=self.logger)
        self.assertIn(os.path.join(self.tmp.name, "manga-out"), runner.conversions[0])


class ScanTests(unittest.TestCase):
    def test_scan_once_returns_stable_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "a.cbz"), "wb") as handle:
                handle.write(b"x")
            with open(os.path.join(tmp, "b.txt"), "wb") as handle:
                handle.write(b"x")
            clock = Clock()
            config = kw.Config(
                settle_seconds=60,
                extensions={".cbz"},
                folders=[kw.Folder("comics", tmp)],
                state_file=os.path.join(tmp, "state.json"),
            )
            watcher = kw.Watcher(config, now=clock)
            self.assertEqual(watcher.scan_once(), [])
            clock.advance(120)
            ready = watcher.scan_once()
            self.assertEqual([os.path.basename(p) for p, _ in ready], ["a.cbz"])

    def test_scan_missing_dir_is_ignored(self):
        config = kw.Config(
            settle_seconds=0,
            extensions={".cbz"},
            folders=[kw.Folder("comics", "/does/not/exist")],
        )
        watcher = kw.Watcher(config)
        self.assertEqual(watcher.scan_once(), [])


if __name__ == "__main__":
    unittest.main()
