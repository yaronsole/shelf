import ast
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
import unittest

from community import rank_loves, recently_loved, with_ranks, taste_signals

NOW = datetime(2026, 10, 12, tzinfo=timezone.utc)


def reaction(title="Book", kind="alreadyReadLiked", days=0, **extra):
    return dict(title=title, author="Author", kind=kind,
                created_at=NOW + timedelta(days=days), **extra)


def route(name, **dependencies):
    """Run the real route body with fake storage, without initializing paid clients.

    Decorators/auth injection aren't exercised here; data contracts and user
    scoping inside the handler are. Pure ranking rules are tested directly.
    """
    tree = ast.parse((Path(__file__).parents[1] / "main.py").read_text())
    fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == name)
    fn = deepcopy(fn)
    fn.decorator_list = []
    namespace = dict(UserID=str, with_ranks=with_ranks, recently_loved=recently_loved,
                     COMMUNITY_LIST_SIZE=30, **dependencies)
    exec(compile(ast.Module(body=[fn], type_ignores=[]), "main.py", "exec"), namespace)
    return namespace[name]


class RankingTests(unittest.TestCase):
    def test_repeated_loves_count_once_and_normalize_identity(self):
        result = rank_loves([("a", True, [reaction(), reaction(title=" book ", days=1)]),
                             ("b", True, [reaction()])])
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["loved_count"], 2)

    def test_opt_out_missing_titles_and_other_domains_do_not_vote(self):
        result = rank_loves([("a", False, [reaction()]),
                             ("b", True, [reaction(domain="recipes"), reaction(title=" ")])])
        self.assertEqual(result, [])

    def test_latest_dislike_retracts_love_regardless_of_query_order(self):
        events = [reaction(kind="alreadyReadDisliked", days=1), reaction()]
        self.assertEqual(rank_loves([("a", True, events)]), [])
        self.assertEqual(rank_loves([("a", True, list(reversed(events)))]), [])

    def test_dislike_wins_exact_time_tie(self):
        self.assertEqual(rank_loves([("a", True, [reaction(), reaction(kind="alreadyReadDisliked")])]), [])

    def test_pass_and_save_do_not_erase_reading_sentiment(self):
        result = rank_loves([("a", True, [reaction(), reaction(kind="dismiss", days=1), reaction(kind="save", days=2)])])
        self.assertEqual(result[0]["loved_count"], 1)
        self.assertEqual(result[0]["latest_loved_at"], NOW)

    def test_equal_votes_share_rank_but_recent_view_favors_new_discoveries(self):
        books = rank_loves([("a", True, [reaction("A"), reaction("B"), reaction("C", days=2)]),
                            ("b", True, [reaction("A"), reaction("B")])])
        self.assertEqual([b["rank"] for b in with_ranks(books)], [1, 1, 3])
        self.assertEqual(recently_loved(books)[0]["title"], "C")

    def test_legacy_missing_timestamp_is_not_presented_as_recent(self):
        event = reaction()
        del event["created_at"]
        books = rank_loves([("a", True, [event])])
        self.assertEqual(books[0]["loved_count"], 1)
        self.assertEqual(recently_loved(books), [])

    def test_pass_is_not_a_negative_taste_signal(self):
        self.assertEqual(taste_signals([reaction(kind="dismiss")]), ([], []))

    def test_changed_opinion_is_not_both_positive_and_negative(self):
        loved = reaction()
        disliked = reaction(kind="alreadyReadDisliked", days=1)
        liked, negative = taste_signals([loved, disliked, reaction(kind="save", days=2)])
        self.assertEqual(liked, [])
        self.assertEqual(negative, [disliked])

    def test_removed_taste_influence_retains_community_love(self):
        event = reaction(taste_excluded=True)
        self.assertEqual(taste_signals([event]), ([], []))
        self.assertEqual(rank_loves([("a", True, [event])])[0]["loved_count"], 1)

    def test_prompt_signal_caps_and_domain_isolation(self):
        events = [reaction(str(n)) for n in range(50)] + [reaction("Wrong", domain="recipes")]
        liked, _ = taste_signals(events)
        self.assertEqual(len(liked), 30)
        self.assertNotIn("Wrong", [r["title"] for r in liked])


class RouteTests(unittest.TestCase):
    def leaderboard(self, data):
        snap = SimpleNamespace(exists=bool(data), to_dict=lambda: data)
        return route("community_leaderboard",
                     _community_doc_ref=lambda: SimpleNamespace(get=lambda: snap),
                     _has_valid_cover=lambda url: bool(url and url.strip()),
                     _user_list_status_map=lambda uid, domain: {("a", "author"): "read"})

    def test_global_rank_keeps_read_books_and_filters_missing_covers(self):
        books = [dict(book_id=t, title=t, author="Author", loved_count=count, cover_url=cover)
                 for t, count, cover in [("A", 3, "cover"), ("B", 3, "cover"), ("C", 2, ""), ("D", 1, "cover")]]
        result = self.leaderboard(dict(books=books, updated_at=NOW))("viewer")
        self.assertEqual([b["rank"] for b in result["books"]], [1, 1, 3])
        self.assertEqual(result["books"][0]["user_status"], "read")
        self.assertEqual(result["updated_at"], NOW)

    def test_old_snapshot_does_not_fake_recent_order(self):
        self.assertEqual(self.leaderboard(dict(books=[]))("viewer", order="recent")["books"], [])

    def test_empty_snapshot_is_valid(self):
        result = self.leaderboard(None)("viewer")
        self.assertEqual(result["books"], [])
        self.assertIsNone(result["updated_at"])

    def test_undo_is_scoped_to_authenticated_user(self):
        calls = []
        collection = lambda uid: SimpleNamespace(document=lambda rid: SimpleNamespace(delete=lambda: calls.append((uid, rid))))
        route("delete_reaction", reaction_col=collection)("reaction-1", "reader-1")
        self.assertEqual(calls, [("reader-1", "reaction-1")])


if __name__ == "__main__":
    unittest.main()
