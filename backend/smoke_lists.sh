#!/bin/bash
# Smoke test for /v1/lists endpoints. Requires a locally-running uvicorn:
#   cd ~/Desktop/ShelfApp/backend
#   GCP_PROJECT=shelf-488022 ANTHROPIC_API_KEY=... GOOGLE_BOOKS_API_KEY=... ./run_local.sh
#
# Then in another terminal:
#   ./smoke_lists.sh
set -e

BASE="${BASE:-http://localhost:8080}"
# Test user — burn-after-reading. Any UUID is fine; this isolates state in Firestore.
USER="smoke-test-$(date +%s)"
AUTH="Authorization: Bearer $USER"

pass() { printf "\033[32mPASS\033[0m %s\n" "$1"; }
fail() { printf "\033[31mFAIL\033[0m %s\n" "$1"; exit 1; }

echo "== GET /v1/lists (catalog) =="
CATALOG=$(curl -s "$BASE/v1/lists")
echo "$CATALOG" | python3 -m json.tool > /dev/null || fail "catalog response not valid JSON"
echo "$CATALOG" | grep -q "oprah_book_club" || fail "catalog missing oprah_book_club"
echo "$CATALOG" | grep -q "reese_book_club" || fail "catalog missing reese_book_club"
pass "catalog returned, both lists present"

echo
echo "== GET /v1/lists/oprah_book_club (detail) =="
DETAIL=$(curl -s -H "$AUTH" "$BASE/v1/lists/oprah_book_club")
echo "$DETAIL" | python3 -m json.tool > /dev/null || fail "detail response not valid JSON"
BOOK_COUNT=$(echo "$DETAIL" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['books']))")
[[ "$BOOK_COUNT" -ge 30 ]] || fail "expected >=30 books, got $BOOK_COUNT"
pass "detail returned $BOOK_COUNT books"

FIRST_BOOK=$(echo "$DETAIL" | python3 -c "import sys, json; b=json.load(sys.stdin)['books'][0]; print(b['book_id'], b['title'], b['author'], sep='|')")
FIRST_ID=$(echo "$FIRST_BOOK" | cut -d'|' -f1)
FIRST_TITLE=$(echo "$FIRST_BOOK" | cut -d'|' -f2)
FIRST_AUTHOR=$(echo "$FIRST_BOOK" | cut -d'|' -f3)
echo "First book: $FIRST_TITLE by $FIRST_AUTHOR (id=$FIRST_ID)"

echo
echo "== POST /v1/lists/oprah_book_club/react (read) =="
REACT=$(curl -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"book_id\":\"$FIRST_ID\",\"title\":\"$FIRST_TITLE\",\"author\":\"$FIRST_AUTHOR\",\"kind\":\"read\"}" \
    "$BASE/v1/lists/oprah_book_club/react")
echo "$REACT" | grep -q '"kind":"read"' || fail "react response missing kind=read: $REACT"
pass "marked read"

echo
echo "== Verify status persists on subsequent GET =="
DETAIL2=$(curl -s -H "$AUTH" "$BASE/v1/lists/oprah_book_club")
STATUS=$(echo "$DETAIL2" | FIRST_ID="$FIRST_ID" python3 -c "import sys, json, os; d=json.load(sys.stdin); fid=os.environ['FIRST_ID']; b=next(x for x in d['books'] if x['book_id']==fid); print(b.get('user_status'))")
[[ "$STATUS" == "read" ]] || fail "expected user_status=read, got: $STATUS"
pass "user_status=read persisted"

echo
echo "== Verify the book is now in seed_books =="
SEEDS=$(curl -s -H "$AUTH" "$BASE/v1/seed-books")
echo "$SEEDS" | grep -q "$FIRST_TITLE" || fail "seed list missing $FIRST_TITLE"
pass "book appeared in seed_books (will be in exclusion list)"

echo
echo "== POST /v1/lists/oprah_book_club/react (saved on a different book) =="
SECOND=$(echo "$DETAIL" | python3 -c "import sys, json; b=json.load(sys.stdin)['books'][1]; print(b['book_id'], b['title'], b['author'], sep='|')")
SECOND_ID=$(echo "$SECOND" | cut -d'|' -f1)
SECOND_TITLE=$(echo "$SECOND" | cut -d'|' -f2)
SECOND_AUTHOR=$(echo "$SECOND" | cut -d'|' -f3)
curl -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"book_id\":\"$SECOND_ID\",\"title\":\"$SECOND_TITLE\",\"author\":\"$SECOND_AUTHOR\",\"kind\":\"saved\"}" \
    "$BASE/v1/lists/oprah_book_club/react" > /dev/null
DETAIL3=$(curl -s -H "$AUTH" "$BASE/v1/lists/oprah_book_club")
STATUS2=$(echo "$DETAIL3" | SECOND_ID="$SECOND_ID" python3 -c "import sys, json, os; d=json.load(sys.stdin); fid=os.environ['SECOND_ID']; b=next(x for x in d['books'] if x['book_id']==fid); print(b.get('user_status'))")
[[ "$STATUS2" == "saved" ]] || fail "expected saved status, got: $STATUS2"
pass "saved status applied"

echo
echo "== DELETE /v1/lists/.../react (undo) =="
curl -s -X DELETE -H "$AUTH" "$BASE/v1/lists/oprah_book_club/react/$FIRST_ID" > /dev/null
DETAIL4=$(curl -s -H "$AUTH" "$BASE/v1/lists/oprah_book_club")
STATUS3=$(echo "$DETAIL4" | FIRST_ID="$FIRST_ID" python3 -c "import sys, json, os; d=json.load(sys.stdin); fid=os.environ['FIRST_ID']; b=next(x for x in d['books'] if x['book_id']==fid); print(b.get('user_status'))")
[[ "$STATUS3" == "None" ]] || fail "expected user_status=None after undo, got: $STATUS3"
pass "undo cleared status"

echo
echo "== Bad slug returns 404 =="
CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH" "$BASE/v1/lists/nonexistent")
[[ "$CODE" == "404" ]] || fail "expected 404 for bad slug, got: $CODE"
pass "404 on bad slug"

echo
echo "== Covers populate on at least one book =="
COVER_COUNT=$(echo "$DETAIL" | python3 -c "import sys, json; print(sum(1 for b in json.load(sys.stdin)['books'] if b.get('cover_url')))")
echo "Books with covers: $COVER_COUNT / $BOOK_COUNT"
[[ "$COVER_COUNT" -ge 10 ]] || fail "expected >=10 books with covers, got $COVER_COUNT"
pass "$COVER_COUNT/$BOOK_COUNT books have covers"

echo
printf "\033[32m== ALL SMOKE TESTS PASSED ==\033[0m\n"
echo "Note: Run cleanup_smoke_user.sh later (or accept this user's data lives in Firestore)."
echo "User id: $USER"
