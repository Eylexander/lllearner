"""Builds assets/dict.db, the read-only SQLite dictionary of the app's courses. There is one
course today, Taiwan Mandarin for French speakers (lang 'man'); a new course is a new
deck (lang value) plus its entry in lib/course.dart.

Sources (download each into its own scratch dir, then pass the paths):
  curl -LO https://chine.in/assets/cfdict/cfdict.u8                 # CFDICT, CC BY-SA 3.0
  curl -LO https://raw.githubusercontent.com/ivankra/tocfl/master/tocfl-202307.csv
  # Tatoeba sentences, CC BY 2.0 FR:
  curl -LO https://downloads.tatoeba.org/exports/per_language/cmn/cmn_sentences.tsv.bz2
  curl -LO https://downloads.tatoeba.org/exports/per_language/fra/fra_sentences.tsv.bz2
  curl -LO https://downloads.tatoeba.org/exports/per_language/cmn/cmn-fra_links.tsv.bz2
  pip install dragonmapper opencc-python-reimplemented               # pinyin -> zhuyin, 简 -> 繁
  python tool/build_words.py cfdict.u8 tocfl-202307.csv <tatoeba dir> assets/

Tables:
  words(lang, pos, hanzi, roman, zhuyin, fr, tag) in study order (pos): hand-written
    essentials by theme, then TOCFL levels '1 · Débutant' … '6 · Expert';
  sentences(id, hanzi, roman, fr): Tatoeba pairs, converted to Taiwan characters and
    vocabulary (OpenCC s2twp); roman is pinyin from the deck's readings (TOCFL, so
    Taiwan pronunciations) and CFDICT for other words;
  examples(lang, hanzi, n, sid): up to 3 sentences per word, preferring short ones whose
    other words are no harder than the word itself.

Mandarin: the TOCFL list with CFDICT glosses. The CFDICT reading is chosen to match
TOCFL's pinyin (letters and tones). FR_FIX corrects automatic glosses.
"""

import bz2
import csv
import json
import re
import sys
import unicodedata

LEVELS = ['1 · Débutant', '2 · Débutant +', '3 · Élémentaire', '4 · Intermédiaire', '5 · Avancé', '6 · Expert']

# Mandarin (hanzi, pinyin as pronounced with 一/不 sandhi, français, thème); zhuyin is derived.
MAN_ESSENTIALS = [
    ('你好', 'nǐ hǎo', 'Bonjour', 'Salutations'), ('早安', "zǎo'ān", 'Bonjour (le matin)', 'Salutations'),
    ('晚安', "wǎn'ān", 'Bonne nuit', 'Salutations'), ('再見', 'zàijiàn', 'Au revoir', 'Salutations'),
    ('謝謝', 'xièxie', 'Merci', 'Salutations'), ('不客氣', 'bú kèqì', 'De rien', 'Salutations'),
    ('對不起', 'duìbùqǐ', 'Désolé(e)', 'Salutations'), ('不好意思', 'bù hǎoyìsi', 'Excusez-moi', 'Salutations'),
    ('沒關係', 'méi guānxì', "Ce n'est pas grave", 'Salutations'), ('請問', 'qǐngwèn', 'Excusez-moi, puis-je demander…', 'Salutations'),
    ('歡迎', 'huānyíng', 'Bienvenue', 'Salutations'), ('我叫', 'wǒ jiào', "Je m'appelle…", 'Salutations'),
    ('請', 'qǐng', "S'il vous plaît ; inviter", 'Bases'), ('是', 'shì', 'Être ; oui', 'Bases'),
    ('不是', 'bú shì', 'Non ; ne pas être', 'Bases'), ('好', 'hǎo', 'Bien ; d’accord', 'Bases'),
    ('好喔', 'hǎo o', 'Ok ! (familier, très taïwanais)', 'Bases'), ('真的嗎', 'zhēn de ma', 'Vraiment ?', 'Bases'),
    ('加油', 'jiāyóu', 'Courage ! ; allez !', 'Bases'), ('很棒', 'hěn bàng', 'Génial', 'Bases'),
    ('我', 'wǒ', 'Je ; moi', 'Personnes'), ('你', 'nǐ', 'Tu ; toi', 'Personnes'), ('他', 'tā', 'Il ; lui', 'Personnes'),
    ('她', 'tā', 'Elle', 'Personnes'), ('我們', 'wǒmen', 'Nous', 'Personnes'), ('朋友', 'péngyǒu', 'Ami(e)', 'Personnes'),
    ('老師', 'lǎoshī', 'Professeur', 'Personnes'), ('學生', 'xuéshēng', 'Étudiant(e)', 'Personnes'),
    ('法國人', 'Fǎguó rén', 'Français(e)', 'Personnes'), ('台灣', 'Táiwān', 'Taïwan', 'Personnes'),
    ('中文', 'Zhōngwén', 'Le chinois (langue)', 'Personnes'), ('家', 'jiā', 'Maison ; famille', 'Personnes'),
    ('工作', 'gōngzuò', 'Travail ; travailler', 'Personnes'),
    ('有', 'yǒu', 'Avoir ; il y a', 'Verbes'), ('沒有', 'méiyǒu', 'Ne pas avoir', 'Verbes'),
    ('要', 'yào', 'Vouloir ; falloir', 'Verbes'), ('想', 'xiǎng', 'Penser ; avoir envie de', 'Verbes'),
    ('可以', 'kěyǐ', 'Pouvoir (permission)', 'Verbes'), ('喜歡', 'xǐhuān', 'Aimer (bien)', 'Verbes'),
    ('吃', 'chī', 'Manger', 'Verbes'), ('喝', 'hē', 'Boire', 'Verbes'), ('去', 'qù', 'Aller', 'Verbes'),
    ('來', 'lái', 'Venir', 'Verbes'), ('看', 'kàn', 'Regarder ; lire', 'Verbes'), ('說', 'shuō', 'Parler ; dire', 'Verbes'),
    ('學', 'xué', 'Apprendre', 'Verbes'), ('買', 'mǎi', 'Acheter', 'Verbes'), ('知道', 'zhīdào', 'Savoir', 'Verbes'),
    ('一', 'yī', 'Un (1)', 'Nombres'), ('二', 'èr', 'Deux (2)', 'Nombres'),
    ('兩', 'liǎng', 'Deux (devant un classificateur)', 'Nombres'), ('三', 'sān', 'Trois (3)', 'Nombres'),
    ('四', 'sì', 'Quatre (4)', 'Nombres'), ('五', 'wǔ', 'Cinq (5)', 'Nombres'), ('六', 'liù', 'Six (6)', 'Nombres'),
    ('七', 'qī', 'Sept (7)', 'Nombres'), ('八', 'bā', 'Huit (8)', 'Nombres'), ('九', 'jiǔ', 'Neuf (9)', 'Nombres'),
    ('十', 'shí', 'Dix (10)', 'Nombres'), ('一百', 'yìbǎi', 'Cent (100)', 'Nombres'),
    ('一千', 'yìqiān', 'Mille (1000)', 'Nombres'), ('塊', 'kuài', 'Dollar taïwanais (oral)', 'Nombres'),
    ('珍珠奶茶', 'zhēnzhū nǎichá', 'Bubble tea', 'Nourriture'), ('小籠包', 'xiǎolóngbāo', 'Raviolis vapeur', 'Nourriture'),
    ('牛肉麵', 'niúròu miàn', 'Soupe de nouilles au bœuf', 'Nourriture'), ('臭豆腐', 'chòu dòufǔ', 'Tofu puant', 'Nourriture'),
    ('夜市', 'yèshì', 'Marché de nuit', 'Nourriture'), ('好吃', 'hǎochī', 'Délicieux', 'Nourriture'),
    ('水', 'shuǐ', 'Eau', 'Nourriture'), ('茶', 'chá', 'Thé', 'Nourriture'), ('咖啡', 'kāfēi', 'Café', 'Nourriture'),
    ('早餐', 'zǎocān', 'Petit-déjeuner', 'Nourriture'), ('便當', 'biàndāng', 'Bento', 'Nourriture'),
    ('不要辣', 'bú yào là', 'Pas épicé, s’il vous plaît', 'Nourriture'), ('少冰', 'shǎo bīng', 'Peu de glaçons', 'Nourriture'),
    ('半糖', 'bàn táng', 'Moitié sucre', 'Nourriture'), ('外帶', 'wàidài', 'À emporter', 'Nourriture'),
    ('內用', 'nèiyòng', 'Sur place', 'Nourriture'), ('買單', 'mǎidān', "L'addition", 'Nourriture'),
    ('捷運', 'jiéyùn', 'Métro (MRT)', 'Ville'), ('公車', 'gōngchē', 'Bus', 'Ville'), ('計程車', 'jìchéngchē', 'Taxi', 'Ville'),
    ('機車', 'jīchē', 'Scooter', 'Ville'), ('腳踏車', 'jiǎotàchē', 'Vélo', 'Ville'), ('火車站', 'huǒchē zhàn', 'Gare', 'Ville'),
    ('高鐵', 'gāotiě', 'Train à grande vitesse', 'Ville'), ('悠遊卡', 'yōuyóukǎ', 'Carte EasyCard', 'Ville'),
    ('便利商店', 'biànlì shāngdiàn', 'Supérette (7-Eleven…)', 'Ville'), ('左轉', 'zuǒ zhuǎn', 'Tourner à gauche', 'Ville'),
    ('右轉', 'yòu zhuǎn', 'Tourner à droite', 'Ville'), ('直走', 'zhí zǒu', 'Tout droit', 'Ville'),
    ('醫院', 'yīyuàn', 'Hôpital', 'Ville'), ('垃圾', 'lèsè', 'Déchets (prononciation taïwanaise)', 'Ville'),
    ('今天', 'jīntiān', "Aujourd'hui", 'Temps'), ('明天', 'míngtiān', 'Demain', 'Temps'), ('昨天', 'zuótiān', 'Hier', 'Temps'),
    ('現在', 'xiànzài', 'Maintenant', 'Temps'), ('星期一', 'xīngqí yī', 'Lundi', 'Temps'),
    ('禮拜天', 'lǐbài tiān', 'Dimanche (courant à Taïwan)', 'Temps'), ('幾點', 'jǐ diǎn', 'Quelle heure ?', 'Temps'),
    ('天氣', 'tiānqì', 'La météo', 'Temps'), ('很熱', 'hěn rè', 'Il fait très chaud', 'Temps'),
    ('多少錢', 'duōshǎo qián', 'Combien ça coûte ?', 'Phrases'), ('太貴了', 'tài guì le', "C'est trop cher", 'Phrases'),
    ('我要這個', 'wǒ yào zhège', 'Je veux celui-ci', 'Phrases'), ('廁所在哪裡', 'cèsuǒ zài nǎlǐ', 'Où sont les toilettes ?', 'Phrases'),
    ('聽不懂', 'tīng bù dǒng', 'Je ne comprends pas (à l’oral)', 'Phrases'),
    ('請再說一次', 'qǐng zài shuō yí cì', 'Pouvez-vous répéter ?', 'Phrases'),
    ('我是法國人', 'wǒ shì Fǎguó rén', 'Je suis français(e)', 'Phrases'),
]

# Hand corrections for automatic glosses.
FR_FIX = {}

# Readings for sentence pinyin where a character alone is usually a particle, not its
# dictionary-first reading (的 de, not dí).
PARTICLES = {'的': 'de', '了': 'le', '著': 'zhe', '得': 'de', '個': 'ge', '們': 'men', '嗎': 'ma', '呢': 'ne',
             '吧': 'ba', '啊': 'a', '呀': 'ya', '喔': 'o', '啦': 'la'}

NOISE = re.compile(r'^(variante|voir |cf\.|CL:|nom de famille|abr[ée]v|forme ancienne|\(?arch)|\((argot|vulg|péj)', re.I)
PUNCT = {'，': ',', '。': '.', '？': '?', '！': '!', '：': ':', '；': ';', '、': ',', '「': '“', '」': '”', '…': '…'}


def tones(pinyin):
    """'dà' or 'da4' -> 'da4' (letters, then tones); neutral tones dropped so both notations compare."""
    marks = {'̄': '1', '́': '2', '̌': '3', '̀': '4'}
    p = unicodedata.normalize('NFD', pinyin.lower().replace('u:', 'ü'))
    return ''.join(c for c in p if c.isalpha()) + ''.join(marks.get(c, c if c in '1234' else '') for c in p)


def marked(numbered):
    """CFDICT 'ni3 hao3' -> 'nǐhǎo' (tone mark on a/e, on o of ou, else on the last vowel)."""
    out = []
    for syl in numbered.replace('u:', 'ü').replace('v', 'ü').split():
        m = re.fullmatch(r'([a-zü]+)([1-5])', syl.lower())
        if not m:
            out.append(syl)
            continue
        s, t = m[1], int(m[2])
        if t != 5:
            i = s.find('a') if 'a' in s else s.find('e') if 'e' in s else s.find('o') if 'ou' in s else \
                max(s.rfind(v) for v in 'iouü')
            if i >= 0:
                s = s[:i] + unicodedata.normalize('NFC', s[i] + '̄́̌̀'[t - 1]) + s[i + 1:]
        if out and s[0] in 'aeo':
            s = "'" + s
        out.append(s)
    return ''.join(out)


def zhuyin(pinyin):
    from dragonmapper.transcriptions import pinyin_to_zhuyin
    z = pinyin_to_zhuyin(pinyin.lower().replace(' ', ''))  # keep ' : wǎn'ān, not wǎ-nān
    # Taiwan convention: neutral-tone dot before the syllable; erhua ㄦ untoned.
    return re.sub(r'(\S+)˙', r'˙\1', z).replace('˙ㄦ', 'ㄦ')


def first(s):
    return s.split('/')[0].replace('(', '').replace(')', '').strip()


def gloss(defs):
    senses = [d.strip() for d in defs.split('/') if d.strip()]
    good = [d for d in senses if not NOISE.search(d)] or senses
    out = good[0]
    for d in good[1:3]:
        if len(out) + len(d) > 60:
            break
        out += ' ; ' + d
    return out[0].upper() + out[1:]


def write_db(path, decks, sentences, examples):
    import os
    import sqlite3
    import time
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.executescript('''
        CREATE TABLE words(lang TEXT, pos INTEGER, hanzi TEXT, roman TEXT, zhuyin TEXT, fr TEXT, tag TEXT,
                           PRIMARY KEY(lang, pos));
        CREATE TABLE sentences(id INTEGER PRIMARY KEY, hanzi TEXT, roman TEXT, fr TEXT);
        CREATE TABLE examples(lang TEXT, hanzi TEXT, n INTEGER, sid INTEGER, PRIMARY KEY(lang, hanzi, n));
    ''')
    for lang, rows in decks.items():
        db.executemany('INSERT INTO words VALUES (?,?,?,?,?,?,?)', [(lang, i, *r) for i, r in enumerate(rows)])
    db.executemany('INSERT INTO sentences VALUES (?,?,?,?)', sentences)
    db.executemany('INSERT INTO examples VALUES (?,?,?,?)', examples)
    # The app recopies its dict.db when this stamp (also in the SQLite header) changes.
    version = int(time.time())
    db.execute(f'PRAGMA user_version = {version}')
    db.commit()
    db.execute('VACUUM')
    db.close()
    open(os.path.join(os.path.dirname(path), 'dict.version'), 'w').write(f'{version}\n')


def read_cfdict(path, reading):
    """hanzi -> French senses, and hanzi -> pinyin for sentence readings. Indexed by
    simplified too (Taiwan writes 吃 where CFDICT has 喫). Among readings: the one TOCFL
    gives (喝 hē "boire", not hè "crier"), else the most senses."""
    cf, pron = {}, {}
    for line in open(path, encoding='utf-8'):
        m = re.match(r'(\S+) (\S+) \[([^\]]*)\] /(.*)/\s*$', line)
        if not m:
            continue
        proper = m[3][:1].isupper()
        for h in (m[1], m[2]):
            rank = (not proper, tones(m[3]) == reading.get(h), m[4].count('/'))
            if h not in pron or rank > pron[h][0]:
                pron[h] = rank, marked(m[3])
            if not proper and (h not in cf or rank > cf[h][0]):
                cf[h] = rank, m[4]
    return {h: d for h, (_, d) in cf.items()}, {h: p for h, (_, p) in pron.items()}


def read_tatoeba(folder):
    """Mandarin sentences with their shortest French translation, in Taiwan characters
    and vocabulary; duplicates (the same sentence in both scripts) merged."""
    from opencc import OpenCC
    cc = OpenCC('s2twp')

    def tsv(name):
        return (line.rstrip('\n').split('\t') for line in bz2.open(f'{folder}/{name}', 'rt', encoding='utf-8'))

    cmn = {int(i): s for i, _, s in tsv('cmn_sentences.tsv.bz2')}
    links = [(int(a), int(b)) for a, b in tsv('cmn-fra_links.tsv.bz2')]
    wanted = {b for _, b in links}
    fra = {int(i): s for i, _, s in tsv('fra_sentences.tsv.bz2') if int(i) in wanted}
    out = {}
    for a, b in links:
        if a not in cmn or b not in fra:
            continue
        zh = cc.convert(cmn[a].strip()).translate(str.maketrans('?!,:;', '？！，：；'))
        # Short, Han only (no names in Latin letters), common characters (no rare-glyph font).
        if not 4 <= len(zh) <= 24 or re.search(r'[A-Za-zＡ-Ｚａ-ｚ0-9０-９]', zh) \
                or any(0x3400 <= ord(c) <= 0x4DBF or ord(c) > 0xFFFF for c in zh):
            continue
        fr = fra[b].strip()
        if zh not in out or len(fr) < len(out[zh]):
            out[zh] = fr
    return out


def segment(text, vocab):
    """Greedy longest match over known words; other characters (punctuation) alone."""
    i, out = 0, []
    while i < len(text):
        n = next((n for n in range(min(6, len(text) - i), 1, -1) if text[i:i + n] in vocab), 1)
        out.append(text[i:i + n])
        i += n
    return out


def sentence_pinyin(tokens, deck_pron, pron):
    words = []
    for t in tokens:
        if t in PUNCT:
            if words:
                words[-1] += PUNCT[t]
        elif re.fullmatch(r'[一-鿿]+', t):
            p = PARTICLES.get(t) or deck_pron.get(t) or pron.get(t)
            if p is None:
                return None  # a character we can't read: skip the sentence rather than guess
            words.append(p)
        else:
            words.append(t)
    # Capitalized like a sentence: first letter, and after . ? !
    return re.sub(r'(^|[.?!] )(\w)', lambda m: m[1] + m[2].upper(), ' '.join(words))


def main(cfdict_path, tocfl_path, tatoeba_dir, out_dir):
    tocfl = list(csv.DictReader(open(tocfl_path, encoding='utf-8')))
    reading = {}
    for r in tocfl:
        for h in re.split(r'[/()]', r['Traditional']):
            if h:
                reading.setdefault(h, tones(r['Pinyin'].split('/')[0]))
    cf, pron = read_cfdict(cfdict_path, reading)

    # ---- Mandarin: essentials, then TOCFL by level.
    man, level = [], {}
    for h, py, fr, theme in MAN_ESSENTIALS:
        man.append([h, py, zhuyin(py), fr, theme])
        level[h] = 0
    for r in tocfl:
        # Variants pair each written form with its own pinyin; take the first CFDICT knows,
        # '車(子)' trying 車子 then 車.
        forms = [(v['Traditional'], v['Pinyin']) for v in json.loads(r['Variants'])] if r['Variants'] else []
        forms += [(r['Traditional'], r['Pinyin']), (r['Traditional'].split('(')[0], r['Pinyin'].split('(')[0])]
        h, py = next(((first(h), first(p)) for h, p in forms if first(h) in cf), (None, None))
        if h and h not in level:
            lv = int(r['ID'][1])
            level[h] = lv
            man.append([h, py, zhuyin(py), FR_FIX.get(h) or gloss(cf[h]), LEVELS[lv]])

    # ---- Example sentences: segmented with the deck first (Taiwan readings), then CFDICT.
    deck_pron = {r[0]: r[1] for r in man}
    vocab = set(deck_pron) | set(pron)
    sentences, by_word = [], {}
    for zh, fr in read_tatoeba(tatoeba_dir).items():
        tokens = segment(zh, vocab)
        roman = sentence_pinyin(tokens, deck_pron, pron)
        if roman is None:
            continue
        sid = len(sentences) + 1
        sentences.append((sid, zh, roman, fr))
        words = [t for t in tokens if t in vocab]
        for t in set(words):
            by_word.setdefault(t, []).append((sid, words, len(zh)))

    def hardness(words, target):
        # 0 = every other word is at most the target's level; unknown words count as 7.
        return sum(max(0, level.get(w, 7) - max(1, level[target])) for w in words if w != target)

    examples = []
    for h, *_ in man:
        found = by_word.get(h, [])
        if len(found) < 3:  # 吃 also illustrated by sentences with 吃飯
            found = found + [(sid, ws, n) for t, lst in by_word.items() if h in t and t != h for sid, ws, n in lst]
        best = sorted(found, key=lambda f: (hardness(f[1], h) > 0, hardness(f[1], h), abs(f[2] - 9), f[0]))
        seen = []
        for sid, _, _ in best:
            if sid not in seen:
                seen.append(sid)
            if len(seen) == 3:
                break
        examples += [('man', h, n, sid) for n, sid in enumerate(seen)]
    used = {sid for *_, sid in examples}
    sentences = [s for s in sentences if s[0] in used]

    write_db(f'{out_dir}/dict.db', {'man': man}, sentences, examples)
    rare = {c for r in man for c in r[0] if 0x3400 <= ord(c) <= 0x4DBF or ord(c) > 0xFFFF}
    print(f'man: {len(man)} words, {len(sentences)} sentences, '
          f'{len({h for _, h, _, _ in examples})} words with examples; rare characters: {"".join(rare) or "none"}')


if __name__ == '__main__':
    main(*sys.argv[1:5])
