"""Korean deck ('kor') for build_words.py.

Words: KOR_ESSENTIALS, then krdict's learner words by level ('1 · Débutant' 초급 … '3 · Avancé'
고급), the most frequent in Tatoeba first; homonyms are one word whose gloss lists their senses.
roman is the Revised Romanization with sound changes (koroman), zhuyin is empty.
Examples: Tatoeba pairs (direct, else through English), matched on the dictionary forms Kiwi
finds (갔어요 -> 가다).
"""

import bz2
import re

SENTENCE_LENGTH = 14  # characters: examples closest to it are preferred
UNKNOWN_LEVEL = 4  # words outside the deck count as harder than krdict's levels (1-3)

# Korean (hangul, français, thème): polite -요 forms for everyday phrases; romanization is
# generated. A form krdict also has keeps this gloss, so homonyms list their main senses.
KOR_ESSENTIALS = [
    ('안녕하세요', 'Bonjour', 'Salutations'), ('안녕히 가세요', 'Au revoir (à qui s’en va)', 'Salutations'),
    ('안녕히 계세요', 'Au revoir (à qui reste)', 'Salutations'), ('감사합니다', 'Merci', 'Salutations'),
    ('고마워요', 'Merci (moins formel)', 'Salutations'), ('죄송합니다', 'Je suis désolé(e) (formel)', 'Salutations'),
    ('미안해요', 'Pardon ; désolé(e)', 'Salutations'), ('괜찮아요', 'Ça va ; ce n’est pas grave', 'Salutations'),
    ('반갑습니다', 'Enchanté(e)', 'Salutations'), ('제 이름은', 'Je m’appelle…', 'Salutations'),
    ('잘 먹겠습니다', 'Bon appétit (avant de manger)', 'Salutations'),
    ('잘 먹었습니다', 'Merci pour le repas', 'Salutations'),
    ('네', 'Oui', 'Bases'), ('아니요', 'Non', 'Bases'), ('주세요', 'Donnez-moi, s’il vous plaît', 'Bases'),
    ('잠깐만요', 'Un instant !', 'Bases'), ('저기요', 'Excusez-moi (pour appeler)', 'Bases'),
    ('좋아요', 'C’est bien ; d’accord', 'Bases'), ('알겠어요', 'Compris', 'Bases'),
    ('몰라요', 'Je ne sais pas', 'Bases'), ('진짜요', 'Vraiment ?', 'Bases'), ('파이팅', 'Courage ! ; allez !', 'Bases'),
    ('저', 'Je ; moi (poli)', 'Personnes'), ('나', 'Je ; moi (familier)', 'Personnes'),
    ('우리', 'Nous ; notre', 'Personnes'), ('친구', 'Ami(e)', 'Personnes'), ('선생님', 'Professeur', 'Personnes'),
    ('학생', 'Étudiant(e) ; élève', 'Personnes'), ('프랑스 사람', 'Français(e)', 'Personnes'),
    ('한국', 'Corée', 'Personnes'), ('한국어', 'Le coréen (langue)', 'Personnes'), ('가족', 'Famille', 'Personnes'),
    ('있어요', 'Il y a ; j’ai', 'Verbes'), ('없어요', 'Il n’y a pas ; je n’ai pas', 'Verbes'),
    ('가요', 'Je vais ; on y va', 'Verbes'), ('와요', 'Je viens ; il vient', 'Verbes'),
    ('먹어요', 'Je mange', 'Verbes'), ('마셔요', 'Je bois', 'Verbes'), ('좋아해요', 'J’aime (bien)', 'Verbes'),
    ('해요', 'Je fais', 'Verbes'), ('봐요', 'Je regarde ; je vois', 'Verbes'), ('사요', 'J’achète', 'Verbes'),
    ('알아요', 'Je sais ; je connais', 'Verbes'), ('필요해요', 'J’en ai besoin', 'Verbes'),
    ('일', 'Un (1) ; travail ; jour', 'Nombres'), ('이', 'Deux (2) ; ce, cette ; dent', 'Nombres'),
    ('삼', 'Trois (3)', 'Nombres'), ('사', 'Quatre (4)', 'Nombres'), ('오', 'Cinq (5)', 'Nombres'),
    ('육', 'Six (6)', 'Nombres'), ('칠', 'Sept (7)', 'Nombres'), ('팔', 'Huit (8) ; bras', 'Nombres'),
    ('구', 'Neuf (9) ; arrondissement', 'Nombres'), ('십', 'Dix (10)', 'Nombres'), ('백', 'Cent (100)', 'Nombres'),
    ('천', 'Mille (1000)', 'Nombres'), ('만', 'Dix mille ; seulement', 'Nombres'),
    ('하나', 'Un (coréen natif)', 'Nombres'), ('둘', 'Deux (coréen natif)', 'Nombres'),
    ('셋', 'Trois (coréen natif)', 'Nombres'), ('원', 'Won (monnaie)', 'Nombres'),
    ('밥', 'Riz cuit ; repas', 'Nourriture'), ('김치', 'Kimchi', 'Nourriture'),
    ('비빔밥', 'Bibimbap (riz mélangé)', 'Nourriture'), ('불고기', 'Bulgogi (bœuf mariné grillé)', 'Nourriture'),
    ('떡볶이', 'Tteokbokki (gâteaux de riz épicés)', 'Nourriture'), ('라면', 'Ramyeon (nouilles instantanées)', 'Nourriture'),
    ('치킨', 'Poulet frit', 'Nourriture'), ('물', 'Eau', 'Nourriture'), ('커피', 'Café', 'Nourriture'),
    ('맥주', 'Bière', 'Nourriture'), ('맛있어요', 'C’est délicieux', 'Nourriture'),
    ('안 맵게 해 주세요', 'Pas épicé, s’il vous plaît', 'Nourriture'),
    ('포장해 주세요', 'À emporter, s’il vous plaît', 'Nourriture'), ('여기서 먹을게요', 'Sur place', 'Nourriture'),
    ('계산해 주세요', 'L’addition, s’il vous plaît', 'Nourriture'),
    ('지하철', 'Métro', 'Ville'), ('버스', 'Bus', 'Ville'), ('택시', 'Taxi', 'Ville'), ('차', 'Voiture ; thé', 'Ville'),
    ('역', 'Gare ; station', 'Ville'), ('교통카드', 'Carte de transport (T-money)', 'Ville'),
    ('편의점', 'Supérette (CU, GS25…)', 'Ville'), ('화장실', 'Toilettes', 'Ville'), ('병원', 'Hôpital', 'Ville'),
    ('약국', 'Pharmacie', 'Ville'), ('왼쪽', 'Gauche', 'Ville'), ('오른쪽', 'Droite', 'Ville'),
    ('쭉 가세요', 'Allez tout droit', 'Ville'),
    ('오늘', 'Aujourd’hui', 'Temps'), ('내일', 'Demain', 'Temps'), ('어제', 'Hier', 'Temps'),
    ('지금', 'Maintenant', 'Temps'), ('월요일', 'Lundi', 'Temps'), ('일요일', 'Dimanche', 'Temps'),
    ('몇 시예요', 'Quelle heure est-il ?', 'Temps'), ('날씨', 'La météo', 'Temps'),
    ('더워요', 'Il fait chaud', 'Temps'), ('추워요', 'Il fait froid', 'Temps'),
    ('얼마예요', 'Combien ça coûte ?', 'Phrases'), ('너무 비싸요', 'C’est trop cher', 'Phrases'),
    ('이거 주세요', 'Je voudrais ceci', 'Phrases'), ('화장실이 어디예요', 'Où sont les toilettes ?', 'Phrases'),
    ('이해 못 했어요', 'Je n’ai pas compris', 'Phrases'),
    ('다시 말해 주세요', 'Pouvez-vous répéter ?', 'Phrases'),
    ('천천히 말해 주세요', 'Parlez lentement, s’il vous plaît', 'Phrases'),
    ('한국어를 잘 못해요', 'Je parle mal coréen', 'Phrases'),
    ('저는 프랑스 사람이에요', 'Je suis français(e)', 'Phrases'),
]
KOR_LEVELS = {'초급': '1 · Débutant', '중급': '2 · Intermédiaire', '고급': '3 · Avancé'}

# Hand corrections for automatic glosses, and the beginner words whose main sense krdict gives
# no short French for (the build lists the ones still missing).
FR_FIX = {
    '구경': 'Visite (pour voir) ; spectacle', '김밥': 'Gimbap (rouleau de riz et d’algue)',
    '마리': 'Animal (classificateur)', '무슨': 'Quel ; quelle sorte de', '바다': 'Mer',
    '설렁탕': 'Seolleongtang (soupe d’os de bœuf)', '성격': 'Caractère ; personnalité',
    '시키다': 'Faire faire ; commander (au restaurant)', '아니다': 'Ne pas être', '어떻다': 'Comment (être) ; quel',
    '없다': 'Ne pas y avoir ; ne pas avoir', '울산': 'Ulsan (ville)', '인천': 'Incheon (ville)',
    '자장면': 'Jajangmyeon (nouilles à la sauce noire)', '추석': 'Chuseok (fête des récoltes)',
    '가늘다': 'Fin ; mince', '개월': 'Mois (durée)', '것': 'Chose ; ce que', '광주': 'Gwangju (ville)',
    '칼국수': 'Kalguksu (nouilles coupées au couteau)', '태극기': 'Drapeau sud-coréen',
    '퇴근': 'Sortie du travail', '푹': 'Profondément (dormir) ; bien (cuire)', '피아노': 'Piano',
    '후배': 'Cadet(te) (à l’école, au travail)', '깜짝': 'En sursaut (de surprise)', '대전': 'Daejeon (ville)',
    '드리다': 'Donner (honorifique) ; offrir', '때': 'Moment ; quand ; saleté', '말': 'Parole ; cheval ; fin (du mois)',
    '분': 'Minute ; personne (honorifique)', '올림': 'Respectueusement (en fin de lettre)', '정말': 'Vraiment',
    '제': 'Mon ; ma (poli)', '짝': 'Partenaire ; paire', '거': 'Chose (familier)', '년': 'An ; année (unité)',
    '대구': 'Daegu (ville) ; cabillaud', '못': 'Ne pas pouvoir ; clou', '부산': 'Busan (ville)',
    '씨': 'M. ; Mme (après le nom) ; graine', '인분': 'Portion (par personne)', '회': 'Poisson cru ; fois ; réunion',
    '벌': 'Tenue (classificateur) ; abeille ; punition', '중': 'Pendant ; en train de ; milieu',
    '가지': 'Sorte ; branche ; aubergine', '명': 'Personne (classificateur)', '쪽': 'Côté ; direction ; page',
    '장': 'Feuille (classificateur) ; marché', '대': 'Véhicule, machine (classificateur)',
    # Frequent words whose automatic gloss puts a rare sense forward.
    '있다': 'Il y a ; avoir ; être (quelque part)', '좋다': 'Bon ; bien ; agréable', '크다': 'Grand ; grandir',
    '어디': 'Où ; quelque part', '그렇다': 'Ainsi ; comme ça', '필요': 'Besoin ; nécessité',
    '시': 'Heure (… heures) ; ville ; poème', '번': 'Fois ; numéro', '이상': 'Plus de ; au-delà ; anomalie',
    '만나다': 'Rencontrer ; voir (quelqu’un)', '전': 'Avant ; il y a (temps)', '줄': 'Corde ; file ; ligne',
    '타다': 'Monter (dans un véhicule) ; brûler', '나다': 'Se produire ; pousser ; sortir',
    '들다': 'Entrer ; porter ; coûter', '지다': 'Perdre ; porter sur le dos ; se coucher (soleil)',
    '걸리다': 'Prendre (du temps) ; être accroché ; attraper (un rhume)', '살': 'An (âge) ; chair',
    '세': 'Trois (devant un nom) ; loyer', '월': 'Mois (… mois) ; lundi', '내': 'Mon ; ma ; je',
    '두': 'Deux (devant un nom)', '한': 'Un (devant un nom) ; environ', '이것': 'Ceci ; ça',
    '자신': 'Soi-même ; confiance en soi', '돌아가다': 'Retourner ; rentrer ; tourner',
    '피우다': 'Fumer ; faire fleurir ; allumer (un feu)', '놓다': 'Poser ; lâcher', '사이': 'Entre ; espace ; relation',
    '처음': 'Début ; première fois', '내리다': 'Descendre ; tomber (pluie, neige)', '열': 'Dix (coréen natif) ; fièvre',
}


def kor_sense(eq, main):
    """A sense's French: its lemma, else for the [main] (first) sense its definition when short
    ('Quatre jours.'), else None."""
    lemma, definition = (eq.find(f"feat[@att='{a}']") for a in ('lemma', 'definition'))
    if lemma is not None and lemma.get('val', '').strip():
        return lemma.get('val').strip()
    d = definition.get('val', '').strip().rstrip('.').replace('&quot;', '"') if definition is not None else ''
    return d if main and 0 < len(d) <= 40 else None


def read_krdict(folder):
    """krdict entries with a learner level, homonyms merged: hangul -> (level 1-3, French senses in
    order or None where it has none, semantic category), at the easiest level of its homonyms."""
    import glob
    import io
    import xml.etree.ElementTree as ET
    entries = []
    for path in glob.glob(f'{folder}/*.xml'):
        # One file has a raw '<' inside an attribute value.
        text = re.sub(r'val="[^"]*"', lambda m: m[0].replace('<', '&lt;'), open(path, encoding='utf-8').read())
        for _, e in ET.iterparse(io.StringIO(text)):
            if e.tag != 'LexicalEntry':
                continue
            feats = {f.get('att'): f.get('val') for f in e.findall('feat')}
            form = e.find('Lemma/feat').get('val').strip()
            # Words only: affixes (-님) and endings have a hyphen.
            if feats.get('vocabularyLevel') in KOR_LEVELS and re.fullmatch(r'[가-힣]+( [가-힣]+)*', form):
                fr = [next((kor_sense(q, i == 0) for q in s.findall('Equivalent')
                            if q.find("feat[@att='language']").get('val') == '프랑스어'), None)
                      for i, s in enumerate(e.findall('Sense'))]
                lv = list(KOR_LEVELS).index(feats['vocabularyLevel']) + 1
                entries.append((form, lv, int(feats.get('homonym_number') or 0), fr, feats.get('semanticCategory') or ''))
            e.clear()
    words = {}
    for form, lv, _, fr, cat in sorted(entries, key=lambda x: (x[1], x[2])):
        if form in words:
            words[form][1].append(fr)
        else:
            words[form] = (lv, [fr], cat)
    return words


def kor_gloss(homonyms, roman):
    """Each homonym's French senses ('(n.) bord, rebord', None…) -> 'Bord ; rebord ; neige': two terms of
    the main word's first sense (or one and the next sense's), then the first sense of the other
    homonyms (눈: œil, neige), three terms at most within 60 characters, without bare romanizations
    ('gye'). None when the main sense has no French: a minor one would mislead (없다 is not 'pauvre')."""
    def terms(sense):
        parts = [re.sub(r'^\([^)]{1,6}\)\s*', '', t.strip()).rstrip('.') for t in re.split(r'[,;]', sense or '')]
        return [t for t in parts if t and t.lower().replace('-', '') != roman.replace('-', '')]

    main, *others = homonyms
    first = terms(main[0]) if main else []
    if not first:
        return None
    picks = first[:2] + (terms(main[1])[:1] if len(first) == 1 and len(main) > 1 else [])
    picks += [t for h in others if h for t in terms(h[0])[:1]]
    out = []
    for t in picks:
        if not out or len(out) < 3 and t.lower() not in map(str.lower, out) and len(' ; '.join(out + [t])) <= 60:
            out.append(t)
    gloss = ' ; '.join(out)
    return gloss[0].upper() + gloss[1:]


def kor_lemmas(kiwi, text):
    """Dictionary forms in a sentence: nouns, adverbs… as written, verbs and adjectives + 다
    (갔어요 -> 가다), noun + 하/되 suffix as one verb (공부해요 -> 공부하다)."""
    toks = kiwi.tokenize(text)
    out = []
    for i, t in enumerate(toks):
        tag = t.tag.split('-')[0]  # VV-I: irregular verb
        if tag in ('VV', 'VA', 'VX'):
            out.append(t.form + '다')
        elif tag in ('XSV', 'XSA') and i and toks[i - 1].tag in ('NNG', 'XR'):
            out.append(toks[i - 1].form + t.form + '다')
        elif tag[0] in 'NM' or tag == 'IC':
            out.append(t.form)
    return out


def read_tatoeba_kor(folder):
    """Korean sentences -> their shortest French translation, direct, else through an English one."""
    def tsv(name):
        return (line.rstrip('\n').split('\t') for line in bz2.open(f'{folder}/{name}', 'rt', encoding='utf-8'))

    kor = {int(i): s.strip() for i, _, s in tsv('kor_sentences.tsv.bz2')}
    direct = [(int(a), int(b)) for a, b in tsv('kor-fra_links.tsv.bz2')]
    eng = {}
    for a, b in tsv('kor-eng_links.tsv.bz2'):
        eng.setdefault(int(b), []).append(int(a))
    via = [(k, int(f)) for e, f in tsv('eng-fra_links.tsv.bz2') if int(e) in eng for k in eng[int(e)]]
    wanted = {b for _, b in direct + via}
    fra = {int(i): s.strip() for i, _, s in tsv('fra_sentences.tsv.bz2') if int(i) in wanted}
    out = {}
    for links in (direct, via):
        found = {}
        for a, b in links:
            # Short, hangul only (no latin names, digits or hanja).
            ko = kor.get(a, '')
            if b in fra and 4 <= len(ko) <= 30 and re.fullmatch(r'[가-힣 .,?!~"\'’…]+', ko) and ko not in out:
                if ko not in found or len(fra[b]) < len(found[ko]):
                    found[ko] = fra[b]
        out.update(found)
    return out, list(kor.values())


def build(krdict_dir, tatoeba_dir):
    """The deck, as build_words.py expects it."""
    from kiwipiepy import Kiwi
    from koroman import romanize
    kiwi = Kiwi()
    pairs, every = read_tatoeba_kor(tatoeba_dir)
    # Order inside a level: most frequent in Tatoeba's Korean first, then by theme.
    freq = {}
    for s in every:
        for w in set(kor_lemmas(kiwi, s)):
            freq[w] = freq.get(w, 0) + 1

    kor, level = [], {}
    for h, fr, theme in KOR_ESSENTIALS:
        kor.append([h, romanize(h), '', fr, theme])
        level[h] = 0
    dic = read_krdict(krdict_dir)
    for h, (lv, fr, _) in sorted(dic.items(), key=lambda x: (x[1][0], -freq.get(x[0], 0), x[1][2] or '~', x[0])):
        roman = romanize(h)
        gl = FR_FIX.get(h) or kor_gloss(fr, roman)
        if h not in level and gl:
            level[h] = lv
            kor.append([h, roman, '', gl, KOR_LEVELS[list(KOR_LEVELS)[lv - 1]]])
    missing = [h for h, (lv, fr, _) in dic.items() if lv == 1 and h not in level]
    if missing:
        print(f'kor: beginner words dropped for want of a French gloss (add them to FR_FIX): {" ".join(missing)}')

    sentences, by_word, lemmas = [], {}, {}
    for ko, fr in pairs.items():
        sid = len(sentences) + 1
        roman = re.sub(r'(^|[.?!] )(\w)', lambda m: m[1] + m[2].upper(), romanize(ko))
        sentences.append((sid, ko, roman, fr))
        lemmas[sid] = words = kor_lemmas(kiwi, ko)
        for w in set(words) & level.keys():
            by_word.setdefault(w, []).append((sid, words, len(ko)))

    candidates = {}
    for h, *_ in kor:
        found = by_word.get(h, [])
        if len(found) < 3 and len(h) > 1:  # set phrases (안녕하세요) as written
            found = found + [(sid, lemmas[sid], len(ko)) for sid, ko, _, _ in sentences if h in ko]
        candidates[h] = found
    return kor, level, sentences, candidates
