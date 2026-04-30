# Strong's Dataset Comparison Notes

This note consolidates the terminal outputs and conclusions from comparing:

- `Strong_Dictionary.SQLite3`
- `SECE.dictionary.SQLite3`

Compared files:

- `/Users/richardbillings/Desktop/Codex/Strong_Dictionary.SQLite3`
- `/Users/richardbillings/Desktop/Codex/SECE.dictionary.SQLite3`

## Short Handoff

- The two Strong's dictionaries are not interchangeable.
- `SECE.dictionary.SQLite3` has much richer long-form `definition` content on average.
- `Strong_Dictionary.SQLite3` contains extended `G0...` entries that `SECE.dictionary.SQLite3` lacks.
- Topic drift is not limited to `G0...`; Greek coverage differs in both directions.
- `Strong_Dictionary.SQLite3` includes many suffixed or extended Greek keys.
- `SECE.dictionary.SQLite3` includes a contiguous block of standard Greek keys absent from `Strong_Dictionary.SQLite3`.
- `short_definition` overlap looks broadly aligned where topics match.
- Hebrew divergence appears minimal in this comparison.
- Exact dictionary keys must be preserved.
- Do not normalize away meaningful zeros or suffix-like distinctions.
- Do not silently swap `Strong_Dictionary.SQLite3` for `SECE.dictionary.SQLite3`.
- If `SECE` is used in future, treat it as a selectable or layered enrichment source, not an assumed replacement.

## Scope

The comparison work focused on:

- topic-set overlap and drift
- long-definition richness
- short-definition similarity
- extended `G0...` coverage
- non-`G0` Greek key drift
- whether the datasets appear interchangeable

## Key Conclusion

These two dictionaries are not interchangeable.

- `SECE.dictionary.SQLite3` appears materially richer in long-form definition content.
- `Strong_Dictionary.SQLite3` contains extended `G0...` Greek entries that `SECE.dictionary.SQLite3` lacks.
- Coverage also differs beyond `G0...`, especially in Greek topics.
- The divergence is patterned, not random.

Architecturally, this supports:

- preserving exact Strong's keys
- not collapsing extended keys into standard keys
- treating the two dictionaries as partially overlapping sources
- avoiding silent source substitution

## Earlier Structural Check

Output:

```text
name
----------------------
info
cognate_strong_numbers
dictionary
morphology_indications
```

Interpretation:

- The observed issue was not about obvious table absence in `SECE.dictionary.SQLite3`.

## Hebrew `H0...` Check

Output:

```text
metric        value
------------  -----
db1_h0_count  0
db2_h0_count  0
```

Interpretation:

- No `H0...` entries were present in either compared file.
- The Hebrew side did not show the same kind of extended-key pattern seen on the Greek side.

## Topic Drift and Shared Short Definitions

Output:

```text
metric              value
------------------  -----
topics_only_in_db1  168
topics_only_in_db2  102
```

```text
metric                                    value
----------------------------------------  -----
shared_topics_with_diff_short_definition  0
```

Interpretation:

- Topic sets differ in both directions.
- Where topics overlap, `short_definition` matched in the earlier comparison query.

## Shared Topics and Definition Length Averages

Output:

```text
metric              value
------------------  -----
shared_topics       14196
topics_only_in_db1  168
topics_only_in_db2  102
```

```text
metric                 value
---------------------  ------
avg_def_len_db1        261.15
avg_def_len_db2        640.28
avg_short_def_len_db1  7.48
avg_short_def_len_db2  7.42
```

Interpretation:

- `SECE.dictionary.SQLite3` is substantially richer in the long `definition` field.
- `short_definition` length is nearly the same between the two datasets.
- The main prose richness difference is in the full definition body, not the short summary.

## Sample Shared Topics Where `SECE` Definitions Are Longer

Output excerpt:

```text
topic  db1_def_len  db2_def_len
-----  -----------  -----------
H935   647          5019
H5375  740          4865
H7725  1238         4901
H1980  736          4193
H5414  883          4072
H3318  839          3954
H5674  993          4085
H7200  658          3705
H7760  736          3732
H5927  794          3608
G4160  753          3538
G4863  415          3171
G1325  570          3314
G2192  759          3407
H3947  303          2927
G1587  262          2841
G5087  709          3276
H6213  917          3458
H7121  508          2969
G5015  200          2659
```

Interpretation:

- `SECE.dictionary.SQLite3` is often dramatically more verbose on shared entries.
- This supports the claim that its definition content is richer.

## Sample Shared Topics Where `Strong_Dictionary` Definitions Are Longer

Output excerpt:

```text
topic  db1_def_len  db2_def_len
-----  -----------  -----------
G3753  720          554
H3433  871          785
H1787  489          455
H8471  670          644
H3778  857          854
```

Interpretation:

- The richness advantage is not universal.
- `SECE.dictionary.SQLite3` is generally longer, but not always.

## `G0...` Entries Present Only in `Strong_Dictionary`

Output:

```text
bucket       topic
-----------  ------
db1_only_g0  G00311
db1_only_g0  G00321
db1_only_g0  G00951
db1_only_g0  G01191
db1_only_g0  G01591
db1_only_g0  G02371
db1_only_g0  G02921
db1_only_g0  G02931
db1_only_g0  G02981
db1_only_g0  G03111
db1_only_g0  G03741
db1_only_g0  G04151
db1_only_g0  G06891
db1_only_g0  G07201
db1_only_g0  G07331
db1_only_g0  G08481
db1_only_g0  G08491
db1_only_g0  G08621
db1_only_g0  G09551
db1_only_g0  G09611
db1_only_g0  G09941
```

Interpretation:

- `Strong_Dictionary.SQLite3` includes at least 21 extended `G0...` keys absent from `SECE.dictionary.SQLite3`.
- This reinforces the need to preserve exact Strong's dictionary keys.

## Difference Buckets by Topic Family

Output:

```text
bucket            count
----------------  -----
db1_only_g0       21
db1_only_g_other  146
db1_only_h_other  1
db2_only_g_other  101
db2_only_other    1
```

Interpretation:

- The divergence is not limited to `G0...`.
- Most drift is Greek-side drift in both directions.
- Hebrew divergence is minimal in this comparison.

## Sample `db1_only_g_other` and `db2_only_g_other`

### `db1_only_g_other`

Output excerpt:

```text
G10681
G10791
G11601
G11771
G11891
G12441
G12751
G13061
G13151
G13261
G13561
G13641
G13811
G14251
G14371
G14571
G14601
G14901
G15361
G15431
G15671
G15691
G15991
G16001
G16481
G16482
G17001
G17051
G17281
G17461
G17521
G17522
G17591
G17741
G18571
G18831
G19451
G19521
G19801
G19861
G19871
G20371
G21031
G21151
G21171
G21371
G21461
G21881
G22041
G22691
G22791
G23091
G23491
G24101
G24751
G24881
G24921
G24922
G25011
G25311
```

### `db2_only_g_other`

Output excerpt:

```text
G2717
G3203
G3204
G3205
G3206
G3207
G3208
G3209
G3210
G3211
G3212
G3213
G3214
G3215
G3216
G3217
G3218
G3219
G3220
G3221
G3222
G3223
G3224
G3225
G3226
G3227
G3228
G3229
G3230
G3231
G3232
G3233
G3234
G3235
G3236
G3237
G3238
G3239
G3240
G3241
G3242
G3243
G3244
G3245
G3246
G3247
G3248
G3249
G3250
G3251
G3252
G3253
G3254
G3255
G3256
G3257
G3258
G3259
G3260
G3261
```

Interpretation:

- This is patterned drift, not random drift.
- `Strong_Dictionary.SQLite3` contains many suffixed or extended Greek keys.
- `SECE.dictionary.SQLite3` contains a contiguous run of standard Greek keys absent from `Strong_Dictionary.SQLite3`.
- The two datasets are expressing Greek topic identity differently.

## Architecture Implications

The comparison supports these rules:

- Preserve exact dictionary keys first.
- Do not normalize away semantically meaningful zeros.
- Do not assume one Strong's dictionary file can silently replace another.
- Keep verse-tag normalization separate from dictionary-key normalization.
- If richer content from `SECE.dictionary.SQLite3` is ever desired, prefer:
  - selectable source behavior, or
  - layered enrichment behavior
  instead of silent substitution.

## Relation to This App

This comparison informed hardening work in `ScriptureStudy`:

- Strong's lookup behavior was adjusted to preserve exact extended keys while still allowing useful canonical lookup for standard inputs.
- Regression tests were added so future cleanup does not collapse extended IDs like:
  - `G00311`
  - `G03111`
  - `H00031`

## Current Working Assessment

- `Strong_Dictionary.SQLite3` appears safer for coverage and extended-key compatibility.
- `SECE.dictionary.SQLite3` appears stronger for long-form definition richness.
- Neither file should currently be treated as a strict superset of the other.
