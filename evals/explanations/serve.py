#!/usr/bin/env python3
"""Local review UI. Serves only an explicit run and static UI, never the dataset."""
import argparse
import csv
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import secrets
import threading
from urllib.parse import urlsplit

HERE = Path(__file__).resolve().parent
CHOICES = {"A", "B", "tie", "neither", "unsure"}
CRITERIA = {"accuracy", "specificity", "usefulness"}


def now():
    return datetime.now(timezone.utc).isoformat()


def atomic_json(path, data):
    temp = path.with_suffix(".tmp")
    with temp.open("w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    temp.replace(path)


class Review:
    def __init__(self, run_dir):
        self.directory = Path(run_dir)
        self.manifest = json.loads((self.directory / "manifest.json").read_text())
        if self.manifest["status"] != "ready":
            raise ValueError("Only complete generation runs can be reviewed.")
        self.cases = self.manifest["cases"]
        self.ids = {c["id"] for c in self.cases}
        self.token = secrets.token_urlsafe(24)
        self.lock = threading.RLock()
        self.path = self.directory / "judgments.json"
        self.state = json.loads(self.path.read_text()) if self.path.exists() else {
            "schema_version": 1, "run_id": self.manifest["run_id"],
            "dataset_sha256": self.manifest["dataset_sha256"], "revealed_at": None, "judgments": {}}
        if self.state["run_id"] != self.manifest["run_id"] or self.state["dataset_sha256"] != self.manifest["dataset_sha256"]:
            raise ValueError("Judgments do not belong to this frozen run.")

    def complete(self):
        return self.ids == set(self.state["judgments"])

    def public(self):
        with self.lock:
            outputs = {(o["case_id"], o["variant"]): o["reason"] for o in self.manifest["outputs"]}
            cases = []
            for case in self.cases:
                visible = {k: case[k] for k in ("id", "reader", "scenario", "seed", "recommendation")}
                visible["options"] = {side: outputs[case["id"], variant]
                    for side, variant in self.manifest["assignments"][case["id"]].items()}
                cases.append(visible)
            return {"run_id": self.manifest["run_id"], "dataset_sha256": self.manifest["dataset_sha256"],
                    "cases": cases, "judgments": self.state["judgments"], "revealed_at": self.state["revealed_at"],
                    "complete": self.complete(), "token": self.token, "split": self.manifest["split"]}

    def save(self, value):
        with self.lock:
            if self.state["revealed_at"]:
                raise ValueError("This round is revealed and read-only. Start a new round for fresh judgments.")
            if not isinstance(value, dict) or value.get("case_id") not in self.ids or value.get("choice") not in CHOICES:
                raise ValueError("Choose a valid case and judgment.")
            note, criteria = value.get("note", ""), value.get("criteria", [])
            if not isinstance(note, str) or len(note) > 2000:
                raise ValueError("Notes must be text, at most 2,000 characters.")
            if not isinstance(criteria, list) or any(not isinstance(c, str) or c not in CRITERIA for c in criteria):
                raise ValueError("Unknown evaluation criterion.")
            if value.get("confidence", "unsure") not in {"confident", "unsure"}:
                raise ValueError("Choose a valid confidence level.")
            record = {"case_id": value["case_id"], "choice": value["choice"], "note": note.strip(),
                      "criteria": sorted(set(criteria)), "confidence": value.get("confidence", "unsure"),
                      "saved_at": now(), "blind": True}
            updated = dict(self.state["judgments"])
            updated[record["case_id"]] = record
            next_state = {**self.state, "judgments": updated}
            atomic_json(self.path, next_state)
            self.state = next_state
            return record

    def reveal(self):
        with self.lock:
            if not self.complete():
                raise ValueError("Finish or mark uncertainty on every case before revealing versions.")
            if not self.state["revealed_at"]:
                state = {**self.state, "revealed_at": now()}
                atomic_json(self.path, state)
                self.state = state
            return self.results()

    def results(self):
        with self.lock:
            revealed = bool(self.state["revealed_at"])
            totals = {k: 0 for k in ("baseline", "candidate", "tie", "neither", "unsure")} if revealed else None
            rows = []
            for case in self.cases:
                judgment = self.state["judgments"].get(case["id"])
                row = {"case_id": case["id"], "seed": case["seed"]["title"],
                       "recommendation": case["recommendation"]["title"], "judgment": judgment}
                if revealed:
                    row["assignment"] = self.manifest["assignments"][case["id"]]
                    winner = row["assignment"].get(judgment["choice"], judgment["choice"])
                    row["preferred_variant"] = winner
                    totals[winner] += 1
                rows.append(row)
            return {"rows": rows, "totals": totals, "complete": self.complete(), "revealed_at": self.state["revealed_at"],
                    "prompts": self.manifest["prompts"] if revealed else None}


def handler_for(review):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def send(self, value, status=200, kind="application/json; charset=utf-8", filename=None):
            data = json.dumps(value, ensure_ascii=False).encode() if kind.startswith("application/json") else value
            self.send_response(status)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
            if filename:
                self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
            self.end_headers()
            self.wfile.write(data)

        def allowed_host(self):
            port = self.server.server_port
            return self.headers.get("Host") in {f"localhost:{port}", f"127.0.0.1:{port}"}

        def do_GET(self):
            if not self.allowed_host():
                return self.send({"error": "Local access only."}, 403)
            path = urlsplit(self.path).path
            assets = {"/": ("index.html", "text/html; charset=utf-8"),
                      "/app.js": ("app.js", "text/javascript; charset=utf-8"),
                      "/style.css": ("style.css", "text/css; charset=utf-8")}
            if path in assets:
                file, kind = assets[path]
                return self.send((HERE / "web" / file).read_bytes(), kind=kind)
            if path == "/api/session":
                return self.send(review.public())
            if path == "/api/results":
                return self.send(review.results())
            if path == "/health":
                return self.send({"ok": True, "run_id": review.manifest["run_id"]})
            if path == "/api/export.json":
                public = review.public()
                public.pop("token")
                public["results"] = review.results()
                return self.send(public, filename="shelf-explanation-review.json")
            if path == "/api/export.csv":
                stream = io.StringIO()
                writer = csv.writer(stream)
                writer.writerow(["case_id", "seed", "recommendation", "choice", "preferred_variant", "criteria", "confidence", "note"])
                for row in review.results()["rows"]:
                    j = row["judgment"] or {}
                    # Avoid formula execution if reviewer notes are opened in a spreadsheet.
                    cells = [row["case_id"], row["seed"], row["recommendation"], j.get("choice", ""), row.get("preferred_variant", ""), "; ".join(j.get("criteria", [])), j.get("confidence", ""), j.get("note", "")]
                    writer.writerow(["'" + c if c.startswith(("=", "+", "-", "@", "\t", "\r")) else c for c in cells])
                return self.send(stream.getvalue().encode(), kind="text/csv; charset=utf-8", filename="shelf-explanation-review.csv")
            return self.send({"error": "Not found."}, 404)

        def do_POST(self):
            port = self.server.server_port
            if (not self.allowed_host() or self.headers.get("Origin") not in {f"http://localhost:{port}", f"http://127.0.0.1:{port}"}
                    or self.headers.get("X-Review-Token") != review.token):
                return self.send({"error": "Reload this local review page to continue."}, 403)
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length <= 0 or length > 12000:
                    raise ValueError("Invalid request size.")
                value = json.loads(self.rfile.read(length))
                if self.path == "/api/judgment":
                    return self.send(review.save(value))
                if self.path == "/api/reveal":
                    return self.send(review.reveal())
                return self.send({"error": "Not found."}, 404)
            except (ValueError, KeyError, TypeError) as exc:
                return self.send({"error": str(exc)}, 400)
            except OSError:
                return self.send({"error": "Could not save to disk. Your draft is retained in this browser; retry after checking the server."}, 500)
    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", default=str(HERE / "runs" / "round-01"), type=Path)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(Review(args.run)))
    print(f"Shelf review ready at http://127.0.0.1:{server.server_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()


if __name__ == "__main__":
    main()
