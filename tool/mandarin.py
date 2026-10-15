"""Taiwan Mandarin deck ('man') for build_words.py.

Words: MAN_ESSENTIALS, then the TOCFL list ('1 · Débutant' … '6 · Expert') with CFDICT glosses.
The CFDICT reading is chosen to match TOCFL's pinyin (letters and tones); zhuyin is derived.
Examples: Tatoeba Mandarin–French pairs converted to Taiwan characters and vocabulary (OpenCC
s2twp), segmented with the deck (Taiwan readings) then CFDICT; sentences with a character it
can't read are dropped rather than guessed.
Characters (chars): how each one is built, from Make Me a Hanzi (kind pictographic / ideographic /
pictophonetic, its components, the meaning and sound components, an English hint), and its
readings 'pinyin<TAB>French gloss' one per line, from CFDICT, else RADICALS for radical forms,
else '(en) ' + the English one.
"""

import bz2
import csv
import json
import re
import unicodedata

SENTENCE_LENGTH = 9  # characters: examples closest to it are preferred
UNKNOWN_LEVEL = 7  # words outside the deck count as harder than TOCFL's levels (0-5)

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

# Hand corrections for CFDICT glosses: hanzi -> French.
FR_FIX = {}

# Readings for sentence pinyin where a character alone is usually a particle, not its
# dictionary-first reading (的 de, not dí).
PARTICLES = {'的': 'de', '了': 'le', '著': 'zhe', '得': 'de', '個': 'ge', '們': 'men', '嗎': 'ma', '呢': 'ne',
             '吧': 'ba', '啊': 'a', '呀': 'ya', '喔': 'o', '啦': 'la'}

# French for radical forms and components CFDICT doesn't have as characters.
RADICALS = {
    '扌': 'main', '辶': 'marcher', '糹': 'soie ; fil', '纟': 'soie ; fil', '⺼': 'chair ; corps', '忄': 'cœur ; sentiment',
    '阝': 'colline (à gauche) ; ville (à droite)', '釒': 'métal', '钅': 'métal', '刂': 'couteau', '⺈': 'couteau',
    '广': 'abri ; bâtiment', '犭': 'chien ; animal', '丷': 'deux points', '尸': 'corps ; cadavre', '飠': 'nourriture ; manger',
    '饣': 'nourriture ; manger', '罒': 'filet', '衤': 'vêtement', '儿': 'enfant ; jambes', '厂': 'falaise ; abri',
    '礻': 'autel ; esprit', '户': 'porte', '乚': 'crochet', '爿': 'planche', '爫': 'griffe ; main', '氵': 'eau',
    '亻': 'personne', '讠': 'parole', '艹': 'herbe', '⺌': 'petit', '耂': 'vieux', '巛': 'rivière', '覀': 'couvrir',
    '冫': 'glace', '疒': 'maladie', '癶': 'pieds', '彳': 'pas', '攵': 'frapper ; action', '夂': 'marcher lentement',
    '卩': 'sceau', '㔾': 'sceau', '匚': 'boîte', '勹': 'envelopper', '彡': 'poils ; ornement', '廴': 'avancer',
    '亠': 'couvercle', '冖': 'couvercle', '宀': 'toit', '灬': 'feu', '丶': 'point', '丿': 'trait', '亅': 'crochet',
    '冂': 'enceinte', '凵': 'récipient', '厶': 'privé', '囗': 'enclos', '⺊': 'divination', '龶': 'pousse',
    '⺮': 'bambou', '𥫗': 'bambou', '⺶': 'mouton', '⺧': 'bœuf', '牜': 'bœuf', '⺗': 'cœur', '⺆': 'enceinte',
    '𠂉': 'homme', '⺄': 'second', '⺝': 'lune ; mois', '⻊': 'pied', '𧾷': 'pied', '⻌': 'marcher', '⻏': 'ville',
    '⻖': 'colline', '⺣': 'feu', '⺡': 'eau', '⺅': 'personne', '⺘': 'main', '⺖': 'cœur', '⺾': 'herbe',
    '果': 'fruit ; résultat', '周': 'tour ; semaine', '台': 'plateforme ; Taïwan',
}
IDC = '⿰⿱⿲⿳⿴⿵⿶⿷⿸⿹⿺⿻'

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


def parts(ids):
    """'⿰女子' -> ['女', '子']: the top-level components of an ideographic description; one
    without a character of its own is replaced by its pieces, unknown ones (？) dropped."""
    pos = 0

    def node():
        nonlocal pos
        c = ids[pos]
        pos += 1
        return [node() for _ in range(3 if c in '⿲⿳' else 2)] if c in IDC else c

    def leaves(n):
        return [n] if isinstance(n, str) else [x for c in n for x in leaves(c)]

    try:
        tree = node()
    except IndexError:
        tree = list(ids)
    out = [] if isinstance(tree, str) else [x for c in tree for x in leaves(c)]
    return [c for c in out if c not in IDC and c != '？']


def chars(cfdict_path, mmah_path):
    """The chars table: (hanzi, kind, parts, semantic, phonetic, hint, readings) rows."""
    readings = {}  # hanzi -> {pinyin: French}, traditional entries before simplified ones
    for pass_ in (0, 1):
        for line in open(cfdict_path, encoding='utf-8'):
            m = re.match(r'(\S+) (\S+) \[([^\]]*)\] /(.*)/\s*$', line)
            if m and len(m[pass_ + 1]) == 1 and not m[3][:1].isupper():
                readings.setdefault(m[pass_ + 1], {}).setdefault(marked(m[3]), gloss(m[4]))
    mmah = {j['character']: j for j in map(json.loads, open(mmah_path, encoding='utf-8'))}
    rows = {}
    for c, j in mmah.items():
        e = j.get('etymology') or {}
        ps = parts(j.get('decomposition', ''))
        rows[c] = [e.get('type', ''), ''.join(ps), e.get('semantic', ''), e.get('phonetic', ''), e.get('hint', '')]
        for p in ps + [e.get('semantic', ''), e.get('phonetic', '')]:
            if p and p not in mmah:
                rows.setdefault(p, ['', '', '', '', ''])

    def reading(c):
        if c in RADICALS:
            return f'{"/".join(mmah.get(c, {}).get("pinyin", []))}\t{RADICALS[c]}'
        if c in readings:
            return '\n'.join(f'{p}\t{fr}' for p, fr in readings[c].items())
        j = mmah.get(c, {})
        return f'{"/".join(j.get("pinyin", []))}\t(en) {j["definition"]}' if j.get('definition') else ''

    rows = [(c, *r, reading(c)) for c, r in rows.items()]
    print(f'chars: {len(rows)}, {sum(1 for r in rows if not r[-1])} without a reading')
    return rows


def build(cfdict_path, tocfl_path, tatoeba_dir):
    """The deck, as build_words.py expects it."""
    tocfl = list(csv.DictReader(open(tocfl_path, encoding='utf-8')))
    reading = {}
    for r in tocfl:
        for h in re.split(r'[/()]', r['Traditional']):
            if h:
                reading.setdefault(h, tones(r['Pinyin'].split('/')[0]))
    cf, pron = read_cfdict(cfdict_path, reading)

    # ---- Words: essentials, then TOCFL by level.
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

    candidates = {}
    for h in level:
        found = by_word.get(h, [])
        if len(found) < 3:  # 吃 also illustrated by sentences with 吃飯
            found = found + [(sid, ws, n) for t, lst in by_word.items() if h in t and t != h for sid, ws, n in lst]
        candidates[h] = found
    rare = {c for r in man for c in r[0] if 0x3400 <= ord(c) <= 0x4DBF or ord(c) > 0xFFFF}
    print(f'man: rare characters: {"".join(rare) or "none"}')
    return man, level, sentences, candidates
