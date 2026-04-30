-- Merge Strong_Dictionary.SQLite3 and SECE.dictionary.SQLite3 into one runtime-safe dictionary.
--
-- Intended usage:
-- 1. cd into the folder that contains both source databases
--    Example:
--      cd "/Users/richardbillings/XcodeOffline/Graphē One Codex/Graphē One Codex/References"
-- 2. Run:
--      sqlite3 Merged_Strongs.dictionary.SQLite3 < ../docs/MERGE_STRONGS_DICTIONARIES.sql
--
-- Output policy:
-- - Strong_Dictionary topics define the baseline keyspace.
-- - Missing SECE topics are inserted.
-- - Shared topics keep Strong_Dictionary.definition as the primary definition.
-- - Shared topics store SECE.definition in expanded_definition.
-- - G0... entries are preserved as-is.

PRAGMA journal_mode = DELETE;
PRAGMA synchronous = NORMAL;

ATTACH DATABASE 'Strong_Dictionary.SQLite3' AS strong;
ATTACH DATABASE 'SECE.dictionary.SQLite3' AS sece;

BEGIN TRANSACTION;

CREATE TABLE info AS
SELECT *
FROM strong.info;

CREATE TABLE cognate_strong_numbers AS
SELECT *
FROM strong.cognate_strong_numbers;

CREATE TABLE morphology_indications AS
SELECT *
FROM strong.morphology_indications;

CREATE TABLE dictionary (
    topic TEXT PRIMARY KEY,
    definition TEXT,
    lexeme TEXT,
    transliteration TEXT,
    pronunciation TEXT,
    short_definition TEXT,
    expanded_definition TEXT,
    source_flags TEXT NOT NULL
);

INSERT INTO dictionary (
    topic,
    definition,
    lexeme,
    transliteration,
    pronunciation,
    short_definition,
    expanded_definition,
    source_flags
)
SELECT
    topic,
    definition,
    lexeme,
    transliteration,
    pronunciation,
    short_definition,
    NULL,
    'strong'
FROM strong.dictionary;

UPDATE dictionary
SET
    lexeme = COALESCE(
        NULLIF(dictionary.lexeme, ''),
        NULLIF((SELECT s.lexeme FROM sece.dictionary s WHERE s.topic = dictionary.topic), '')
    ),
    transliteration = COALESCE(
        NULLIF(dictionary.transliteration, ''),
        NULLIF((SELECT s.transliteration FROM sece.dictionary s WHERE s.topic = dictionary.topic), '')
    ),
    pronunciation = COALESCE(
        NULLIF(dictionary.pronunciation, ''),
        NULLIF((SELECT s.pronunciation FROM sece.dictionary s WHERE s.topic = dictionary.topic), '')
    ),
    short_definition = COALESCE(
        NULLIF(dictionary.short_definition, ''),
        NULLIF((SELECT s.short_definition FROM sece.dictionary s WHERE s.topic = dictionary.topic), '')
    ),
    expanded_definition = NULLIF(
        (SELECT s.definition FROM sece.dictionary s WHERE s.topic = dictionary.topic),
        ''
    ),
    source_flags = 'both'
WHERE EXISTS (
    SELECT 1
    FROM sece.dictionary s
    WHERE s.topic = dictionary.topic
);

INSERT INTO dictionary (
    topic,
    definition,
    lexeme,
    transliteration,
    pronunciation,
    short_definition,
    expanded_definition,
    source_flags
)
SELECT
    s.topic,
    s.definition,
    s.lexeme,
    s.transliteration,
    s.pronunciation,
    s.short_definition,
    NULL,
    'sece'
FROM sece.dictionary s
LEFT JOIN dictionary d ON d.topic = s.topic
WHERE d.topic IS NULL;

CREATE INDEX idx_dictionary_topic ON dictionary(topic);

COMMIT;

DETACH DATABASE strong;
DETACH DATABASE sece;
