#!/usr/bin/env python3
"""
graphe_converter.py

Converts supported module sources into runtime-readable `.graphe` files.

Pipeline:
  source module -> normalized MyBible-style sqlite3 -> `.graphe`

Supported source inputs:
  - plain e-Sword Bible sqlite input
    .bbl
  - normalized sqlite inputs that already match the app's runtime schemas
    .sqlite3 .sqlite .db .mybible

Usage:
  python3 graphe_converter.py <source_file> <dest_folder>

Notes:
  - `.graphe` in this repo is a normal SQLite database whose content payloads
    are AES-256-CBC encrypted per value and stored as BLOBs.
  - This script only encrypts content-bearing columns that are safe to encrypt
    for the current runtime. Lookup/index columns remain plaintext.
"""

from __future__ import annotations

import ctypes
import os
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

COMMON_CRYPTO = ctypes.cdll.LoadLibrary("/usr/lib/system/libcommonCrypto.dylib")

kCCEncrypt = 0
kCCAlgorithmAES128 = 0
kCCOptionPKCS7Padding = 0x0001
kCCKeySizeAES256 = 32
kCCBlockSizeAES128 = 16
kCCSuccess = 0

GRAPHE_KEY = bytes([
    0x9D, 0xD4, 0x49, 0x2D, 0x38, 0xE1, 0x65, 0xB6,
    0xF6, 0x69, 0x9C, 0x3E, 0x31, 0x5F, 0x2F, 0x65,
    0xF3, 0xFF, 0x6C, 0xB4, 0x74, 0xEA, 0x6F, 0xCB,
    0x9B, 0x6E, 0x22, 0x22, 0xFC, 0xA4, 0x6B, 0xFE,
])

SUPPORTED_ESWORD_BIBLE_EXTS = {".bbl"}
SUPPORTED_SQLITE_EXTS = {".sqlite3", ".sqlite", ".db", ".mybible"}

# Only encrypt value/content columns. Lookup columns must remain plaintext.
ENCRYPTED_COLUMNS = {
    "info": {"value"},
    "verses": {"text"},
    "commentaries": {"text"},
    "commentary": {"text"},
    "dictionary": {"definition"},
    "devotions": {"title", "body", "text", "content"},
    "subheadings": {"text"},
}


def encrypt_graphe_value(text: str) -> bytes:
    plaintext = text.encode("utf-8")
    iv = os.urandom(16)
    out_size = len(plaintext) + kCCBlockSizeAES128
    out_buffer = ctypes.create_string_buffer(out_size)
    out_length = ctypes.c_size_t(0)

    status = COMMON_CRYPTO.CCCrypt(
        kCCEncrypt,
        kCCAlgorithmAES128,
        kCCOptionPKCS7Padding,
        ctypes.c_char_p(GRAPHE_KEY),
        kCCKeySizeAES256,
        ctypes.c_char_p(iv),
        ctypes.c_char_p(plaintext),
        len(plaintext),
        out_buffer,
        out_size,
        ctypes.byref(out_length),
    )
    if status != kCCSuccess:
        raise RuntimeError(f"CommonCrypto encryption failed with status {status}")

    return iv + out_buffer.raw[: out_length.value]


def find_table_case_insensitive(connection: sqlite3.Connection, desired_name: str) -> str | None:
    rows = connection.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    ).fetchall()
    for row in rows:
        table_name = row[0]
        if table_name.lower() == desired_name.lower():
            return table_name
    return None


def column_map(connection: sqlite3.Connection, table_name: str) -> dict[str, str]:
    rows = connection.execute(f"PRAGMA table_info('{table_name}')").fetchall()
    return {str(row[1]).lower(): str(row[1]) for row in rows}


def first_present_column(columns: dict[str, str], candidates: list[str]) -> str | None:
    for candidate in candidates:
        if candidate in columns:
            return columns[candidate]
    return None


def copy_info_table(source_connection: sqlite3.Connection, destination_connection: sqlite3.Connection) -> None:
    destination_connection.execute("CREATE TABLE info (name TEXT PRIMARY KEY, value TEXT)")

    details_table = find_table_case_insensitive(source_connection, "details")
    if details_table is None:
        destination_connection.executemany(
            "INSERT OR REPLACE INTO info (name, value) VALUES (?, ?)",
            [
                ("description", "Converted from e-Sword .bbl"),
                ("language", "en"),
            ],
        )
        return

    details_columns = column_map(source_connection, details_table)
    key_column = first_present_column(details_columns, ["field", "name", "key"])
    value_column = first_present_column(details_columns, ["value", "content", "data"])
    if key_column is None or value_column is None:
        destination_connection.executemany(
            "INSERT OR REPLACE INTO info (name, value) VALUES (?, ?)",
            [
                ("description", "Converted from e-Sword .bbl"),
                ("language", "en"),
            ],
        )
        return

    rows = source_connection.execute(
        f"SELECT {key_column}, {value_column} FROM '{details_table}'"
    ).fetchall()
    inserts = []
    for key, value in rows:
        if key is None or value is None:
            continue
        inserts.append((str(key).strip(), str(value)))

    inserts.extend([
        ("description", "Converted from e-Sword .bbl"),
        ("language", "en"),
    ])
    destination_connection.executemany(
        "INSERT OR REPLACE INTO info (name, value) VALUES (?, ?)",
        inserts,
    )


def convert_esword_bible_to_sqlite(source_path: Path, output_path: Path) -> None:
    source_connection = sqlite3.connect(source_path)
    destination_connection = sqlite3.connect(output_path)
    try:
        bible_table = find_table_case_insensitive(source_connection, "bible")
        if bible_table is None:
            raise RuntimeError("No Bible table found in source file.")

        bible_columns = column_map(source_connection, bible_table)
        book_column = first_present_column(bible_columns, ["book", "booknumber", "book_number"])
        chapter_column = first_present_column(bible_columns, ["chapter", "chapter_number"])
        verse_column = first_present_column(bible_columns, ["verse", "verse_number"])
        text_column = first_present_column(bible_columns, ["scripture", "text", "versetext", "content"])

        if None in {book_column, chapter_column, verse_column, text_column}:
            raise RuntimeError("Bible table schema is not recognized.")

        destination_connection.execute(
            """
            CREATE TABLE verses (
                book_number INTEGER NOT NULL,
                chapter INTEGER NOT NULL,
                verse INTEGER NOT NULL,
                text TEXT,
                PRIMARY KEY (book_number, chapter, verse)
            )
            """
        )

        rows = source_connection.execute(
            f"""
            SELECT {book_column}, {chapter_column}, {verse_column}, {text_column}
            FROM '{bible_table}'
            ORDER BY {book_column}, {chapter_column}, {verse_column}
            """
        ).fetchall()

        destination_connection.executemany(
            """
            INSERT OR REPLACE INTO verses (book_number, chapter, verse, text)
            VALUES (?, ?, ?, ?)
            """,
            [
                (int(book), int(chapter), int(verse), "" if text is None else str(text))
                for book, chapter, verse, text in rows
            ],
        )
        copy_info_table(source_connection, destination_connection)
        destination_connection.commit()
    finally:
        destination_connection.close()
        source_connection.close()


def normalize_to_sqlite(source_path: Path, temp_dir: Path) -> Path:
    ext = source_path.suffix.lower()
    if ext in SUPPORTED_SQLITE_EXTS:
        return source_path

    output_path = temp_dir / f"{source_path.stem}.sqlite3"
    if output_path.exists():
        output_path.unlink()

    if ext in SUPPORTED_ESWORD_BIBLE_EXTS:
        convert_esword_bible_to_sqlite(source_path, output_path)
    else:
        raise RuntimeError(f"Unsupported source type: {ext}")

    return output_path


def package_sqlite_as_graphe(sqlite_path: Path, graphe_path: Path) -> int:
    if graphe_path.exists():
        graphe_path.unlink()
    shutil.copy2(sqlite_path, graphe_path)

    conn = sqlite3.connect(graphe_path)
    encrypted_values = 0
    try:
        tables = [
            row[0]
            for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        ]

        for table in tables:
            target_columns = ENCRYPTED_COLUMNS.get(table, set())
            if not target_columns:
                continue

            pragma_rows = conn.execute(f"PRAGMA table_info('{table}')").fetchall()
            table_columns = {row[1] for row in pragma_rows}
            candidate_columns = [col for col in target_columns if col in table_columns]
            if not candidate_columns:
                continue

            select_columns = ", ".join(["rowid"] + candidate_columns)
            rows = conn.execute(f"SELECT {select_columns} FROM '{table}'").fetchall()

            for row in rows:
                rowid = row[0]
                updates = {}
                for index, column_name in enumerate(candidate_columns, start=1):
                    value = row[index]
                    if value is None:
                        continue
                    if isinstance(value, bytes):
                        # Already packaged.
                        continue
                    text_value = str(value)
                    if not text_value:
                        continue
                    updates[column_name] = encrypt_graphe_value(text_value)

                if not updates:
                    continue

                assignments = ", ".join(f"{column_name}=?" for column_name in updates)
                parameters = list(updates.values()) + [rowid]
                conn.execute(f"UPDATE '{table}' SET {assignments} WHERE rowid=?", parameters)
                encrypted_values += len(updates)

        conn.commit()
    finally:
        conn.close()

    return encrypted_values


def validate_runtime_shape(graphe_path: Path) -> None:
    conn = sqlite3.connect(graphe_path)
    try:
        tables = {
            row[0]
            for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
        }
        if not tables:
            raise RuntimeError("Packaged file has no readable tables.")

        if "info" not in tables:
            print("Warning: packaged file has no info table.")
    finally:
        conn.close()


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: graphe_converter.py <source_file> <dest_folder>")
        return 1

    source_path = Path(sys.argv[1]).expanduser().resolve()
    dest_folder = Path(sys.argv[2]).expanduser().resolve()

    if not source_path.is_file():
        print(f"Source file not found: {source_path}")
        return 1
    if not dest_folder.is_dir():
        print(f"Destination folder not found: {dest_folder}")
        return 1

    ext = source_path.suffix.lower()
    if ext not in SUPPORTED_ESWORD_BIBLE_EXTS and ext not in SUPPORTED_SQLITE_EXTS:
        print(f"Unsupported source type: {ext}")
        return 1

    output_path = dest_folder / f"{source_path.stem}.graphe"

    with tempfile.TemporaryDirectory(prefix="graphe-converter-") as temp_dir_raw:
        temp_dir = Path(temp_dir_raw)
        normalized_sqlite = normalize_to_sqlite(source_path, temp_dir)
        encrypted_count = package_sqlite_as_graphe(normalized_sqlite, output_path)
        validate_runtime_shape(output_path)

    print(f"Packaged .graphe: {output_path}")
    print(f"Encrypted values: {encrypted_count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
