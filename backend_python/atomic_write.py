"""Atomic JSON file writes that survive Windows.

The offline data files are written by dumping to a temp file and renaming it
over the target, so a crash mid-write can never leave truncated JSON behind.
`os.replace` is atomic on both platforms, but on Windows it fails with
PermissionError (WinError 5, "Access is denied") whenever another process holds
the source or the destination open — and a real-time antivirus scanner opens
every file the moment it is created. A burst of writes to the same path is
therefore a lottery: one unlucky replace fails the whole request.

Two defences here:

  * the temp file carries the writing process's pid, so two processes working
    on the same mock_data directory (the API server and a testing_*.py script,
    say) can never fight over one temp path;
  * a refused replace is retried for about a second, because the scanner's
    handle is transient — it lets go as soon as it has read the file.

Callers should still avoid rewriting the same file hundreds of times in a row
(see the deferred flush in mock_firestore); retrying is the safety net, not
the licence.
"""

import json
import os
import time

# ~1s of retries in total, which is far longer than a scanner holds a file.
_ATTEMPTS = 20
_BACKOFF_SECONDS = 0.05


def _temp_path(path):
    return f"{path}.{os.getpid()}.tmp"


def replace_atomically(tmp, path):
    """Renames tmp over path, retrying while Windows says access is denied."""
    for attempt in range(_ATTEMPTS):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            # Last attempt: drop the temp file rather than leaving litter
            # behind, and let the caller see the real error.
            if attempt == _ATTEMPTS - 1:
                try:
                    os.remove(tmp)
                except OSError:
                    pass
                raise
            time.sleep(_BACKOFF_SECONDS)


def write_json(path, payload, **dump_kwargs):
    """Writes payload to path as JSON, atomically."""
    dump_kwargs.setdefault("indent", 2)
    dump_kwargs.setdefault("ensure_ascii", False)
    tmp = _temp_path(path)
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, **dump_kwargs)
    replace_atomically(tmp, path)
