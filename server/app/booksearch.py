"""Book search on Open Library, done here so the rules can change without an app
release. The app sends only the typed text and falls back to calling Open Library
itself when this server cannot answer (see docs/backend.md, "Book search").
"""

import json
import re
import threading
import time
import urllib.parse
import urllib.request

CATALOGUE = "https://openlibrary.org/search.json"
_AGENT = "ReadingLibraryServer/0.1 (+https://ai.duk-tech.com/books-api/)"
_FIELDS = "title,author_name,number_of_pages_median,language,cover_i,first_publish_year"
_RESPONSE_LIMIT = 2 * 1024 * 1024

# Words that appear in most titles. In an any-word query one of them matches
# nearly the whole catalogue, and Open Library answers with a 500 after about
# ten seconds, so "frieda the coworker" found nothing at all.
STOP_WORDS = frozenset(
    "the and for from with into are was not "
    "din cel cea cei cele pentru sau despre una "
    "les des une der die das und del los las".split()
)

LANGUAGES = {
    "eng": "English", "fre": "French", "ger": "German", "spa": "Spanish",
    "ita": "Italian", "rum": "Romanian", "por": "Portuguese", "dut": "Dutch",
    "rus": "Russian", "pol": "Polish", "lat": "Latin", "jpn": "Japanese",
    "chi": "Chinese", "swe": "Swedish", "dan": "Danish", "nor": "Norwegian",
    "fin": "Finnish", "hun": "Hungarian", "cze": "Czech", "gre": "Greek",
    "tur": "Turkish", "ara": "Arabic", "heb": "Hebrew", "kor": "Korean",
    "hin": "Hindi",
}  # fmt: skip


class CatalogueUnavailable(Exception):
    pass


def fetch(params: dict[str, str]) -> dict:
    """One request to Open Library. Replaced in tests."""
    url = f"{CATALOGUE}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": _AGENT})
    with urllib.request.urlopen(request, timeout=12) as response:
        body = response.read(_RESPONSE_LIMIT + 1)
    if len(body) > _RESPONSE_LIMIT:
        raise ValueError("Response too large")
    return json.loads(body)


def isbn_from(text: str) -> str | None:
    compact = re.sub(r"[\s-]", "", text)
    if re.fullmatch(r"\d{13}|\d{9}[\dXx]", compact):
        return compact.upper()
    return None


def _book(doc) -> dict | None:
    if not isinstance(doc, dict):
        return None
    title = doc.get("title")
    if not isinstance(title, str) or not title.strip():
        return None
    authors = doc.get("author_name")
    names = [a for a in authors if isinstance(a, str)][:3] if isinstance(authors, list) else []
    pages = doc.get("number_of_pages_median")
    year = doc.get("first_publish_year")
    cover = doc.get("cover_i")
    languages = doc.get("language")
    return {
        "title": title.strip(),
        "author": ", ".join(names),
        "page_count": round(pages) if isinstance(pages, (int, float)) and pages > 0 else None,
        "first_publish_year": year if isinstance(year, int) else None,
        # A work's language list covers every edition; only one entry is
        # unambiguous enough to prefill.
        "language": LANGUAGES.get(languages[0])
        if isinstance(languages, list) and len(languages) == 1
        else None,
        "cover_id": cover if isinstance(cover, int) and cover > 0 else None,
    }


def _query(q: str, limit: int) -> list[dict]:
    data = fetch({"q": q, "limit": str(limit), "fields": _FIELDS})
    docs = data.get("docs") if isinstance(data, dict) else None
    if not isinstance(docs, list):
        raise ValueError("Unexpected response")
    return [b for b in map(_book, docs) if b is not None]


def search(text: str) -> dict:
    """Exact search first; if a multi-word query matches nothing, an any-word
    retry labelled `approximate`. Raises CatalogueUnavailable only when the exact
    search fails: the retry is a bonus and never turns "no match" into an error."""
    text = text.strip()
    isbn = isbn_from(text)
    try:
        exact = _query(f"isbn:{isbn}" if isbn else text, 15)
    except Exception as e:  # network, timeout, status, parse: all "unavailable"
        raise CatalogueUnavailable() from e
    if exact or isbn:
        return {"approximate": False, "books": exact}
    words = [
        w
        for w in re.split(r"[\W_]+", text)
        if len(w) >= 3 and w.lower() not in STOP_WORDS
    ]
    if len(words) < 2:
        return {"approximate": False, "books": exact}
    try:
        loose = _query(" OR ".join(words), 10)
    except Exception:
        return {"approximate": False, "books": exact}
    return {"approximate": bool(loose), "books": loose}


class _Cache:
    """Recent answers, in memory only (never on disk), so a popular title is not
    fetched again for every reader. Failures are not cached."""

    def __init__(self, ttl_seconds: int = 6 * 3600, size: int = 500):
        self.ttl, self.size = ttl_seconds, size
        self._items: dict[str, tuple[float, dict]] = {}
        self._lock = threading.Lock()

    @staticmethod
    def key(text: str) -> str:
        return " ".join(text.casefold().split())

    def get(self, text: str) -> dict | None:
        with self._lock:
            hit = self._items.get(self.key(text))
            if hit is None or hit[0] < time.monotonic():
                return None
            return hit[1]

    def put(self, text: str, value: dict) -> None:
        with self._lock:
            if len(self._items) >= self.size:
                now = time.monotonic()
                self._items = {k: v for k, v in self._items.items() if v[0] >= now}
                while len(self._items) >= self.size:
                    self._items.pop(next(iter(self._items)))
            self._items[self.key(text)] = (time.monotonic() + self.ttl, value)

    def clear(self) -> None:
        with self._lock:
            self._items.clear()


cache = _Cache()


def cached_search(text: str) -> dict:
    found = cache.get(text)
    if found is None:
        found = search(text)
        cache.put(text, found)
    return found
