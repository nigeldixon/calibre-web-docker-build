#!/usr/bin/env python3
"""Watch drop folders and run kcc-c2e on completed comic/manga archives.

Completion detection is a polling stability scanner, which works on local
disks, bind mounts, NFS and CIFS. When ``inotifywait`` is available it is used
only to shorten the latency of local drops; correctness never depends on it.
"""

from __future__ import annotations

import configparser
import json
import logging
import os
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Set, Tuple

LOG = logging.getLogger("kcc-watch")

DEFAULT_FOLDERS: Dict[str, str] = {
    "comics": "/c2e_comics",
    "manga": "/c2e_manga",
}

DEFAULTS: Dict[str, str] = {
    "enabled": "true",
    "poll_seconds": "10",
    "settle_seconds": "60",
    "extensions": "cbz, cbr, cb7, cbt, zip, rar, 7z, pdf",
    "output": "/calibredrop",
    # -p KoLC targets the Kobo Libra Colour geometry, but kcc-c2e still
    # converts to grayscale unless --forcecolor is given. The GUI derives
    # that from the profile; the command line does not.
    "options": "-p KoLC --forcecolor",
    "concurrency": "1",
    "use_inotify": "true",
    "fail_threshold": "3",
    "kcc_c2e": "/usr/local/bin/kcc-c2e",
    "sevenzip": "7z",
    "inotifywait": "inotifywait",
    "state_file": "/config/kcc-watch-state.json",
    "config_file": "/config/kcc-watch.ini",
}

ENV_GLOBALS: Dict[str, str] = {
    "KCC_WATCH_ENABLED": "enabled",
    "KCC_WATCH_POLL": "poll_seconds",
    "KCC_WATCH_SETTLE": "settle_seconds",
    "KCC_WATCH_EXTENSIONS": "extensions",
    "KCC_WATCH_OUTPUT": "output",
    "KCC_WATCH_OPTIONS": "options",
    "KCC_WATCH_CONCURRENCY": "concurrency",
    "KCC_WATCH_USE_INOTIFY": "use_inotify",
    "KCC_WATCH_FAIL_THRESHOLD": "fail_threshold",
    "KCC_WATCH_KCC_C2E": "kcc_c2e",
    "KCC_WATCH_SEVENZIP": "sevenzip",
    "KCC_WATCH_INOTIFYWAIT": "inotifywait",
    "KCC_WATCH_STATE": "state_file",
    "KCC_WATCH_CONFIG": "config_file",
}

TRUE_VALUES = {"1", "true", "yes", "on"}


def as_bool(value: object, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in TRUE_VALUES


def normalize_extensions(value: str) -> Set[str]:
    extensions: Set[str] = set()
    for part in str(value).replace(";", ",").split(","):
        part = part.strip().lower()
        if not part:
            continue
        if not part.startswith("."):
            part = "." + part
        extensions.add(part)
    return extensions


def is_candidate(name: str, extensions: Set[str]) -> bool:
    if name.startswith("."):
        return False
    return os.path.splitext(name)[1].lower() in extensions


@dataclass
class Folder:
    name: str
    path: str
    options: str = ""
    output: Optional[str] = None

    def resolved_output(self, default_output: str) -> str:
        return self.output or default_output


@dataclass
class Config:
    enabled: bool = True
    poll_seconds: float = 10.0
    settle_seconds: float = 60.0
    extensions: Set[str] = field(default_factory=set)
    output: str = "/calibredrop"
    concurrency: int = 1
    use_inotify: bool = True
    fail_threshold: int = 3
    kcc_c2e: str = "/usr/local/bin/kcc-c2e"
    sevenzip: str = "7z"
    inotifywait: str = "inotifywait"
    state_file: str = "/config/kcc-watch-state.json"
    config_file: str = "/config/kcc-watch.ini"
    folders: List[Folder] = field(default_factory=list)


def _parse_ini(ini_path: str) -> Tuple[Dict[str, str], Dict[str, Dict[str, Optional[str]]]]:
    values: Dict[str, str] = {}
    sections: Dict[str, Dict[str, Optional[str]]] = {}
    if not ini_path or not os.path.isfile(ini_path):
        return values, sections
    parser = configparser.ConfigParser()
    try:
        parser.read(ini_path)
    except configparser.Error as exc:
        LOG.warning("could not parse %s: %s", ini_path, exc)
        return values, sections
    if parser.has_section("kcc-watch"):
        for key, value in parser.items("kcc-watch"):
            values[key] = value
    for section in parser.sections():
        if section == "kcc-watch":
            continue
        path = parser.get(section, "path", fallback=None)
        if not path:
            continue
        sections[section] = {
            "path": path,
            "options": parser.get(section, "options", fallback=""),
            "output": parser.get(section, "output", fallback=None),
        }
    return values, sections


def load_config(env: Optional[Dict[str, str]] = None) -> Config:
    env = dict(os.environ if env is None else env)

    values = dict(DEFAULTS)
    ini_values, folder_sections = _parse_ini(env.get("KCC_WATCH_CONFIG", DEFAULTS["config_file"]))
    values.update(ini_values)

    if not folder_sections:
        folder_sections = {
            name: {"path": path, "options": "", "output": None}
            for name, path in DEFAULT_FOLDERS.items()
        }

    for env_key, key in ENV_GLOBALS.items():
        if env_key in env:
            values[key] = env[env_key]

    for name, section in folder_sections.items():
        prefix = "C2E_" + name.upper().replace("-", "_")
        if f"{prefix}_OPTIONS" in env:
            section["options"] = env[f"{prefix}_OPTIONS"]
        if f"{prefix}_OUTPUT" in env:
            section["output"] = env[f"{prefix}_OUTPUT"]

    folders = [
        Folder(name=name, path=section["path"] or "", options=section.get("options") or values.get("options", ""),
               output=section.get("output"))
        for name, section in folder_sections.items()
    ]

    return Config(
        enabled=as_bool(values.get("enabled"), True),
        poll_seconds=float(values["poll_seconds"]),
        settle_seconds=float(values["settle_seconds"]),
        extensions=normalize_extensions(values["extensions"]),
        output=values["output"],
        concurrency=max(1, int(values["concurrency"])),
        use_inotify=as_bool(values.get("use_inotify"), True),
        fail_threshold=max(1, int(values["fail_threshold"])),
        kcc_c2e=values["kcc_c2e"],
        sevenzip=values["sevenzip"],
        inotifywait=values["inotifywait"],
        state_file=values["state_file"],
        config_file=values["config_file"],
        folders=folders,
    )


class StabilityTracker:
    """Remembers size/mtime per path and reports when a file has stopped changing."""

    def __init__(self, settle_seconds: float, now: Callable[[], float] = time.monotonic):
        self.settle_seconds = settle_seconds
        self._now = now
        self._seen: Dict[str, Tuple[int, float, float]] = {}

    def is_stable(self, path: str, size: int, mtime: float) -> bool:
        now = self._now()
        previous = self._seen.get(path)
        if previous is None or previous[0] != size or previous[1] != mtime:
            self._seen[path] = (size, mtime, now)
            return False
        return (now - previous[2]) >= self.settle_seconds

    def forget(self, path: str) -> None:
        self._seen.pop(path, None)

    def prune(self, existing: Set[str]) -> None:
        for path in list(self._seen):
            if path not in existing:
                del self._seen[path]


class StateStore:
    """Thread-safe, atomically-persisted per-file state."""

    def __init__(self, path: str):
        self.path = path
        self._lock = threading.RLock()
        self._data: Dict[str, Dict[str, object]] = {}

    def load(self) -> None:
        with self._lock:
            try:
                with open(self.path, "r", encoding="utf-8") as handle:
                    loaded = json.load(handle)
                self._data = loaded if isinstance(loaded, dict) else {}
            except (OSError, ValueError):
                self._data = {}

    def save(self) -> None:
        with self._lock:
            directory = os.path.dirname(self.path)
            if directory:
                os.makedirs(directory, exist_ok=True)
            tmp = self.path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as handle:
                json.dump(self._data, handle, indent=2, sort_keys=True)
            os.replace(tmp, self.path)

    def get(self, path: str) -> Dict[str, object]:
        with self._lock:
            return dict(self._data.get(path, {}))

    def attempts(self, path: str) -> int:
        try:
            return int(self.get(path).get("attempts", 0))  # type: ignore[arg-type]
        except (TypeError, ValueError):
            return 0

    def set(self, path: str, **fields: object) -> None:
        with self._lock:
            entry = self._data.setdefault(path, {})
            entry.update(fields)

    def prune(self, existing: Set[str]) -> None:
        with self._lock:
            for path in list(self._data):
                if path not in existing:
                    del self._data[path]


def build_command(kcc_c2e: str, options: str, output: str, source: str) -> List[str]:
    command = [kcc_c2e]
    if options and options.strip():
        command.extend(shlex.split(options))
    if output:
        command.extend(["-o", output])
    command.append(source)
    return command


def validate_archive(
    path: str,
    sevenzip: str,
    runner: Callable[..., object] = subprocess.run,
    timeout: float = 300,
) -> bool:
    try:
        result = runner(
            [sevenzip, "l", "-y", "-p1", path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return getattr(result, "returncode", 1) == 0


def inotify_command(config: Config) -> List[str]:
    dirs = [folder.path for folder in config.folders]
    return [
        config.inotifywait,
        "-m",
        "-q",
        "-e",
        "close_write,moved_to,create",
        "--format",
        "%w%f",
        *dirs,
    ]


def _fail(
    source: str,
    folder: Folder,
    config: Config,
    state: StateStore,
    reason: str,
    logger: logging.Logger,
) -> bool:
    attempts = state.attempts(source) + 1
    state.set(source, status="failed", attempts=attempts, reason=reason)
    logger.error("failed (%d/%d) %s: %s", attempts, config.fail_threshold, source, reason)
    if attempts >= config.fail_threshold:
        failed_dir = os.path.join(folder.path, ".failed")
        destination = os.path.join(failed_dir, os.path.basename(source))
        try:
            os.makedirs(failed_dir, exist_ok=True)
            shutil.move(source, destination)
            state.set(source, status="moved", moved_to=destination)
            logger.error("moved %s to %s", source, destination)
        except OSError as exc:
            logger.error("could not move %s to %s: %s", source, failed_dir, exc)
    return False


def handle_file(
    source: str,
    folder: Folder,
    config: Config,
    state: StateStore,
    runner: Callable[..., object] = subprocess.run,
    logger: logging.Logger = LOG,
) -> bool:
    output = folder.resolved_output(config.output)
    if not validate_archive(source, config.sevenzip, runner=runner):
        return _fail(source, folder, config, state, "invalid or incomplete archive", logger)

    try:
        os.makedirs(output, exist_ok=True)
    except OSError as exc:
        return _fail(source, folder, config, state, f"cannot create output dir: {exc}", logger)

    command = build_command(config.kcc_c2e, folder.options, output, source)
    logger.info("converting %s -> %s", source, output)
    try:
        result = runner(command)
    except OSError as exc:
        return _fail(source, folder, config, state, f"exec error: {exc}", logger)

    if getattr(result, "returncode", 1) != 0:
        return _fail(source, folder, config, state, f"kcc-c2e exit {getattr(result, 'returncode', '?')}", logger)

    try:
        os.remove(source)
    except OSError as exc:
        logger.warning("converted %s but could not delete source: %s", source, exc)
    state.set(source, status="done")
    logger.info("done %s", source)
    return True


class Watcher:
    def __init__(
        self,
        config: Config,
        runner: Callable[..., object] = subprocess.run,
        now: Callable[[], float] = time.monotonic,
        logger: logging.Logger = LOG,
    ):
        self.config = config
        self.runner = runner
        self.logger = logger
        self.tracker = StabilityTracker(config.settle_seconds, now=now)
        self.state = StateStore(config.state_file)
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._pending: Set[str] = set()
        self._lock = threading.Lock()
        self._inotify_proc: Optional[subprocess.Popen] = None

    def scan_once(self) -> List[Tuple[str, Folder]]:
        ready: List[Tuple[str, Folder]] = []
        existing: Set[str] = set()
        for folder in self.config.folders:
            try:
                entries = list(os.scandir(folder.path))
            except (FileNotFoundError, NotADirectoryError):
                continue
            except OSError as exc:
                self.logger.warning("cannot scan %s: %s", folder.path, exc)
                continue
            for entry in entries:
                try:
                    if not entry.is_file():
                        continue
                except OSError:
                    continue
                if not is_candidate(entry.name, self.config.extensions):
                    continue
                path = entry.path
                existing.add(path)
                try:
                    stat = entry.stat()
                except OSError:
                    continue
                if self.tracker.is_stable(path, stat.st_size, stat.st_mtime):
                    ready.append((path, folder))
        self.tracker.prune(existing)
        self.state.prune(existing)
        return ready

    def _process(self, path: str, folder: Folder) -> None:
        try:
            handle_file(path, folder, self.config, self.state, runner=self.runner, logger=self.logger)
        finally:
            self.state.save()

    def run(self) -> None:
        self.state.load()
        if self.config.use_inotify:
            self._start_inotify()
        self.logger.info(
            "watching %s (settle=%ss, poll=%ss)",
            ", ".join(folder.path for folder in self.config.folders),
            self.config.settle_seconds,
            self.config.poll_seconds,
        )
        try:
            with ThreadPoolExecutor(max_workers=self.config.concurrency) as pool:
                futures = {}
                while not self._stop.is_set():
                    for path, folder in self.scan_once():
                        with self._lock:
                            if path in self._pending:
                                continue
                            self._pending.add(path)
                        futures[pool.submit(self._process, path, folder)] = path
                    for future in [f for f in futures if f.done()]:
                        path = futures.pop(future)
                        with self._lock:
                            self._pending.discard(path)
                        try:
                            future.result()
                        except Exception as exc:  # pragma: no cover - defensive
                            self.logger.exception("worker error for %s: %s", path, exc)
                    self._wake.wait(self.config.poll_seconds)
                    self._wake.clear()
        finally:
            self.stop()
            self._stop_inotify()

    def stop(self) -> None:
        self._stop.set()
        self._wake.set()

    def _start_inotify(self) -> None:
        dirs = [folder.path for folder in self.config.folders if os.path.isdir(folder.path)]
        if not dirs:
            return
        try:
            self._inotify_proc = subprocess.Popen(
                inotify_command(self.config),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
        except (FileNotFoundError, OSError) as exc:
            self.logger.info("inotify unavailable (%s); using polling only", exc)
            self._inotify_proc = None
            return
        self.logger.info("inotify enabled")
        threading.Thread(target=self._inotify_loop, name="inotify", daemon=True).start()

    def _inotify_loop(self) -> None:
        proc = self._inotify_proc
        if proc is None or proc.stdout is None:
            return
        try:
            for _line in proc.stdout:
                self._wake.set()
                if self._stop.is_set():
                    break
        except (OSError, ValueError):  # pragma: no cover - defensive
            pass

    def _stop_inotify(self) -> None:
        proc = self._inotify_proc
        if proc is None or proc.poll() is not None:
            return
        try:
            proc.terminate()
            proc.wait(timeout=5)
        except (OSError, subprocess.SubprocessError):  # pragma: no cover - defensive
            try:
                proc.kill()
            except OSError:
                pass


def main(argv: Optional[List[str]] = None) -> int:
    logging.basicConfig(
        level=os.environ.get("KCC_WATCH_LOGLEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    config = load_config()
    if not config.enabled:
        LOG.info("kcc-watch disabled via KCC_WATCH_ENABLED")
        return 0
    watcher = Watcher(config)

    def _handler(signum, _frame):
        LOG.info("received signal %s, shutting down", signum)
        watcher.stop()

    signal.signal(signal.SIGTERM, _handler)
    signal.signal(signal.SIGINT, _handler)
    watcher.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
