# calibre-web-docker-build

Auto build docker images based on changes to personal calibre-web container.

Image: `ghcr.io/nigeldixon/calibre-web:nightly`

## Automatic KCC conversion (kcc-watch)

The container watches the comic/manga drop folders and runs `kcc-c2e` on any
archive that finishes being written, dropping the converted output into
`/calibredrop` and deleting the source on success. Files that fail
`fail_threshold` times (default 3) are moved to `<drop folder>/.failed/`.

Completion is detected by a polling stability scanner, which works on local
disks, bind mounts, NFS and CIFS. When `inotifywait` is available it is used
only to shorten the latency of local drops.

### Defaults

| Setting | Default | Description |
| --- | --- | --- |
| `KCC_WATCH_ENABLED` | `true` | Enable the watcher |
| `KCC_WATCH_POLL` | `10` | Seconds between scans |
| `KCC_WATCH_SETTLE` | `60` | Seconds a file must be unchanged before conversion |
| `KCC_WATCH_EXTENSIONS` | `cbz, cbr, cb7, cbt, zip, rar, 7z, pdf` | Archive types to process |
| `KCC_WATCH_OUTPUT` | `/calibredrop` | Output directory |
| `KCC_WATCH_CONCURRENCY` | `1` | Parallel conversions |
| `KCC_WATCH_USE_INOTIFY` | `true` | Use `inotifywait` to shorten latency |
| `KCC_WATCH_FAIL_THRESHOLD` | `3` | Failures before moving to `.failed/` |
| `KCC_WATCH_STATE` | `/config/kcc-watch-state.json` | Persisted state |

Drop folders default to `comics` → `/c2e_comics` and `manga` → `/c2e_manga`.

### Configuration file

Global settings and per-folder overrides can be set in `/config/kcc-watch.ini`:

```ini
[kcc-watch]
settle_seconds = 60
output = /calibredrop

[comics]
path = /c2e_comics
options = -p K1 -m

[manga]
path = /c2e_manga
options = -p K1 -m --manga-style
output = /calibredrop/manga
```

`options` are passed through to `kcc-c2e`. Precedence is
**environment variables > ini file > defaults**.

### Per-folder environment overrides

For each folder section `NAME`, `C2E_NAME_OPTIONS` and `C2E_NAME_OUTPUT`
override its `options`/`output` (e.g. `C2E_MANGA_OPTIONS`, `C2E_COMICS_OUTPUT`).

### Running kcc-watch standalone

```sh
KCC_WATCH_CONFIG=/config/kcc-watch.ini python3 scripts/kcc_watch.py
```

## Tests

```sh
python3 -m unittest discover -s tests -t . -v
```
