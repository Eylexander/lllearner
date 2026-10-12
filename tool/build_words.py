"""Builds assets/dict.db, the read-only SQLite dictionary: Taiwanese Hokkien (hok) and
Taiwan Mandarin (man) decks, plus the MOE dictionary's definitions and example sentences.

Sources (download into a scratch dir, then pass the paths):
  curl -LO https://sutian.moe.edu.tw/media/senn/ods/kautian.ods    # MOE 臺灣台語常用詞辭典, CC BY-ND 3.0 TW
  python tool/build_words.py --ods kautian.ods <dir>                 # dumps its sheets to <dir>/*.csv
  curl -LO https://chine.in/assets/cfdict/cfdict.u8                 # CFDICT, CC BY-SA 3.0
  curl -LO https://raw.githubusercontent.com/ivankra/tocfl/master/tocfl-202307.csv
  pip install dragonmapper                                           # pinyin -> zhuyin
  python tool/build_words.py <dir> cfdict.u8 tocfl-202307.csv assets/

Rare characters (CJK Ext-A/B such as 𠢕 𪜶) are missing from Android's CJK font, so
the app bundles them as a fallback font cut from jf open huninn (OFL, needs fonttools):
  curl -LO https://github.com/justfont/open-huninn-font/releases/download/v2.1/jf-openhuninn-2.1.ttf
  python tool/build_words.py --font jf-openhuninn-2.1.ttf assets/fonts/rare_han.ttf

Tables: words(lang, pos, hanzi, roman, zhuyin, fr, tag, audio, see, moe, short) in study
order (pos); defs(moe, text); examples(moe, n, hanji, roman, zh). moe is the MOE entry id
(= headword audio id, = sutian.moe.edu.tw/zh-hant/su/<moe>/), 0 for Mandarin.
roman is Tâi-lô (hok) or pinyin (man); zhuyin only for man. fr is '' for the ~17k hok
words without a reliable French gloss: short (first Mandarin definition) stands in. audio (hok only) is a MOE
recording path under https://sutian.moe.edu.tw/media/senn/mp3/imtong/<audio>.mp3:
'subak/<id // 1000>/<id>' for headwords, 'leku/…' for example sentences (found on the
word's page, e.g. su/1653). see = the other language's equivalent, "謝謝 xièxie".

Hokkien: the MOE dictionary has no French, so each word gets the CFDICT gloss of the
Mandarin synonyms its first definition starts with (啉: 「喝、飲。」) and is ranked by
their TOCFL level; the others follow as '7 · Dictionnaire'. Mandarin: the TOCFL list with CFDICT glosses, levels as given.
Each language starts with hand-written essentials; FR_FIX corrects automatic glosses.
"""

import collections
import csv
import json
import re
import sys
import unicodedata
import zipfile
import xml.etree.ElementTree as ET

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

# Hokkien (hanji, français, thème[, tâi-lô[, audio]]): Tâi-lô and audio come from the MOE
# dictionary. The optional tâi-lô picks the reading (行 kiânn, not hâng); for phrases
# the dictionary lacks it is used as-is, with the optional audio path (else silent).
HOK_ESSENTIALS = [
    ('𠢕早', 'Bonjour (le matin)', 'Salutations'),
    ('你好', 'Bonjour (formule moderne)', 'Salutations', 'lí hó'),
    ('你食飽未？', 'Bonjour ! (litt. « as-tu mangé ? »)', 'Salutations', 'Lí tsia̍h-pá--buē?', 'leku/47/47190'),
    ('你好無？', 'Comment vas-tu ?', 'Salutations', 'Lí hó--bô?'),
    ('逐家好', 'Bonjour à tous', 'Salutations', 'ta̍k-ke hó'),
    ('好久無看', 'Ça fait longtemps !', 'Salutations', 'hó-kú bô khuànn'),
    ('暗安', 'Bonne nuit ; bonsoir', 'Salutations'),
    ('再會', 'Au revoir', 'Salutations'), ('慢行', 'Au revoir (à qqn qui part)', 'Salutations'),
    ('多謝', 'Merci', 'Salutations'), ('感謝', 'Remercier ; merci beaucoup', 'Salutations'),
    ('毋免客氣', 'De rien ; je vous en prie', 'Salutations', 'm̄-bián kheh-khì'),
    ('歹勢', 'Pardon ; excusez-moi', 'Salutations'), ('失禮', 'Excusez-moi (poli) ; pardon', 'Salutations'),
    ('無要緊', "Ce n'est pas grave", 'Salutations'),
    ('請問', 'Excusez-moi, puis-je demander…', 'Salutations'), ('借問', 'Pardon, une question…', 'Salutations'),
    ('歡迎', 'Bienvenue', 'Salutations'), ('請坐', 'Asseyez-vous, je vous prie', 'Salutations'),
    ('我叫', "Je m'appelle…", 'Salutations', 'guá kiò'),
    ('熟似', 'Faire connaissance ; se connaître', 'Salutations'),
    ('是', 'Être ; oui', 'Bases'), ('毋是', "Non ; ce n'est pas", 'Bases'), ('好', 'Bien ; d’accord', 'Bases'),
    ('有', 'Avoir ; il y a', 'Bases'), ('無', 'Ne pas avoir ; non', 'Bases'), ('知影', 'Savoir', 'Bases'),
    ('會使', 'Pouvoir (permission)', 'Bases'), ('袂使', 'Ne pas pouvoir ; interdit', 'Bases'),
    ('欲', 'Vouloir ; aller (futur)', 'Bases'), ('愛', 'Aimer ; devoir', 'Bases'),
    ('真', 'Très ; vraiment', 'Bases'), ('足', 'Très (familier)', 'Bases'), ('媠', 'Beau ; joli', 'Bases'),
    ('臺語', 'Le taïwanais (langue)', 'Bases', 'Tâi-gí'), ('臺灣', 'Taïwan', 'Bases', 'Tâi-uân'),
    ('法國', 'France', 'Bases', 'Huat-kok'),
    ('我', 'Je ; moi', 'Personnes'), ('你', 'Tu ; toi', 'Personnes'), ('伊', 'Il ; elle', 'Personnes'),
    ('阮', 'Nous (sans toi)', 'Personnes'), ('咱', 'Nous (avec toi)', 'Personnes'), ('恁', 'Vous', 'Personnes'),
    ('𪜶', 'Ils ; elles', 'Personnes'), ('朋友', 'Ami(e)', 'Personnes'), ('老師', 'Professeur', 'Personnes'),
    ('學生', 'Élève ; étudiant', 'Personnes'), ('頭家', 'Patron ; commerçant', 'Personnes'),
    ('囡仔', 'Enfant', 'Personnes'), ('阿爸', 'Papa', 'Personnes'), ('阿母', 'Maman', 'Personnes'),
    ('阿公', 'Grand-père', 'Personnes'), ('阿媽', 'Grand-mère', 'Personnes'),
    ('翁', 'Mari', 'Personnes'), ('某', 'Épouse', 'Personnes'),
    ('啥物', 'Quoi ; quel', 'Questions'), ('啥人', 'Qui', 'Questions'), ('佗位', 'Où', 'Questions'),
    ('按怎', 'Comment ; pourquoi', 'Questions'), ('偌濟', 'Combien', 'Questions'), ('幾', 'Combien (petit nombre)', 'Questions'),
    ('食', 'Manger', 'Verbes'), ('啉', 'Boire', 'Verbes'), ('去', 'Aller', 'Verbes'), ('來', 'Venir', 'Verbes'),
    ('看', 'Regarder ; voir', 'Verbes'), ('講', 'Parler ; dire', 'Verbes'), ('聽', 'Écouter', 'Verbes'),
    ('買', 'Acheter', 'Verbes'), ('賣', 'Vendre', 'Verbes'), ('行', 'Marcher', 'Verbes', 'kiânn'), ('坐', "S'asseoir", 'Verbes'),
    ('睏', 'Dormir', 'Verbes'), ('做', 'Faire', 'Verbes'), ('學', 'Apprendre', 'Verbes'), ('寫', 'Écrire', 'Verbes'),
    ('讀冊', 'Étudier', 'Verbes'), ('等', 'Attendre', 'Verbes'), ('揣', 'Chercher', 'Verbes'),
    ('予', 'Donner', 'Verbes'), ('提', 'Prendre ; tenir', 'Verbes'), ('轉去', 'Rentrer', 'Verbes'),
    ('一', 'Un (1)', 'Nombres'), ('二', 'Deux (2, en comptant)', 'Nombres'), ('兩', 'Deux (devant un classificateur)', 'Nombres', 'nn̄g'),
    ('三', 'Trois (3)', 'Nombres'), ('四', 'Quatre (4)', 'Nombres'), ('五', 'Cinq (5)', 'Nombres'),
    ('六', 'Six (6)', 'Nombres'), ('七', 'Sept (7)', 'Nombres'), ('八', 'Huit (8)', 'Nombres'),
    ('九', 'Neuf (9)', 'Nombres'), ('十', 'Dix (10)', 'Nombres'), ('百', 'Cent', 'Nombres'),
    ('千', 'Mille', 'Nombres'), ('萬', 'Dix mille', 'Nombres'), ('箍', 'Dollar (unité monétaire)', 'Nombres'),
    ('飯', 'Riz cuit ; repas', 'Nourriture'), ('糜', 'Bouillie de riz', 'Nourriture'), ('水', 'Eau', 'Nourriture'),
    ('茶', 'Thé', 'Nourriture'), ('咖啡', 'Café', 'Nourriture'), ('麵', 'Nouilles', 'Nourriture'),
    ('肉', 'Viande', 'Nourriture'), ('魚', 'Poisson', 'Nourriture'), ('菜', 'Légume ; plat', 'Nourriture'),
    ('果子', 'Fruit', 'Nourriture'), ('早頓', 'Petit-déjeuner', 'Nourriture'), ('中晝頓', 'Déjeuner', 'Nourriture'),
    ('暗頓', 'Dîner', 'Nourriture'), ('夜市', 'Marché de nuit', 'Nourriture'), ('便當', 'Bento', 'Nourriture'),
    ('好食', 'Délicieux', 'Nourriture', 'hó-tsia̍h'), ('枵', 'Avoir faim', 'Nourriture'), ('飽', 'Rassasié', 'Nourriture'),
    ('厝', 'Maison', 'Lieux'), ('學校', 'École', 'Lieux'), ('病院', 'Hôpital', 'Lieux'), ('便所', 'Toilettes', 'Lieux'),
    ('車頭', 'Gare', 'Lieux'), ('火車', 'Train', 'Lieux'), ('路', 'Route ; chemin', 'Lieux'),
    ('倒手爿', 'Côté gauche', 'Lieux'), ('正手爿', 'Côté droit', 'Lieux'), ('頭前', 'Devant', 'Lieux'),
    ('後壁', 'Derrière', 'Lieux'), ('遮', 'Ici', 'Lieux'), ('遐', 'Là-bas', 'Lieux'),
    ('今仔日', "Aujourd'hui", 'Temps'), ('明仔載', 'Demain', 'Temps'), ('昨昏', 'Hier', 'Temps'),
    ('這馬', 'Maintenant', 'Temps'), ('早起', 'Matin', 'Temps'), ('下晡', 'Après-midi', 'Temps'),
    ('暗時', 'Soir', 'Temps'), ('禮拜', 'Semaine ; dimanche', 'Temps'), ('落雨', 'Pleuvoir', 'Temps'),
    ('大', 'Grand', 'Adjectifs', 'tuā'), ('細', 'Petit', 'Adjectifs'), ('熱', 'Chaud', 'Adjectifs'), ('寒', 'Froid', 'Adjectifs'),
    ('貴', 'Cher', 'Adjectifs'), ('俗', 'Bon marché', 'Adjectifs'), ('濟', 'Beaucoup', 'Adjectifs'), ('少', 'Peu', 'Adjectifs'),
    ('新', 'Nouveau', 'Adjectifs'), ('舊', 'Vieux (objet)', 'Adjectifs'), ('歡喜', 'Content ; heureux', 'Adjectifs'),
    ('忝', 'Fatigué ; épuisé', 'Adjectifs'),
]

# Mandarin equivalents where the automatic link (from definitions) is missing or weak.
HOK_LINKS = {'你好': '你好', '毋免客氣': '不客氣', '我叫': '我叫', '臺灣': '台灣', '𠢕早': '早安', '暗安': '晚安',
             '再會': '再見', '歹勢': '不好意思', '無要緊': '沒關係', '請問': '請問', '歡迎': '歡迎', '食': '吃', '啉': '喝'}

# Hand corrections for automatic (Hokkien) glosses that are wrong (checked on the first levels).
FR_FIX = {
    '古早': "Autrefois ; d'antan",
    '所在': 'Endroit ; lieu',
    '會': 'Pouvoir ; savoir (faire) ; (futur)',
    '頭': 'Tête',
    '較早': 'Avant ; autrefois',
    '分': 'Partager ; distribuer ; donner',
    '出': 'Sortir',
    '正': 'Droit ; correct ; principal',
    '再': 'De nouveau ; encore',
    '冷': 'Froid ; frais',
    '每': 'Chaque',
    '見': 'Voir ; rencontrer',
    '能': 'Capacité ; pouvoir',
    '偌': 'Combien ; à quel point',
    '張': 'Préparer ; (classificateur des objets plats)',
    '報': 'Annoncer ; informer',
    '畫': 'Dessiner ; peindre',
    '著': 'Correct ; juste ; atteindre',
    '開': 'Ouvrir ; dépenser',
    '想': 'Penser ; réfléchir',
    '矮': 'Petit (de taille) ; bas',
    '對': 'Correct ; envers ; depuis',
    '說': 'Expliquer ; dire',
    '課': 'Cours ; leçon',
    '談': 'Discuter ; parler',
    '請': 'Inviter ; offrir (un repas)',
    '錢': 'Argent ; monnaie',
    '難': 'Difficile',
    '也是': 'Aussi ; également',
    '工藝': 'Artisanat ; travail manuel',
    '內部': 'Intérieur ; interne',
    '日子': 'Jours ; vie quotidienne',
    '加減': 'Plus ou moins ; un peu quand même',
    '外頭': 'Dehors ; extérieur',
    '目前': 'Actuellement ; à présent',
    '地頭': 'Lieu ; endroit',
    '作業': 'Devoirs (scolaires) ; travail',
    '尾溜': 'Queue ; fin',
    '角勢': 'Coin ; endroit',
    '走路': "S'enfuir ; prendre la fuite",
    '明白': 'Comprendre ; clair',
    '停睏': 'Se reposer ; faire une pause',
    '測驗': 'Test ; examen',
    '猶閣': 'Encore ; toujours',
    '檢定': 'Examen ; certification',
    '燒酒': 'Alcool',
    '著愛': 'Il faut ; devoir',
    '多少': 'Plus ou moins ; un peu',
    '中央': 'Milieu ; centre',
    '重': 'Lourd',
    '付': 'Payer ; remettre',
    '仿': 'Imiter ; ressembler à',
    '形': 'Forme',
    '並': 'Comparer',
    '放': 'Lâcher ; poser ; libérer',
    '將': "Prendre (marque l'objet)",
    '牽': 'Tirer ; tenir par la main ; mener',
    '越': 'Se retourner ; tourner',
    '才調': 'Talent ; capacité',
    '比賽': 'Compétition ; concourir',
    '事件': 'Événement ; affaire',
    '其他': 'Autre(s)',
    '奇怪': 'Étrange ; bizarre',
    '所有': 'Tout ; tous les',
    '攢': 'Préparer',
    '叉': 'Fourche ; bifurcation',
    '接': 'Recevoir ; accueillir',
    '紲': 'Ensuite ; continuer',
    '對不住': 'Pardon ; désolé',
    '應該然': "Évidemment ; c'est normal",
    '叫': 'Appeler ; crier ; commander',
    '綴': 'Suivre',
    '邊': 'Côté ; bord',
}

NOISE = re.compile(r'^(variante|voir |cf\.|CL:|nom de famille|abr[ée]v|forme ancienne|\(?arch)|\((argot|vulg|péj)', re.I)


def dump_ods(src, out):
    """Each sheet of an .ods to <out>/<sheet>.csv, stdlib only."""
    ns = {'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0', 'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'}
    t, value = '{%s}' % ns['table'], '{urn:oasis:names:tc:opendocument:xmlns:office:1.0}value'
    for sheet in ET.fromstring(zipfile.ZipFile(src).read('content.xml')).iter(t + 'table'):
        rows = []
        for row in sheet.iter(t + 'table-row'):
            cells = []
            for c in row.findall(t + 'table-cell'):
                text = '\n'.join(''.join(p.itertext()) for p in c.findall('text:p', ns)) or c.get(value, '')
                cells += [text] * min(int(c.get(t + 'number-columns-repeated', 1)), 50)
            while cells and not cells[-1]:
                cells.pop()
            if cells:
                rows.append(cells)
        csv.writer(open(f'{out}/{sheet.get(t + "name")}.csv', 'w', encoding='utf-8')).writerows(rows)


def rare_font(src, out):
    """Keeps only CJK Ext-A and supplementary-plane glyphs, renamed: the OFL forbids
    modified versions from using the reserved names 'open huninn' / 'huninn'."""
    from fontTools import subset
    from fontTools.ttLib import TTFont
    font = TTFont(src)
    keep = [c for c in font.getBestCmap() if 0x3400 <= c <= 0x4DBF or c > 0xFFFF]
    sub = subset.Subsetter(subset.Options(name_IDs=['*'], name_languages=['*'], notdef_outline=True))
    sub.populate(unicodes=keep)
    sub.subset(font)
    for n in font['name'].names:
        if n.nameID in (1, 3, 4, 6, 16, 17):
            n.string = {6: 'LLLearnerRareHan'}.get(n.nameID, 'LLLearner Rare Han')
    font.save(out)
    print(f'{len(keep)} glyphs kept')


def tones(pinyin):
    """'dà' or 'da4' -> 'da4' (letters, then tones); neutral tones dropped so both notations compare."""
    marks = {'\u0304': '1', '\u0301': '2', '\u030c': '3', '\u0300': '4'}
    p = unicodedata.normalize('NFD', pinyin.lower().replace('u:', 'ü'))
    return ''.join(c for c in p if c.isalpha()) + ''.join(marks.get(c, c if c in '1234' else '') for c in p)


def zhuyin(pinyin):
    from dragonmapper.transcriptions import pinyin_to_zhuyin
    z = pinyin_to_zhuyin(pinyin.lower().replace(' ', ''))  # keep ' : wǎn'ān, not wǎ-nān
    # Taiwan convention: neutral-tone dot before the syllable; erhua ㄦ untoned.
    return re.sub(r'(\S+)˙', r'˙\1', z).replace('˙ㄦ', 'ㄦ')


def first(s):
    return s.split('/')[0].replace('(', '').replace(')', '').strip()


def write_db(path, decks, defs, examples):
    import os
    import sqlite3
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.executescript('''
        CREATE TABLE words(lang TEXT, pos INTEGER, hanzi TEXT, roman TEXT, zhuyin TEXT, fr TEXT, tag TEXT,
                           audio TEXT, see TEXT, moe INTEGER, short TEXT, PRIMARY KEY(lang, pos));
        CREATE TABLE defs(moe INTEGER PRIMARY KEY, text TEXT);
        CREATE TABLE examples(moe INTEGER, n INTEGER, hanji TEXT, roman TEXT, zh TEXT);
        CREATE INDEX examples_moe ON examples(moe);
    ''')
    for lang, rows in decks.items():
        db.executemany('INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?,?)', [(lang, i, *r) for i, r in enumerate(rows)])
    db.executemany('INSERT INTO defs VALUES (?,?)', defs.items())
    db.executemany('INSERT INTO examples VALUES (?,?,?,?,?)', examples)
    # The app recopies its dict.db when this stamp (also in the SQLite header) changes.
    import time
    version = int(time.time())
    db.execute(f'PRAGMA user_version = {version}')
    db.commit()
    db.execute('VACUUM')
    db.close()
    open(os.path.join(os.path.dirname(path), 'dict.version'), 'w').write(f'{version}\n')


def clean(s):
    return re.sub(r'【.*?】', '', s or '').strip()


def gloss(defs):
    senses = [d.strip() for d in defs.split('/') if d.strip()]
    good = [d for d in senses if not NOISE.search(d)] or senses
    out = good[0]
    for d in good[1:3]:
        if len(out) + len(d) > 60:
            break
        out += ' ; ' + d
    return out[0].upper() + out[1:]


def main(sheets, cfdict_path, tocfl_path, out_dir):
    def read(name):
        return csv.DictReader(open(f'{sheets}/{name}.csv', encoding='utf-8'))

    tocfl = list(csv.DictReader(open(tocfl_path, encoding='utf-8')))
    level, reading = {}, {}
    for r in tocfl:
        for h in re.split(r'[/()]', r['Traditional']):
            if h:
                level.setdefault(h, int(r['ID'][1]))
                reading.setdefault(h, tones(r['Pinyin'].split('/')[0]))
    # Mandarin -> French. Indexed by simplified too (Taiwan writes 吃 where CFDICT has 喫).
    # Among readings: the one TOCFL gives (喝 hē "boire", not hè "crier"), else the most senses.
    cf = {}
    for line in open(cfdict_path, encoding='utf-8'):
        m = re.match(r'(\S+) (\S+) \[([^\]]*)\] /(.*)/\s*$', line)
        if m and not m[3][:1].isupper():
            for h in (m[1], m[2]):
                rank = (tones(m[3]) == reading.get(h), m[4].count('/'))
                if h not in cf or rank > cf[h][0]:
                    cf[h] = rank, m[4]
    cf = {h: defs for h, (_, defs) in cf.items()}

    # ---- Mandarin: essentials, then TOCFL by level.
    man, man_seen = [], set()
    for h, py, fr, theme in MAN_ESSENTIALS:
        man.append([h, py, zhuyin(py), fr, theme, '', '', 0, ''])
        man_seen.add(h)
    for r in tocfl:
        # Variants pair each written form with its own pinyin; take the first CFDICT knows,
        # '車(子)' trying 車子 then 車.
        forms = [(v['Traditional'], v['Pinyin']) for v in json.loads(r['Variants'])] if r['Variants'] else []
        forms += [(r['Traditional'], r['Pinyin']), (r['Traditional'].split('(')[0], r['Pinyin'].split('(')[0])]
        h, py = next(((first(h), first(p)) for h, p in forms if first(h) in cf), (None, None))
        if h and h not in man_seen:
            man_seen.add(h)
            man.append([h, py, zhuyin(py), gloss(cf[h]), LEVELS[int(r['ID'][1])], '', '', 0, ''])

    # ---- Hokkien: essentials, then dictionary words ranked by Mandarin level.
    entries = [e for e in read('詞目') if e['詞目類型'] in ('主詞目', '臺華共同詞')]
    first_sense, defs = {}, collections.defaultdict(list)
    for r in read('義項'):
        first_sense.setdefault(r['詞目id'], r['解說'])
        defs[r['詞目id']].append(f"({r['詞性']}) {r['解說']}" if r['詞性'] else r['解說'])
    mandarin = collections.defaultdict(list)  # (hanji, tâi-lô) -> Mandarin equivalents
    accents = collections.defaultdict(set)  # ... -> which of the 10 surveyed accents use it
    for r in read('詞彙比較'):
        mandarin[clean(r['漢字']), r['羅馬字']].append(r['華語詞目'])
        accents[clean(r['漢字']), r['羅馬字']].add(r['腔'])

    def synonyms(e):
        """Mandarin synonyms when the first definition is a plain list (啉: 「喝、飲。」);
        descriptive ones (下: 「指空間位置「上」的相反。」) would pick the wrong word."""
        d = first_sense.get(e['詞目id'], '')
        syn = re.split('、', d[:-1]) if re.fullmatch(r'[^、。，「」（）]{1,4}(、[^、。，「」（）]{1,4})*。', d) else []
        return syn + ([clean(e['漢字'])] if e['詞目類型'] == '臺華共同詞' else [])

    def word(e, fr, tag):
        audio = (e['羅馬字音檔檔名'] or '').split('(')[0]
        # The comparison table pairs too loosely (下 ↔ 上) for links; definitions only.
        link = HOK_LINKS.get(clean(e['漢字'])) or next((c for c in synonyms(e) if c in man_seen), '')
        short = first_sense.get(e['詞目id'], '').rstrip('。')
        return [clean(e['漢字']), clean(e['羅馬字']), '', fr, tag, audio and f'subak/{int(audio) // 1000}/{audio}', link,
                int(e['詞目id']), short[:40] + ('…' if len(short) > 40 else '')]

    by_hanji = {}
    for e in entries:  # literary 【文】 readings only when there is no other
        h = clean(e['漢字'])
        if h not in by_hanji or '【文】' in by_hanji[h]['羅馬字']:
            by_hanji[h] = e

    hok, seen = [], set()
    by_reading = {(clean(e['漢字']), r): e for e in entries for r in clean(e['羅馬字']).split('/')}
    for h, fr, theme, *extra in HOK_ESSENTIALS:
        tailo, audio = (extra + ['', ''])[:2]
        e = by_reading.get((h, tailo)) if tailo else by_hanji.get(h)
        if not e and not tailo:
            sys.exit(f'essential word not in the MOE dictionary: {h}')
        hok.append(word(e, fr, theme) if e else [h, tailo, '', fr, theme, audio, HOK_LINKS.get(h, ''), 0, ''])
        seen.add(h)

    ranked, rest = [], []
    for e in by_hanji.values():
        h = clean(e['漢字'])
        if h in seen or not e['羅馬字音檔檔名']:
            continue
        readings = clean(e['羅馬字']).split('/')
        core = [m for r in readings for m in mandarin[h, r]]
        spread = len(set().union(*(accents[h, r] for r in readings)))
        # French only from the word's own definition; the comparison table only ranks.
        own = [c for c in synonyms(e) if c in cf]
        lv = min((level[c] for c in core + own + [h] if c in level), default=None)
        if (own or h in FR_FIX) and lv is not None:
            fr = FR_FIX.get(h) or gloss(cf[own[0]])
            if 0 < spread < 5:  # regional variant (e.g. 奒 hai): last level
                lv = 5
            ranked.append(((lv, -spread, len(h), int(e['詞目id'])), word(e, fr, LEVELS[lv])))
        elif first_sense.get(e['詞目id']):  # no reliable French: dictionary-only, after everything else
            rest.append(((9 if lv is None else lv, -spread, len(h), int(e['詞目id'])), word(e, '', '7 · Dictionnaire')))
    hok += [w for _, w in sorted(ranked)] + [w for _, w in sorted(rest)]

    # ---- Cross-links, rendered as text: "謝謝 xièxie" on 多謝, and on 謝謝 the first
    # (most basic) Hokkien word pointing at it.
    man_by = {r[0]: r for r in man}
    back = {}
    for r in hok:
        if r[6] in man_by:
            back.setdefault(r[6], f'{r[0]} {r[1]}')
            r[6] = f'{r[6]} {man_by[r[6]][1]}'
        else:
            r[6] = ''
    for r in man:
        r[6] = back.get(r[0], '')

    kept = {r[7] for r in hok}
    examples = [(int(x['詞目id']), i, x['漢字'], x['羅馬字'], x['華語'])
                for i, x in enumerate(read('例句')) if int(x['詞目id']) in kept]  # sheet order = page order
    definitions = {int(i): '\n'.join(f'{n}. {d}' if len(ds) > 1 else d for n, d in enumerate(ds, 1))
                   for i, ds in defs.items() if int(i) in kept}
    write_db(f'{out_dir}/dict.db', {'hok': hok, 'man': man}, definitions, examples)
    print(f'hok: {len(hok)} words ({sum(1 for r in hok if r[3])} with French), man: {len(man)} words, '
          f'{len(back)} linked pairs, {len(examples)} examples')


if __name__ == '__main__':
    if sys.argv[1] == '--ods':
        dump_ods(*sys.argv[2:4])
    elif sys.argv[1] == '--font':
        rare_font(*sys.argv[2:4])
    else:
        main(*sys.argv[1:5])
