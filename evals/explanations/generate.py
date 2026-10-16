#!/usr/bin/env python3
"""Generate an isolated, immutable explanation comparison. No Shelf API/DB writes."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import random
import secrets
import subprocess
import time
import urllib.error
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
COMMON = '''You write Shelf's short reason beneath "Because you loved <seed title>".
The reader profile and recommended book are FIXED for this experiment. Do not select
another book. Use only the supplied book notes for factual claims. These notes are
limited evidence, not complete books. Do not add quotations, awards, plot twists,
or facts not supported by the notes. An empty reason is allowed when no honest
connection can be named. Return JSON with exactly one string field: reason.
The same 12-word and 120-character display limits apply to both prompt versions.
'''
SCHEMA = {"type": "object", "properties": {"reason": {"type": "string"}},
          "required": ["reason"], "additionalProperties": False}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, data):
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    temp.replace(path)


def checks(reason):
    return {"word_limit": len(reason.split()) <= 12,
            "character_limit": len(reason) <= 120,
            "single_line": "\n" not in reason,
            "abstained": not reason.strip()}


def prompt_for(case, instruction):
    context = {"reader": case["reader"], "seed": {k: case["seed"][k] for k in ("title", "author", "notes")},
               "recommendation": {k: case["recommendation"][k] for k in ("title", "author", "notes")}}
    return COMMON + "\nINSTRUCTION\n" + instruction + "\nFIXED CONTEXT\n" + json.dumps(context, ensure_ascii=False)


def draw(key, model, case, variant, instruction):
    prompt = prompt_for(case, instruction)
    payload = {"model": model, "max_tokens": 2048, "messages": [{"role": "user", "content": prompt}],
               "output_config": {"effort": "medium", "format": {"type": "json_schema", "schema": SCHEMA}}}
    request = urllib.request.Request("https://api.anthropic.com/v1/messages", data=json.dumps(payload).encode(),
        headers={"x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"}, method="POST")
    start = time.monotonic()
    # No automatic retries or quality-based regeneration: preserve first draws.
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            result = json.load(response)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"Generation failed with HTTP {exc.code}; no retry made.") from None
    raw = "".join(b.get("text", "") for b in result.get("content", []) if b.get("type") == "text")
    try:
        parsed = json.loads(raw)
        if set(parsed) != {"reason"} or not isinstance(parsed["reason"], str):
            raise ValueError()
        reason = parsed["reason"]
    except (ValueError, TypeError):
        reason = None
    return {"case_id": case["id"], "variant": variant, "reason": reason, "raw_text": raw,
            "stop_reason": result.get("stop_reason"), "actual_model": result.get("model"),
            "usage": result.get("usage"), "seconds": round(time.monotonic() - start, 2),
            "prompt_sha256": digest(prompt.encode()), "checks": checks(reason) if reason is not None else {"valid_json": False}}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model", default="claude-opus-5-5")
    p.add_argument("--run", default="round-01")
    p.add_argument("--split", choices=["development", "holdout"], default="development")
    p.add_argument("--release-holdout", action="store_true", help="Explicitly spend the reserved final-check cases")
    p.add_argument("--workers", type=int, choices=[1, 2, 3], default=2)
    args = p.parse_args()
    if not args.run.replace("-", "").replace("_", "").isalnum():
        p.error("Use letters, digits, dashes and underscores for the run name.")
    if args.split == "holdout" and not args.release_holdout:
        p.error("Holdout cases are reserved. Use --release-holdout only for a final check.")
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        p.error("ANTHROPIC_API_KEY is required; never put a key in this repository.")
    target = HERE / "runs" / args.run
    target.mkdir(parents=True, exist_ok=False)
    raw_dataset = (HERE / "cases.json").read_bytes()
    dataset = json.loads(raw_dataset)
    cases = [c for c in dataset["cases"] if c["split"] == args.split]
    prompts = {v: (HERE / (v + ".txt")).read_text() for v in ("baseline", "candidate")}
    seed = secrets.randbits(64)
    rng = random.Random(seed)
    sides = ["baseline"] * (len(cases) // 2) + ["candidate"] * (len(cases) - len(cases) // 2)
    rng.shuffle(sides)
    assignments = {c["id"]: {"A": side, "B": "candidate" if side == "baseline" else "baseline"} for c, side in zip(cases, sides)}
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    manifest = {"schema_version": 1, "run_id": args.run, "dataset_id": dataset["dataset_id"],
                "dataset_sha256": digest(raw_dataset), "source_revision": revision,
                "created_at": datetime.now(timezone.utc).isoformat(), "split": args.split,
                "requested_model": args.model, "effort": "medium", "max_output_tokens_per_call": 2048,
                "max_calls": len(cases) * 2, "random_seed": seed, "assignments": assignments,
                "prompts": prompts, "common_prompt": COMMON, "cases": cases, "outputs": [], "status": "generating"}
    write_json(target / "manifest.json", manifest)
    jobs = [(c, v) for c in cases for v in prompts]
    rng.shuffle(jobs)
    try:
        # executor.map preserves job order; results never get cherry-picked.
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            for output in pool.map(lambda cv: draw(key, args.model, cv[0], cv[1], prompts[cv[1]]), jobs):
                manifest["outputs"].append(output)
                write_json(target / "manifest.json", manifest)
                print(f"Generated {len(manifest['outputs'])}/{len(jobs)}", flush=True)
        if any(o["reason"] is None or o["stop_reason"] != "end_turn" for o in manifest["outputs"]):
            raise RuntimeError("A first draw was incomplete; retained as evidence. This run cannot be served.")
        manifest["status"] = "ready"
    except Exception:
        manifest["status"] = "failed"
        write_json(target / "manifest.json", manifest)
        raise
    write_json(target / "manifest.json", manifest)
    print("Comparison ready. Human judgments have not been collected.")


if __name__ == "__main__":
    main()
