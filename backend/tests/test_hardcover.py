from copy import deepcopy
from datetime import datetime, timedelta, timezone
import importlib
import json
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import httpx
from hardcover import RatingService, identity, load_mappings, public_rating, verified_match

NOW = datetime(2026, 10, 16, 20, tzinfo=timezone.utc)


def book(**overrides):
    return dict(id=1, title="Lessons in Chemistry", slug="lessons-in-chemistry",
                rating=4.1, ratings_count=1304, book_status_id=1, canonical_id=None,
                is_partial_book=False, contributions=[{"author": {"name": "Bonnie Garmus"}}], **overrides)


class Cache:
    def __init__(self):
        self.docs = {}

    def collection(self, name):
        assert name == "book_rating_cache"
        return self

    def document(self, key):
        return SimpleNamespace(get=lambda **kw: SimpleNamespace(to_dict=lambda: deepcopy(self.docs.get(key))),
                               set=lambda value, **kw: self.docs.__setitem__(key, deepcopy(value)))


class RatingTests(unittest.TestCase):
    def service(self, responses, mappings=None):
        self.calls = []
        def handler(request):
            self.calls.append(json.loads(request.content))
            result = responses.pop(0)
            if isinstance(result, Exception):
                raise result
            if isinstance(result, int):
                return httpx.Response(result, json={"error": "unavailable"})
            return httpx.Response(200, json={"data": result})
        return RatingService(Cache(), "test-token", mappings=mappings or {}, clock=lambda: NOW,
                             client_factory=lambda: httpx.Client(transport=httpx.MockTransport(handler)))

    def search_result(self, ids=(1,)):
        return {"search": {"results": {"hits": [{"document": {"id": str(i)}} for i in ids]}}}

    def test_exact_match_caches_and_keeps_count_private(self):
        service = self.service([self.search_result(), {"books": [book()]}])
        first = service.get("Lessons in Chemistry", "Bonnie Garmus")
        self.assertEqual(first["score"], 4.1)
        self.assertEqual(set(first), {"score", "source", "fetched_at"})
        self.assertEqual(service.get("Lessons in Chemistry", "Bonnie Garmus"), first)
        self.assertEqual(len(self.calls), 2)

    def test_title_or_full_author_mismatch_and_excerpt_are_rejected(self):
        candidate = book()
        for title, author in [("Another Book", "Bonnie Garmus"), ("Lessons in Chemistry", "Jane Garmus"),
                              ("Lessons in Chemistry", "")]:
            self.assertFalse(verified_match(candidate, title, author))
        candidate["title"] += ": Chapters 1-5: Exclusive excerpt"
        self.assertFalse(verified_match(candidate, "Lessons in Chemistry", "Bonnie Garmus"))
        candidate["title"] = "Lessons in Chemistry: A Graphic Novel"
        self.assertFalse(verified_match(candidate, "Lessons in Chemistry", "Bonnie Garmus"))

    def test_duplicates_do_not_choose_most_popular(self):
        duplicate = book(); duplicate["id"] = 2; duplicate["ratings_count"] = 1
        service = self.service([self.search_result((1,2)), {"books": [book(), duplicate]}])
        self.assertIsNone(service.get("Lessons in Chemistry", "Bonnie Garmus"))
        self.assertIsNone(service.get("Lessons in Chemistry", "Bonnie Garmus"))
        self.assertEqual(len(self.calls), 2)

    def test_audited_alias_uses_id_and_revalidates_current_identity(self):
        mapping = {identity("Chemistry", "Bonnie Garmus"): dict(hardcover_id=1,
                   hardcover_title="Lessons in Chemistry", hardcover_authors=["Bonnie Garmus"])}
        service = self.service([{"books": [book()]}], mapping)
        self.assertIsNotNone(service.get("Chemistry", "Bonnie Garmus"))
        self.assertEqual(len(self.calls), 1)
        wrong = book(); wrong["title"] = "An unrelated work"
        service = self.service([{"books": [wrong]}], mapping)
        self.assertIsNone(service.get("Chemistry", "Bonnie Garmus"))

    def test_unresolved_audit_records_are_not_queried(self):
        service = self.service([], {identity("Book", "Author"): {"hardcover_id": None}})
        self.assertIsNone(service.get("Book", "Author"))
        self.assertFalse(self.calls)

    def test_canonical_redirect_and_partial_book(self):
        original = book(); original["canonical_id"] = 2
        canonical = book(); canonical["id"] = 2
        service = self.service([self.search_result(), {"books": [original]}, {"books": [canonical]}])
        self.assertIsNotNone(service.get("Lessons in Chemistry", "Bonnie Garmus"))
        canonical["is_partial_book"] = True
        self.assertFalse(verified_match(canonical, "Lessons in Chemistry", "Bonnie Garmus"))

    def test_rating_threshold_invalid_values_and_staleness(self):
        record = dict(score=4.1, source="Hardcover", ratings_count=100, fetched_at=NOW)
        self.assertIsNotNone(public_rating(record, NOW))
        for changed in [dict(ratings_count=99), dict(ratings_count=True), dict(score=0),
                        dict(score=5.1), dict(score=float('nan')), dict(score=True),
                        dict(fetched_at=NOW-timedelta(days=7)), dict(fetched_at=NOW+timedelta(seconds=1)),
                        dict(fetched_at=NOW.replace(tzinfo=None)), dict(source="Shelf")]:
            self.assertIsNone(public_rating({**record, **changed}, NOW))

    def test_expired_cache_refresh_failure_does_not_serve_stale_data(self):
        service = self.service([self.search_result(), {"books": [book()]}, 503])
        self.assertIsNotNone(service.get("Lessons in Chemistry", "Bonnie Garmus"))
        service.clock = lambda: NOW + timedelta(days=8)
        self.assertIsNone(service.get("Lessons in Chemistry", "Bonnie Garmus"))
        self.assertIsNone(service.get("Lessons in Chemistry", "Bonnie Garmus"))
        self.assertEqual(len(self.calls), 3)

    def test_quota_failure_backs_off_other_books(self):
        service = self.service([429])
        self.assertIsNone(service.get("One", "Writer"))
        self.assertIsNone(service.get("Two", "Writer"))
        self.assertEqual(len(self.calls), 1)

    def test_missing_key_and_storage_failures_are_optional(self):
        service = self.service([]); service.token = ""
        self.assertIsNone(service.get("Book", "Writer"))
        service.token = "test"; service.db = None
        self.assertIsNone(service.get("Book", "Writer"))
        self.assertFalse(self.calls)

    def test_mapping_data_has_no_rating_snapshot_or_isbn_joins(self):
        mappings = load_mappings()
        self.assertEqual(len(mappings), 100)
        self.assertEqual(sum(m["hardcover_id"] is not None for m in mappings.values()), 88)
        for m in mappings.values():
            self.assertNotIn("rating", m)
            self.assertNotIn("isbn_13", m)


class RatingRouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        with patch("google.cloud.firestore.Client", return_value=Cache()), \
             patch.dict("os.environ", {"ANTHROPIC_API_KEY": "test", "HARDCOVER_API_KEY": ""}):
            cls.main = importlib.import_module("main")
        cls.client = TestClient(cls.main.app)

    def test_auth_validation_and_optional_contract(self):
        body = {"title": "Lessons in Chemistry", "author": "Bonnie Garmus"}
        self.assertEqual(self.client.post("/v1/book-rating", json=body).status_code, 401)
        headers = {"Authorization": "Bearer ratings-test"}
        self.assertEqual(self.client.post("/v1/book-rating", headers=headers, json=body).json(), {"rating": None})
        self.assertEqual(self.client.post("/v1/book-rating", headers=headers,
                         json={"title":"x"*301, "author":"Writer"}).status_code, 422)
        rating = dict(score=4.1, source="Hardcover", fetched_at=NOW.isoformat())
        with patch.object(self.main.book_ratings, "get", return_value=rating):
            response = self.client.post("/v1/book-rating", headers=headers, json=body)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"rating": rating})


if __name__ == "__main__":
    unittest.main()
