"""Builds assets/dict.db, the read-only SQLite dictionary of the app's courses for French speakers.

Each course has a module that reads its sources and returns its deck: mandarin.py (Taiwan
Mandarin, lang 'man') and korean.py ('kor'). This script owns the database: it picks the
example sentences and replaces one course's rows, leaving the others as they are. A new course
is a new module with the same interface, a line in COURSES, and its entry in lib/course.dart.

Sources (download each into its own scratch dir, then pass the paths):
  curl -LO https://chine.in/assets/cfdict/cfdict.u8                 # CFDICT, CC BY-SA 3.0
  curl -LO https://raw.githubusercontent.com/ivankra/tocfl/master/tocfl-202307.csv
  # Tatoeba sentences, CC BY 2.0 FR:
  curl -LO https://downloads.tatoeba.org/exports/per_language/cmn/cmn_sentences.tsv.bz2
  curl -LO https://downloads.tatoeba.org/exports/per_language/fra/fra_sentences.tsv.bz2
  curl -LO https://downloads.tatoeba.org/exports/per_language/cmn/cmn-fra_links.tsv.bz2
  # Make Me a Hanzi character composition, LGPL 3:
  curl -LO https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt
  pip install dragonmapper opencc-python-reimplemented               # pinyin -> zhuyin, 简 -> 繁
  # Korean: krdict (한국어기초사전, NIKL, CC BY-SA 2.0 KR), the 11 XML files of
  # github.com/spellcheck-ko/korean-dict-nikl-krdict into one dir; Tatoeba, into the dir above:
  curl -LO https://downloads.tatoeba.org/exports/per_language/kor/kor_sentences.tsv.bz2
  curl -LO https://downloads.tatoeba.org/exports/per_language/kor/kor-fra_links.tsv.bz2
  curl -LO https://downloads.tatoeba.org/exports/per_language/kor/kor-eng_links.tsv.bz2
  curl -LO https://downloads.tatoeba.org/exports/per_language/eng/eng-fra_links.tsv.bz2
  pip install koroman kiwipiepy                                      # romanization, verb lemmas

Usage (each command rewrites only its own rows; from an empty dict.db, run all three):
  python tool/build_words.py man cfdict.u8 tocfl-202307.csv <tatoeba dir> assets/
  python tool/build_words.py kor <krdict dir> <tatoeba dir> assets/
  python tool/build_words.py chars cfdict.u8 dictionary.txt assets/   # Mandarin's chars table

A course module has SENTENCE_LENGTH, UNKNOWN_LEVEL and build(*sources) returning:
  words: rows (hanzi, roman, zhuyin, fr, tag) in study order (the curriculum);
  level: hanzi -> 0 for the hand-written essentials, else its level in the source list;
  sentences: (id, hanzi, roman, fr), ids from 1 (shifted here past the other courses');
  candidates: hanzi -> [(sentence id, the sentence's words, its length)] to choose examples from.

Tables:
  words(lang, pos, hanzi, roman, zhuyin, fr, tag), pos the study order;
  sentences(id, hanzi, roman, fr), shared by the courses;
  examples(lang, hanzi, n, sid): up to 3 sentences per word, preferring short ones whose
    other words are no harder than the word itself;
  chars(hanzi, kind, parts, semantic, phonetic, hint, readings): see mandarin.py.
"""

import os
import sqlite3
import sys
import time
from collections import Counter

import korean
import mandarin

COURSES = {'man': mandarin, 'kor': korean}

SCHEMA = '''
    CREATE TABLE IF NOT EXISTS words(lang TEXT, pos INTEGER, hanzi TEXT, roman TEXT, zhuyin TEXT, fr TEXT,
                                     tag TEXT, PRIMARY KEY(lang, pos));
    CREATE TABLE IF NOT EXISTS sentences(id INTEGER PRIMARY KEY, hanzi TEXT, roman TEXT, fr TEXT);
    CREATE TABLE IF NOT EXISTS examples(lang TEXT, hanzi TEXT, n INTEGER, sid INTEGER, PRIMARY KEY(lang, hanzi, n));
    CREATE TABLE IF NOT EXISTS chars(hanzi TEXT PRIMARY KEY, kind TEXT, parts TEXT, semantic TEXT, phonetic TEXT,
                                     hint TEXT, readings TEXT);
'''


def pick_examples(level, candidates, length, unknown):
    """Up to 3 (hanzi, n, sentence id) per word: first the sentences whose other words are no harder
    than the word (words outside the deck count as [unknown]), then those closest to [length]."""
    def hardness(words, target):
        return sum(max(0, level.get(w, unknown) - max(1, level[target])) for w in words if w != target)

    examples = []
    for h, found in candidates.items():
        best = sorted(found, key=lambda f: (hardness(f[1], h) > 0, hardness(f[1], h), abs(f[2] - length), f[0]))
        seen = []
        for sid, _, _ in best:
            if sid not in seen:
                seen.append(sid)
            if len(seen) == 3:
                break
        examples += [(h, n, sid) for n, sid in enumerate(seen)]
    return examples


def connect(out_dir):
    db = sqlite3.connect(f'{out_dir}/dict.db')
    db.executescript(SCHEMA)
    return db


def bump_version(db, out_dir):
    """Stamps dict.db's SQLite header and dict.version: the app recopies its dict.db when the stamp
    changes. Closes [db]."""
    version = int(time.time())
    db.execute(f'PRAGMA user_version = {version}')
    db.commit()
    db.execute('VACUUM')
    db.close()
    open(os.path.join(out_dir, 'dict.version'), 'w').write(f'{version}\n')


def build_course(lang, out_dir, *sources):
    """(Re)writes one course's words, its examples and their sentences; the other courses stay."""
    course = COURSES[lang]
    words, level, sentences, candidates = course.build(*sources)
    examples = pick_examples(level, candidates, course.SENTENCE_LENGTH, course.UNKNOWN_LEVEL)
    used = {sid for *_, sid in examples}

    db = connect(out_dir)
    db.execute('DELETE FROM words WHERE lang = ?', (lang,))
    db.execute('DELETE FROM examples WHERE lang = ?', (lang,))
    db.execute('DELETE FROM sentences WHERE id NOT IN (SELECT sid FROM examples)')
    base = db.execute('SELECT coalesce(max(id), 0) FROM sentences').fetchone()[0]
    db.executemany('INSERT INTO words VALUES (?,?,?,?,?,?,?)', [(lang, i, *r) for i, r in enumerate(words)])
    db.executemany('INSERT INTO sentences VALUES (?,?,?,?)', [(base + s[0], *s[1:]) for s in sentences if s[0] in used])
    db.executemany('INSERT INTO examples VALUES (?,?,?,?)', [(lang, h, n, base + sid) for h, n, sid in examples])
    bump_version(db, out_dir)
    levels = ', '.join(f'{lv}: {n}' for lv, n in sorted(Counter(level.values()).items()))
    print(f'{lang}: {len(words)} words (by level, 0 = essentials: {levels}), {len(used)} sentences, '
          f'{len({h for h, _, _ in examples})} words with examples')


def build_chars(out_dir, *sources):
    """(Re)writes the chars table; nothing else changes."""
    rows = mandarin.chars(*sources)
    db = connect(out_dir)
    db.execute('DELETE FROM chars')
    db.executemany('INSERT INTO chars VALUES (?,?,?,?,?,?,?)', rows)
    bump_version(db, out_dir)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')  # the summaries print hangul and hanzi (Windows consoles)
    if len(sys.argv) < 3 or sys.argv[1] not in [*COURSES, 'chars']:
        sys.exit(__doc__)
    command, *sources, out_dir = sys.argv[1:]
    if command == 'chars':
        build_chars(out_dir, *sources)
    else:
        build_course(command, out_dir, *sources)
