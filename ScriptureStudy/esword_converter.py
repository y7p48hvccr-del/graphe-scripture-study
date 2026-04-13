#!/usr/bin/env python3
"""
esword_converter.py
Converts e-Sword / MySword module files to MyBible SQLite3 format.

Supported input extensions:
  .bblx   e-Sword Bible
  .cmtx   e-Sword Commentary
  .dctx   e-Sword Dictionary
  .lexdbtx e-Sword Lexicon / Strong's
  .topx   e-Sword Topic file
  .resx   e-Sword Reference file
  .devotx e-Sword Devotional
  .mybible MySword Bible (already SQLite, schema differs)

Usage (called by ModuleLibraryView.swift):
  python3 esword_converter.py <source_path> <dest_folder>

Exit 0 = success, non-zero = failure (last line of stdout is the error message).
"""

import sys
import os
import sqlite3
import re
import shutil

# ---------------------------------------------------------------------------
# MyBible book_number mapping  (standard OSIS / MyBible order)
# e-Sword uses the same canonical order (1-66 OT+NT) but stores books
# as sequential integers starting at 1 for Genesis.
# MyBible uses multiples of 10: Gen=10, Exo=20 … Rev=730
# ---------------------------------------------------------------------------
ESWORD_TO_MYBIBLE_BOOK = {
    1: 10, 2: 20, 3: 30, 4: 40, 5: 50,
    6: 60, 7: 70, 8: 80, 9: 90, 10: 100,
    11: 110, 12: 120, 13: 130, 14: 140, 15: 150,
    16: 160, 17: 170, 18: 180, 19: 190, 20: 200,
    21: 210, 22: 220, 23: 230, 24: 240, 25: 250,
    26: 260, 27: 270, 28: 280, 29: 290, 30: 300,
    31: 310, 32: 320, 33: 330, 34: 340, 35: 350,
    36: 360, 37: 370, 38: 380, 39: 390,
    # NT
    40: 470, 41: 480, 42: 490, 43: 500, 44: 510,
    45: 520, 46: 530, 47: 540, 48: 550, 49: 560,
    50: 570, 51: 580, 52: 590, 53: 600, 54: 610,
    55: 620, 56: 630, 57: 640, 58: 650, 59: 660,
    60: 670, 61: 680, 62: 690, 63: 700, 64: 710,
    65: 720, 66: 730,
}

MYBIBLE_BOOK_NAMES = {
    10: ("Gen", "Genesis"), 20: ("Exo", "Exodus"), 30: ("Lev", "Leviticus"),
    40: ("Num", "Numbers"), 50: ("Deu", "Deuteronomy"), 60: ("Jos", "Joshua"),
    70: ("Jdg", "Judges"), 80: ("Rut", "Ruth"), 90: ("1Sa", "1 Samuel"),
    100: ("2Sa", "2 Samuel"), 110: ("1Ki", "1 Kings"), 120: ("2Ki", "2 Kings"),
    130: ("1Ch", "1 Chronicles"), 140: ("2Ch", "2 Chronicles"), 150: ("Ezr", "Ezra"),
    160: ("Neh", "Nehemiah"), 170: ("Est", "Esther"), 180: ("Job", "Job"),
    190: ("Psa", "Psalms"), 200: ("Pro", "Proverbs"), 210: ("Ecc", "Ecclesiastes"),
    220: ("Sng", "Song of Solomon"), 230: ("Isa", "Isaiah"), 240: ("Jer", "Jeremiah"),
    250: ("Lam", "Lamentations"), 260: ("Ezk", "Ezekiel"), 270: ("Dan", "Daniel"),
    280: ("Hos", "Hosea"), 290: ("Jol", "Joel"), 300: ("Amo", "Amos"),
    310: ("Oba", "Obadiah"), 320: ("Jon", "Jonah"), 330: ("Mic", "Micah"),
    340: ("Nah", "Nahum"), 350: ("Hab", "Habakkuk"), 360: ("Zep", "Zephaniah"),
    370: ("Hag", "Haggai"), 380: ("Zec", "Zechariah"), 390: ("Mal", "Malachi"),
    470: ("Mat", "Matthew"), 480: ("Mrk", "Mark"), 490: ("Luk", "Luke"),
    500: ("Jhn", "John"), 510: ("Act", "Acts"), 520: ("Rom", "Romans"),
    530: ("1Co", "1 Corinthians"), 540: ("2Co", "2 Corinthians"), 550: ("Gal", "Galatians"),
    560: ("Eph", "Ephesians"), 570: ("Php", "Philippians"), 580: ("Col", "Colossians"),
    590: ("1Th", "1 Thessalonians"), 600: ("2Th", "2 Thessalonians"), 610: ("1Ti", "1 Timothy"),
    620: ("2Ti", "2 Timothy"), 630: ("Tit", "Titus"), 640: ("Phm", "Philemon"),
    650: ("Heb", "Hebrews"), 660: ("Jas", "James"), 670: ("1Pe", "1 Peter"),
    680: ("2Pe", "2 Peter"), 690: ("1Jo", "1 John"), 700: ("2Jo", "2 John"),
    710: ("3Jo", "3 John"), 720: ("Jud", "Jude"), 730: ("Rev", "Revelation"),
}


def strip_rtf(text):
    """Remove RTF markup from e-Sword text fields."""
    if not text:
        return ""
    # Remove RTF control words and groups
    text = re.sub(r'\\[a-z]+\d*\s?', '', text)
    text = re.sub(r'\{[^}]*\}', '', text)
    text = re.sub(r'[{}\\]', '', text)
    return text.strip()


def strip_html(text):
    """Light HTML strip — keep plain text."""
    if not text:
        return ""
    text = re.sub(r'<[^>]+>', '', text)
    text = text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>').replace('&nbsp;', ' ')
    return text.strip()


def read_esword_info(src_conn):
    """Read Details table from e-Sword db into a dict."""
    info = {}
    try:
        cur = src_conn.execute("SELECT Description, Data FROM Details")
        for row in cur:
            if row[0] and row[1]:
                info[row[0]] = row[1]
    except Exception:
        pass
    return info


def write_mybible_info(dst_conn, description, language="en", extra=None):
    """Create and populate the MyBible info table."""
    dst_conn.execute("CREATE TABLE IF NOT EXISTS info (name TEXT, value TEXT)")
    rows = [
        ("description", description),
        ("language", language),
        ("encoding", "UTF-8"),
        ("created_by", "esword_converter"),
    ]
    if extra:
        rows += list(extra.items())
    dst_conn.executemany("INSERT INTO info (name, value) VALUES (?,?)", rows)


# ---------------------------------------------------------------------------
# Bible conversion  (.bblx / MySword .mybible)
# ---------------------------------------------------------------------------

def convert_bible(src_path, dst_path, ext):
    src = sqlite3.connect(src_path)
    info = read_esword_info(src)
    desc = info.get("Title") or info.get("Abbreviation") or os.path.splitext(os.path.basename(src_path))[0]
    lang = info.get("Language") or "en"

    dst = sqlite3.connect(dst_path)
    write_mybible_info(dst, desc, lang)

    dst.execute("""
        CREATE TABLE verses (
            book_number INTEGER,
            chapter     INTEGER,
            verse       INTEGER,
            text        TEXT,
            PRIMARY KEY (book_number, chapter, verse)
        )
    """)
    dst.execute("""
        CREATE TABLE books (
            book_number INTEGER PRIMARY KEY,
            short_name  TEXT,
            long_name   TEXT,
            book_color  TEXT
        )
    """)

    if ext == ".mybible":
        # MySword schema: verses(Book, Chapter, Verse, Scripture)
        rows = src.execute("SELECT Book, Chapter, Verse, Scripture FROM verses ORDER BY Book, Chapter, Verse")
    else:
        # e-Sword schema: Bible(Book, Chapter, Verse, Scripture)
        rows = src.execute("SELECT Book, Chapter, Verse, Scripture FROM Bible ORDER BY Book, Chapter, Verse")

    books_seen = set()
    verse_rows = []
    for book_es, chap, verse, text in rows:
        mb_book = ESWORD_TO_MYBIBLE_BOOK.get(book_es)
        if mb_book is None:
            continue
        clean = strip_rtf(text or "")
        verse_rows.append((mb_book, chap, verse, clean))
        books_seen.add(mb_book)

    dst.executemany("INSERT OR REPLACE INTO verses VALUES (?,?,?,?)", verse_rows)

    book_rows = []
    for mb_book in sorted(books_seen):
        short, long = MYBIBLE_BOOK_NAMES.get(mb_book, (str(mb_book), str(mb_book)))
        book_rows.append((mb_book, short, long, ""))
    dst.executemany("INSERT OR REPLACE INTO books VALUES (?,?,?,?)", book_rows)

    dst.commit()
    src.close()
    dst.close()
    print(f"Converted Bible: {desc} ({len(verse_rows)} verses)")


# ---------------------------------------------------------------------------
# Commentary conversion  (.cmtx)
# ---------------------------------------------------------------------------

def convert_commentary(src_path, dst_path):
    src = sqlite3.connect(src_path)
    info = read_esword_info(src)
    desc = info.get("Title") or os.path.splitext(os.path.basename(src_path))[0]
    lang = info.get("Language") or "en"

    dst = sqlite3.connect(dst_path)
    write_mybible_info(dst, desc, lang)

    dst.execute("""
        CREATE TABLE commentaries (
            book_number        INTEGER,
            chapter_number_from INTEGER,
            verse_number_from   INTEGER,
            chapter_number_to   INTEGER,
            verse_number_to     INTEGER,
            marker             TEXT,
            text               TEXT
        )
    """)

    # e-Sword Commentary: Commentary(Book, Chapter, Verse, Header, Body)
    rows = src.execute("SELECT Book, Chapter, Verse, Header, Body FROM Commentary ORDER BY Book, Chapter, Verse")
    out = []
    for book_es, chap, verse, header, body in rows:
        mb_book = ESWORD_TO_MYBIBLE_BOOK.get(book_es)
        if mb_book is None:
            continue
        text = strip_rtf(body or "")
        out.append((mb_book, chap, verse, chap, verse, header or "", text))

    dst.executemany("INSERT INTO commentaries VALUES (?,?,?,?,?,?,?)", out)
    dst.commit()
    src.close()
    dst.close()
    print(f"Converted Commentary: {desc} ({len(out)} entries)")


# ---------------------------------------------------------------------------
# Dictionary / Lexicon / Strong's conversion  (.dctx / .lexdbtx)
# ---------------------------------------------------------------------------

def convert_dictionary(src_path, dst_path, is_strongs=False):
    src = sqlite3.connect(src_path)
    info = read_esword_info(src)
    desc = info.get("Title") or os.path.splitext(os.path.basename(src_path))[0]
    lang = info.get("Language") or "en"

    dst = sqlite3.connect(dst_path)
    extra = {"is_strong": "true"} if is_strongs else {}
    write_mybible_info(dst, desc, lang, extra)

    dst.execute("""
        CREATE TABLE dictionary (
            topic      TEXT PRIMARY KEY,
            definition TEXT
        )
    """)

    # e-Sword: Dictionary(Word, Definition)
    try:
        rows = src.execute("SELECT Word, Definition FROM Dictionary ORDER BY Word")
    except Exception:
        rows = src.execute("SELECT Topic, Definition FROM Dictionary ORDER BY Topic")

    out = []
    for word, defn in rows:
        out.append((word or "", strip_rtf(defn or "")))

    dst.executemany("INSERT OR REPLACE INTO dictionary VALUES (?,?)", out)
    dst.commit()
    src.close()
    dst.close()
    print(f"Converted Dictionary: {desc} ({len(out)} entries)")


# ---------------------------------------------------------------------------
# Generic topic / reference / devotional  (.topx / .resx / .devotx)
# — store as dictionary table so the app can display them
# ---------------------------------------------------------------------------

def convert_generic(src_path, dst_path):
    src = sqlite3.connect(src_path)
    info = read_esword_info(src)
    desc = info.get("Title") or os.path.splitext(os.path.basename(src_path))[0]
    lang = info.get("Language") or "en"

    dst = sqlite3.connect(dst_path)
    write_mybible_info(dst, desc, lang)
    dst.execute("CREATE TABLE dictionary (topic TEXT PRIMARY KEY, definition TEXT)")

    # Try common table/column names
    out = []
    for table, col_a, col_b in [
        ("Topics",      "Topic",   "Body"),
        ("References",  "Verse",   "Body"),
        ("Devotions",   "Date",    "Body"),
        ("Dictionary",  "Word",    "Definition"),
    ]:
        try:
            rows = src.execute(f"SELECT {col_a}, {col_b} FROM {table}")
            for a, b in rows:
                out.append((str(a or ""), strip_rtf(b or "")))
            break
        except Exception:
            continue

    dst.executemany("INSERT OR REPLACE INTO dictionary VALUES (?,?)", out)
    dst.commit()
    src.close()
    dst.close()
    print(f"Converted {desc} ({len(out)} entries)")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 3:
        print("Usage: esword_converter.py <source_file> <dest_folder>")
        sys.exit(1)

    src_path = sys.argv[1]
    dest_folder = sys.argv[2]

    if not os.path.isfile(src_path):
        print(f"Source file not found: {src_path}")
        sys.exit(1)

    if not os.path.isdir(dest_folder):
        print(f"Destination folder not found: {dest_folder}")
        sys.exit(1)

    ext = os.path.splitext(src_path)[1].lower()
    base = os.path.splitext(os.path.basename(src_path))[0]
    dst_path = os.path.join(dest_folder, base + ".sqlite3")

    # Remove any previous conversion output
    if os.path.exists(dst_path):
        os.remove(dst_path)

    try:
        if ext in (".bblx", ".mybible"):
            convert_bible(src_path, dst_path, ext)
        elif ext == ".cmtx":
            convert_commentary(src_path, dst_path)
        elif ext == ".lexdbtx":
            convert_dictionary(src_path, dst_path, is_strongs=True)
        elif ext == ".dctx":
            convert_dictionary(src_path, dst_path, is_strongs=False)
        elif ext in (".topx", ".resx", ".devotx"):
            convert_generic(src_path, dst_path)
        else:
            print(f"Unsupported file type: {ext}")
            sys.exit(1)
    except Exception as e:
        # Clean up partial output
        if os.path.exists(dst_path):
            os.remove(dst_path)
        print(f"Conversion error: {e}")
        sys.exit(1)

    print(f"Output: {dst_path}")
    sys.exit(0)


if __name__ == "__main__":
    main()
