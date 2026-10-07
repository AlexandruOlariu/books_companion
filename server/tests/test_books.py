import pytest
from sqlalchemy import text

from app import booksearch
from app.db import get_engine


@pytest.fixture(autouse=True)
def catalogue(monkeypatch):
    """A fake Open Library: `answers` maps a query to its docs (or an exception)."""
    booksearch.cache.clear()
    fake = {"answers": {}, "asked": []}

    def fetch(params):
        fake["asked"].append(params["q"])
        answer = fake["answers"].get(params["q"], [])
        if isinstance(answer, Exception):
            raise answer
        return {"docs": answer}

    monkeypatch.setattr(booksearch, "fetch", fetch)
    yield fake
    booksearch.cache.clear()


COWORKER = {
    "title": "The Coworker",
    "author_name": ["Freida McFadden"],
    "number_of_pages_median": 344.4,
    "language": ["eng"],
    "cover_i": 15125038,
    "first_publish_year": 2023,
}


def search(client, q):
    return client.post("/books/search", json={"q": q})


def test_search_needs_no_account_and_returns_plain_books(client, catalogue):
    catalogue["answers"]["Freida The Coworker"] = [
        COWORKER,
        {"title": "Multilingual", "language": ["eng", "fre"], "number_of_pages_median": 0},
        {"author_name": ["No title"]},
    ]
    r = search(client, "Freida The Coworker")
    assert r.status_code == 200
    assert r.json() == {
        "approximate": False,
        "books": [
            {
                "title": "The Coworker",
                "author": "Freida McFadden",
                "page_count": 344,
                "first_publish_year": 2023,
                "language": "English",
                "cover_id": 15125038,
            },
            # An ambiguous language and a zero page count are left for the reader.
            {
                "title": "Multilingual",
                "author": "",
                "page_count": None,
                "first_publish_year": None,
                "language": None,
                "cover_id": None,
            },
        ],
    }


def test_isbn_becomes_an_isbn_query_without_retry(client, catalogue):
    assert search(client, "978-0-441-17271-9").json() == {"approximate": False, "books": []}
    assert catalogue["asked"] == ["isbn:9780441172719"]


def test_misspelling_retries_any_word_without_common_words(client, catalogue):
    catalogue["answers"]["Frieda OR Coworker"] = [COWORKER]
    body = search(client, "Frieda The Coworker").json()
    assert body["approximate"] is True
    assert [b["title"] for b in body["books"]] == ["The Coworker"]
    # "The" would match the whole catalogue; Open Library times out on it.
    assert catalogue["asked"] == ["Frieda The Coworker", "Frieda OR Coworker"]


def test_no_retry_for_one_real_word(client, catalogue):
    assert search(client, "the housmaid").json()["books"] == []
    assert catalogue["asked"] == ["the housmaid"]


def test_a_failed_retry_is_not_an_error(client, catalogue):
    catalogue["answers"]["freida OR mcfaden"] = TimeoutError()
    r = search(client, "freida mcfaden")
    assert r.status_code == 200
    assert r.json() == {"approximate": False, "books": []}


def test_an_unreachable_catalogue_is_a_502(client, catalogue):
    catalogue["answers"]["dune"] = OSError("down")
    r = search(client, "dune")
    assert r.status_code == 502
    # Failures are not cached: the next try asks again.
    catalogue["answers"]["dune"] = [{"title": "Dune"}]
    assert search(client, "dune").json()["books"][0]["title"] == "Dune"


def test_answers_are_cached_by_normalised_text(client, catalogue):
    catalogue["answers"]["Dune"] = [{"title": "Dune"}]
    search(client, "Dune")
    search(client, "  dune ")
    assert catalogue["asked"] == ["Dune"]


def test_bad_input_is_rejected(client, catalogue):
    assert search(client, "").status_code == 422
    assert search(client, "   ").status_code == 422
    assert search(client, "x" * 201).status_code == 422
    assert client.post("/books/search", json={"q": "dune", "note": "x"}).status_code == 422
    assert catalogue["asked"] == []


def test_search_text_is_never_stored(client, catalogue):
    search(client, "a private search")
    with get_engine().connect() as conn:
        keys = conn.execute(text("select key from rate_events")).scalars().all()
    assert keys and all("private" not in k for k in keys)


def test_searches_are_rate_limited_per_address(client, catalogue):
    for _ in range(120):
        assert search(client, "dune").status_code == 200
    assert search(client, "dune").status_code == 429
