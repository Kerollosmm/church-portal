#!/usr/bin/env python3
"""Builds assets/verses/daily_verses.json (the home "verse of the day").

Text is never typed by hand: every verse is copied byte-for-byte from the
public-domain Arabic Van Dyck (Smith-Van Dyke) Bible published by eBible.org
(https://ebible.org/Scriptures/arb-vd_vpl.zip, "Public Domain", Syrian
Mission / American Bible Society). The English text of the same verses
(ADR-047) is copied byte-for-byte from the public-domain World English Bible
British Edition (https://ebible.org/Scriptures/eng-webbe_vpl.zip: the WEB
with "the LORD" instead of "Yahweh"; "not copyrighted, Public Domain"). Both
zips are checked against pinned SHA-256s so a changed upstream file cannot
slip in silently. The verse selection (and so the day rotation) is still
made from the Arabic text only, so adding English changed no day's verse.

Usage: python3 tool/gen_daily_verses.py [arb-vd_vpl.zip [eng-webbe_vpl.zip]]
(without arguments the zips are downloaded with curl).
"""
import hashlib, io, json, os, random, subprocess, sys, zipfile

SRC_URL = 'https://ebible.org/Scriptures/arb-vd_vpl.zip'
SRC_SHA256 = '070404da2e13e641b7550b50d7e777480b2cc2667e9669f2194d909ca04cd68a'
EN_URL = 'https://ebible.org/Scriptures/eng-webbe_vpl.zip'
EN_SHA256 = '018b2ac4ebafdbfcd00c69f9a48ee775c2a6f318d20a93476058a1162d63423a'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REFS = os.path.join(ROOT, 'tool', 'daily_verse_refs.txt')
OUT = os.path.join(ROOT, 'assets', 'verses', 'daily_verses.json')
COUNT = 366  # one per day of a leap year
MAX_LEN = 420  # characters incl. diacritics; keeps the card short

# BibleWorks codes used by the eBible VPL file -> [Arabic, English] names.
BOOKS = {
    'GEN': ['تكوين', 'Genesis'], 'EXO': ['خروج', 'Exodus'], 'LEV': ['لاويين', 'Leviticus'],
    'NUM': ['عدد', 'Numbers'], 'DEU': ['تثنية', 'Deuteronomy'], 'JOS': ['يشوع', 'Joshua'],
    'RUT': ['راعوث', 'Ruth'], '1SA': ['صموئيل الأول', '1 Samuel'], '2SA': ['صموئيل الثاني', '2 Samuel'],
    '1KI': ['ملوك الأول', '1 Kings'], '2KI': ['ملوك الثاني', '2 Kings'],
    '1CH': ['أخبار الأيام الأول', '1 Chronicles'], '2CH': ['أخبار الأيام الثاني', '2 Chronicles'],
    'NEH': ['نحميا', 'Nehemiah'], 'JOB': ['أيوب', 'Job'], 'PSA': ['مزمور', 'Psalm'],
    'PRO': ['أمثال', 'Proverbs'], 'ECC': ['جامعة', 'Ecclesiastes'], 'ISA': ['إشعياء', 'Isaiah'],
    'JER': ['إرميا', 'Jeremiah'], 'LAM': ['مراثي إرميا', 'Lamentations'], 'EZE': ['حزقيال', 'Ezekiel'],
    'DAN': ['دانيال', 'Daniel'], 'HOS': ['هوشع', 'Hosea'], 'JOE': ['يوئيل', 'Joel'],
    'MIC': ['ميخا', 'Micah'], 'NAH': ['ناحوم', 'Nahum'], 'HAB': ['حبقوق', 'Habakkuk'],
    'ZEP': ['صفنيا', 'Zephaniah'], 'ZEC': ['زكريا', 'Zechariah'], 'MAL': ['ملاخي', 'Malachi'],
    'MAT': ['متى', 'Matthew'], 'MAR': ['مرقس', 'Mark'], 'LUK': ['لوقا', 'Luke'], 'JOH': ['يوحنا', 'John'],
    'ACT': ['أعمال الرسل', 'Acts'], 'ROM': ['رومية', 'Romans'], '1CO': ['كورنثوس الأولى', '1 Corinthians'],
    '2CO': ['كورنثوس الثانية', '2 Corinthians'], 'GAL': ['غلاطية', 'Galatians'], 'EPH': ['أفسس', 'Ephesians'],
    'PHI': ['فيلبي', 'Philippians'], 'COL': ['كولوسي', 'Colossians'],
    '1TH': ['تسالونيكي الأولى', '1 Thessalonians'], '2TH': ['تسالونيكي الثانية', '2 Thessalonians'],
    '1TI': ['تيموثاوس الأولى', '1 Timothy'], '2TI': ['تيموثاوس الثانية', '2 Timothy'], 'TIT': ['تيطس', 'Titus'],
    'HEB': ['العبرانيين', 'Hebrews'], 'JAM': ['يعقوب', 'James'], '1PE': ['بطرس الأولى', '1 Peter'],
    '2PE': ['بطرس الثانية', '2 Peter'], '1JO': ['يوحنا الأولى', '1 John'], '3JO': ['يوحنا الثالثة', '3 John'],
    'JUD': ['يهوذا', 'Jude'], 'REV': ['رؤيا يوحنا', 'Revelation'],
}
AR_DIGITS = str.maketrans('0123456789', '٠١٢٣٤٥٦٧٨٩')


def load_zip(arg, url, sha, member):
    if len(sys.argv) > arg:
        data = open(sys.argv[arg], 'rb').read()
    else:
        data = subprocess.run(['curl', '-sSLf', url], check=True, capture_output=True).stdout
    digest = hashlib.sha256(data).hexdigest()
    if digest != sha:
        sys.exit(f'SHA-256 mismatch for {url}: {digest} (expected {sha})')
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        return z.read(member).decode('utf-8')


def parse_vpl(text):
    out = {}
    for line in text.splitlines():
        parts = line.split(' ', 2)
        if len(parts) == 3:
            out[f'{parts[0]} {parts[1]}'] = parts[2].strip()
    return out


def main():
    bible = parse_vpl(load_zip(1, SRC_URL, SRC_SHA256, 'arb-vd_vpl.txt'))
    english = parse_vpl(load_zip(2, EN_URL, EN_SHA256, 'eng-webbe_vpl.txt'))
    toks = open(REFS, encoding='utf-8').read().split()
    refs, seen = [], set()
    for i in range(0, len(toks), 2):
        ref = f'{toks[i]} {toks[i + 1]}'
        if ref in seen:
            continue
        seen.add(ref)
        if ref not in bible:
            sys.exit(f'missing verse {ref}')
        if toks[i] not in BOOKS:
            sys.exit(f'no book name for {toks[i]}')
        if len(bible[ref]) <= MAX_LEN:
            refs.append(ref)
    if len(refs) < COUNT:
        sys.exit(f'only {len(refs)} usable verses, need {COUNT}')
    refs = refs[:COUNT]
    random.Random(2026).shuffle(refs)  # stable mix of books across the year
    verses = []
    for ref in refs:
        book, cv = ref.split(' ')
        ch, v = cv.split(':')
        ar, en = BOOKS[book]
        if not english.get(ref):
            sys.exit(f'no English text for {ref}')
        verses.append({
            'ref': ref,
            'refAr': f'{ar} {ch.translate(AR_DIGITS)}: {v.translate(AR_DIGITS)}',
            'refEn': f'{en} {ch}:{v}',
            'textAr': bible[ref],
            'textEn': english[ref],
        })
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    doc = {
        'translation': 'Arabic Van Dyck (Smith-Van Dyke), 1865',
        'license': 'Public Domain',
        'source': SRC_URL,
        'sourceSha256': SRC_SHA256,
        'translationEn': 'World English Bible British Edition (WEBBE)',
        'licenseEn': 'Public Domain',
        'sourceEn': EN_URL,
        'sourceEnSha256': EN_SHA256,
        'count': len(verses),
        'verses': verses,
    }
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(f'wrote {len(verses)} verses to {OUT}')


if __name__ == '__main__':
    main()
