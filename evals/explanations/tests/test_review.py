"""Contract tests for blinding, label integrity, persistence and holdout isolation."""
import copy
import csv
from http.server import ThreadingHTTPServer
import io
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
from generate import checks, prompt_for
from serve import Review, handler_for


def fixture():
    book = {"title": "Fixture book", "author": "Fixture author", "notes": "Test notes.", "source_url": "https://example.org/book"}
    cases = [{"id": cid, "reader": "Fictional test reader", "scenario": "Test only", "seed": book,
              "recommendation": book, "split": "development"} for cid in ("d01", "d02")]
    return {"status": "ready", "run_id": "test", "dataset_sha256": "test-hash", "cases": cases,
            "split": "development", "prompts": {"baseline": "BASELINE PRIVATE", "candidate": "CANDIDATE PRIVATE"},
            "assignments": {"d01": {"A": "baseline", "B": "candidate"}, "d02": {"A": "candidate", "B": "baseline"}},
            "outputs": [{"case_id": c["id"], "variant": v, "reason": f"{c['id']} {v} test sentence"} for c in cases for v in ("baseline", "candidate")]}


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        (self.directory / "manifest.json").write_text(json.dumps(fixture()))
        self.review = Review(self.directory)

    def tearDown(self):
        self.temp.cleanup()

    def save(self, case_id="d01", choice="A", **kwargs):
        return self.review.save({"case_id": case_id, "choice": choice, **kwargs})

    def test_public_payload_and_results_hide_assignment_prompts_and_holdout(self):
        public = self.review.public()
        self.assertNotIn("assignments", public)
        self.assertNotIn("prompts", public)
        self.assertNotIn("coverage_tag", public["cases"][0])
        self.assertNotIn("variant", public["cases"][0])
        self.assertEqual(public["cases"][0]["options"]["A"], "d01 baseline test sentence")
        self.assertIsNone(self.review.results()["totals"])
        self.assertIsNone(self.review.results()["prompts"])
        with self.assertRaises(ValueError): self.review.reveal()

    def test_saved_labels_survive_restart_and_can_be_corrected_before_reveal(self):
        self.save(note="Specific and accurate", criteria=["accuracy", "specificity"], confidence="confident")
        restored = Review(self.directory)
        self.assertEqual(restored.state["judgments"]["d01"]["note"], "Specific and accurate")
        restored.save({"case_id": "d01", "choice": "neither", "note": "Changed my mind"})
        self.assertEqual(Review(self.directory).state["judgments"]["d01"]["choice"], "neither")

    def test_counterbalancing_maps_both_positions_to_the_right_version(self):
        self.save("d01", "A")
        self.save("d02", "B")
        result = self.review.reveal()
        self.assertEqual(result["totals"]["baseline"], 2)
        self.assertEqual(result["totals"]["candidate"], 0)
        with self.assertRaises(ValueError): self.save("d01", "B")
        self.assertTrue(Review(self.directory).state["revealed_at"])

    def test_ties_rejections_and_uncertainty_remain_distinct(self):
        self.save("d01", "neither")
        self.save("d02", "unsure")
        result = self.review.reveal()
        self.assertEqual(result["totals"]["neither"], 1)
        self.assertEqual(result["totals"]["unsure"], 1)
        self.assertEqual(result["totals"]["tie"], 0)

    def test_invalid_labels_and_holdout_cannot_enter_this_round(self):
        for value in ({"case_id":"h01","choice":"A"}, {"case_id":"d01","choice":"baseline"},
                      {"case_id":"d01","choice":"A","criteria":["made-up"]},
                      {"case_id":"d01","choice":"A","note":"x"*2001}):
            with self.assertRaises(ValueError): self.review.save(value)
        self.assertFalse(self.review.path.exists())

    def test_existing_labels_reject_a_different_dataset(self):
        self.save()
        data = json.loads(self.review.path.read_text()); data["dataset_sha256"] = "another-dataset"
        self.review.path.write_text(json.dumps(data))
        with self.assertRaises(ValueError): Review(self.directory)


class HttpTests(ReviewTests):
    def setUp(self):
        super().setUp()
        self.server = ThreadingHTTPServer(("127.0.0.1",0),handler_for(self.review))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.origin = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()
        super().tearDown()

    def test_raw_manifest_and_dataset_are_never_served(self):
        for path in ("/manifest.json","/cases.json","/../cases.json","/runs/test/manifest.json"):
            with self.assertRaises(urllib.error.HTTPError) as error: urllib.request.urlopen(self.origin+path)
            self.assertEqual(error.exception.code,404)

    def test_cross_origin_writes_are_rejected(self):
        req = urllib.request.Request(self.origin+"/api/judgment",data=b'{"case_id":"d01","choice":"A"}',
            headers={"Origin":"https://unrelated.example","X-Review-Token":self.review.token})
        with self.assertRaises(urllib.error.HTTPError) as error: urllib.request.urlopen(req)
        self.assertEqual(error.exception.code,403)
        self.assertFalse(self.review.path.exists())

    def test_real_save_export_and_formula_escaping(self):
        value={"case_id":"d01","choice":"A","note":"=example, with comma\nand newline"}
        req=urllib.request.Request(self.origin+"/api/judgment",data=json.dumps(value).encode(),
            headers={"Origin":self.origin,"X-Review-Token":self.review.token})
        with urllib.request.urlopen(req) as response: self.assertEqual(response.status,200)
        with urllib.request.urlopen(self.origin+"/api/export.csv") as response: rows=list(csv.DictReader(io.StringIO(response.read().decode())))
        self.assertEqual(rows[0]["note"],"'=example, with comma\nand newline")
        self.assertEqual(rows[0]["preferred_variant"],"")


class DatasetTests(unittest.TestCase):
    def test_fixed_split_unique_cases_and_separate_books(self):
        data=json.loads((HERE/"cases.json").read_text()); cases=data["cases"]
        dev=[c for c in cases if c["split"]=="development"]; held=[c for c in cases if c["split"]=="holdout"]
        self.assertEqual((len(dev),len(held),len({c['id'] for c in cases})),(10,5,15))
        titles=lambda group:{c[k]["title"] for c in group for k in ("seed","recommendation")}
        self.assertFalse(titles(dev)&titles(held))
        for c in cases:
            for k in ("seed","recommendation"):
                self.assertTrue(c[k]["source_url"].startswith("https://")); self.assertTrue(c[k]["notes"])

    def test_same_context_and_limits_for_both_prompts(self):
        c=json.loads((HERE/"cases.json").read_text())["cases"][0]
        baseline=(HERE/"baseline.txt").read_text(); candidate=(HERE/"candidate.txt").read_text()
        self.assertTrue(candidate.startswith(baseline.rstrip()))
        self.assertEqual(prompt_for(c,baseline).split("FIXED CONTEXT\n")[1],prompt_for(c,candidate).split("FIXED CONTEXT\n")[1])
        self.assertFalse(checks("word "*13)["word_limit"])
        self.assertFalse(checks("x"*121)["character_limit"])
        self.assertTrue(checks("")["abstained"])


if __name__=="__main__": unittest.main()
