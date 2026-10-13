"""Create a highlighted review copy, preserving all original document parts."""
from pathlib import Path
from xml.dom import minidom as D
import zipfile
import hashlib
import json
import re

SOURCE = Path('C:/Users/user/OneDrive/Documents/RevisedPaper.docx')
OUT = Path('C:/prototype/docs/revisions')
WORK = OUT / 'current_paper_review'
DEST = OUT / 'RevisedPaper_ISO25059_Edited.docx'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
with zipfile.ZipFile(SOURCE) as z:
    contents = {item.filename: z.read(item.filename) for item in z.infolist()}
    infos = z.infolist()
doc = D.parseString(contents['word/document.xml'])
body = doc.getElementsByTagName('w:body')[0]
original = [e for e in body.childNodes if e.nodeType == e.ELEMENT_NODE]
changes = []
next_bookmark = 100
cache_path = WORK / 'all_page_locations.json'
page_cache = json.loads(cache_path.read_text(encoding='utf-8-sig')) if cache_path.exists() else {}


def el(tag, **attrs):
    n = doc.createElementNS(W, 'w:' + tag)
    for key, value in attrs.items():
        n.setAttributeNS(W, 'w:' + key, str(value))
    return n


def direct(parent, name):
    return next((c for c in parent.childNodes if c.nodeType == c.ELEMENT_NODE and c.tagName == 'w:' + name), None)


def text_of(node):
    return ''.join(t.firstChild.data if t.firstChild else '' for t in node.getElementsByTagName('w:t'))


def bookmark(paragraph, name):
    global next_bookmark
    start = el('bookmarkStart', id=next_bookmark, name=name)
    end = el('bookmarkEnd', id=next_bookmark)
    next_bookmark += 1
    props = direct(paragraph, 'pPr')
    if props is not None:
        paragraph.insertBefore(start, props.nextSibling)
    else:
        paragraph.insertBefore(start, paragraph.firstChild)
    paragraph.appendChild(end)


def run(parent, text, highlight=True, bold=False, size=None, italic=False):
    r = el('r')
    rp = el('rPr')
    if bold:
        rp.appendChild(el('b'))
    if italic:
        rp.appendChild(el('i'))
    if size is not None:
        rp.appendChild(el('sz', val=size))
        rp.appendChild(el('szCs', val=size))
    if highlight:
        rp.appendChild(el('highlight', val='yellow'))
    r.appendChild(rp)
    t = el('t')
    t.setAttribute('xml:space', 'preserve')
    t.appendChild(doc.createTextNode(text))
    r.appendChild(t)
    parent.appendChild(r)
    return r


def paragraph(text, kind='body', highlight=True):
    p = el('p')
    pp = el('pPr')
    pp.appendChild(el('ind', left=0, right=0, firstLine=360 if kind == 'body' else 0))
    pp.appendChild(el('spacing', before=0, after=120, line=476 if kind == 'body' else 260, lineRule='auto'))
    pp.appendChild(el('jc', val='both' if kind == 'body' else 'left'))
    pp.appendChild(el('widowControl'))
    if kind in ('heading', 'caption'):
        pp.appendChild(el('keepNext'))
        pp.appendChild(el('keepLines'))
    p.appendChild(pp)
    run(p, text, highlight=highlight, bold=kind=='heading', italic=kind=='caption', size=24 if kind!='table' else 20)
    return p


def replace(index, text, label, bold=False):
    p = original[index]
    before = text_of(p)
    for n in list(p.childNodes):
        if not (n.nodeType == n.ELEMENT_NODE and n.tagName == 'w:pPr'):
            p.removeChild(n)
    run(p, text, bold=bold)
    changes.append({'action':'replace', 'original_block':index, 'label':label, 'before':before, 'after':text})
    return p


def remove(index):
    body.removeChild(original[index])


def insert_before(index, nodes, label):
    for node in nodes:
        body.insertBefore(node, original[index])
    changes.append({'action':'insert', 'before_original_block':index, 'label':label, 'text':[text_of(n) for n in nodes]})


def make_table(heads, rows, widths):
    tbl = el('tbl')
    props = el('tblPr')
    props.appendChild(el('tblW', w=8645, type='dxa'))
    props.appendChild(el('tblLayout', type='fixed'))
    borders = el('tblBorders')
    for side in ['top','left','bottom','right','insideH','insideV']:
        borders.appendChild(el(side, val='single', sz=4, color='808080'))
    props.appendChild(borders)
    margins = el('tblCellMar')
    for side in ['top','left','bottom','right']:
        margins.appendChild(el(side, w=90, type='dxa'))
    props.appendChild(margins)
    tbl.appendChild(props)
    grid = el('tblGrid')
    for width in widths:
        grid.appendChild(el('gridCol', w=width))
    tbl.appendChild(grid)
    for idx, row in enumerate([heads] + rows):
        tr = el('tr')
        trpr = el('trPr')
        trpr.appendChild(el('cantSplit'))
        if idx == 0:
            trpr.appendChild(el('tblHeader'))
        tr.appendChild(trpr)
        for text, width in zip(row, widths):
            tc = el('tc')
            tcp = el('tcPr')
            tcp.appendChild(el('tcW', w=width, type='dxa'))
            tcp.appendChild(el('vAlign', val='top'))
            tc.appendChild(tcp)
            p = paragraph(text, 'table')
            if idx == 0:
                p.getElementsByTagName('w:rPr')[0].appendChild(el('b'))
            tc.appendChild(p)
            tr.appendChild(tc)
        tbl.appendChild(tr)
    return tbl


# Supporting alignment: the questionnaire and its scores are preserved.
replace(96, 'The ISO/IEC 25010-based questionnaire evaluation resulted in overall ratings of 4.79 from the five IT experts and 4.74 from the 211 end users, both interpreted as Highly Acceptable. A supplementary assessment maps the documented AI-related tests to selected ISO/IEC 25059:2023 quality characteristics and identifies behaviors requiring further observation. The findings indicate that the developed system provides an organized approach to managing security personnel schedules and handling absences while assisting administrators in making replacement assignments.', 'Abstract: distinguish survey results from the supplementary AI assessment')
bookmark(original[96], 'ISO_Abstract')
scope = paragraph('The software evaluation uses the existing ISO/IEC 25010-based questionnaire. The AI-assisted absence-handling feature is additionally examined through documented testing and observation guided by selected ISO/IEC 25059:2023 quality characteristics: functional correctness, robustness, transparency, and user controllability. This supplementary assessment uses the researchers’ test records and does not require a separate respondent questionnaire. Its conclusions are limited to the characteristics and test conditions supported by recorded evidence.')
bookmark(scope, 'ISO_Scope')
insert_before(241, [scope], 'Section 1.3: add the scope of the AI assessment')

# Main change 1: Section 3.7.
replace(500, 'The evaluation uses two complementary sources of evidence. The ISO/IEC 25010-based questionnaire provides respondent ratings of software quality and acceptability. A supplementary technical assessment uses selected characteristics from ISO/IEC 25059:2023 to interpret documented testing and observation of the AI-assisted absence-handling feature. ISO/IEC 25059 provides a quality model for AI systems (International Organization for Standardization [ISO] & International Electrotechnical Commission [IEC], 2023); the specific observation criteria are defined for this project.', 'Section 3.7: introduce both evaluation approaches')
replace(501, 'Table 22 presents the six software quality criteria used in the existing ISO/IEC 25010-based respondent evaluation. The supplementary AI assessment is described separately under AI Testing and Observation.', 'Section 3.7: correct Table 22 reference and clarify its purpose')
replace(508, 'The study employed a descriptive-quantitative approach for the respondent evaluation. Following the Rapid Application Development model, the developed system was evaluated through an ISO/IEC 25010-based instrument covering six selected characteristics: Functional Suitability, Performance Efficiency, Compatibility, Reliability, Usability, and Maintainability. The additional ISO/IEC 25059 assessment organizes existing AI-related test findings and further observations by quality characteristic. It does not introduce another respondent survey or replace the existing software-quality evaluation.', 'Evaluation Design: change eight to six and explain the additional test-based assessment')
remove(509)
replace(512, 'The questionnaire respondents consisted of two groups: five (5) IT experts and 211 end users. The IT experts evaluated technical aspects of the developed system, while the end users comprised administrators, head guards, and security personnel of Kaizen Security Agency Corp. Both groups used the existing ISO/IEC 25010-based evaluation instrument. The supplementary ISO/IEC 25059 assessment uses test cases and researcher observations; it does not add another respondent group.', 'Respondents: retain the original sample and distinguish it from test observers')
replace(515, 'The researchers used a structured Evaluation Rating Scale delivered through Google Forms. The questionnaire was adapted from the ISO/IEC 25010 software quality model and used statements suitable for the study’s respondents. It remains the instrument for the respondent evaluation.', 'Evaluation Instrument: retain the existing Google Forms questionnaire')
remove(516)
method_heading = paragraph('AI Testing and Observation', 'heading')
bookmark(method_heading, 'ISO_Method')
method = [method_heading,
    paragraph('The supplementary AI assessment maps documented test results to four selected ISO/IEC 25059:2023 quality characteristics. Functional correctness is examined by checking whether replacement candidates satisfy the independently verified availability, schedule, shift, and post requirements. Robustness is examined through the workflow’s behavior when the AI service fails or the candidate information changes. Transparency is examined by checking whether the recommendation’s explanation agrees with the supplied records and whether AI advice can be distinguished from rule-based fallback. User controllability is examined by checking whether the administrator can confirm, reject, or change a recommendation before assignment.'),
    paragraph('For each assessed case, the researchers record the test condition, expected behavior, actual behavior, and supporting screenshot or log, together with the observer, test date, and system version. The record identifies whether the AI response was live, simulated, cached, or unavailable. Existing test records may be used when their conditions and outcomes can be traced. Where an observation is missing, the corresponding behavior is marked Not assessed until supporting evidence is recorded. The observation record is completed by the researchers and is not distributed as another questionnaire.'),
    paragraph('The findings are compared with the expected behavior and reported descriptively. A criterion is marked Met only when supported by the recorded observation, and Not met when the actual behavior differs from the expected result. These are study-specific reporting labels. Simulated AI failures support findings about validation and fallback behavior; they do not establish the quality of live model recommendations. The assessment covers the selected characteristics and observed scenarios rather than full conformity with ISO/IEC 25059.'),
]
insert_before(518, method, 'Section 3.7: add AI Testing and Observation')
replace(519, 'The questionnaire used the following five-point Likert scale to rate the acceptability of each item. This scale applies to the respondent evaluation; it is not used to score the ISO/IEC 25059 test observations.', 'Likert Scale: limit Likert ratings to the questionnaire')
replace(525, 'The questionnaire means summarize respondent ratings of the six software quality characteristics and the overall acceptability of the Scheduling and Duty Management System.', 'Clarify the role of the questionnaire means')
analysis = paragraph('The ISO/IEC 25059 observations are analyzed separately by comparing the expected and actual behavior for each test case. The discussion identifies which quality characteristic is supported, the evidence used, and any limitation or observation still required. These findings are not combined with the questionnaire means, and no additional Likert rating or overall ISO/IEC 25059 score is calculated.')
bookmark(analysis, 'ISO_Analysis')
insert_before(535, [analysis], 'Data Analysis Method: distinguish observation findings from weighted means')

# Main change 2: Section 4.1, immediately after the existing web tests.
replace(550, 'RESULTS AND DISCUSSIONS', 'Correct Chapter IV subtitle to match the chapter content', bold=True)
replace(552, 'This chapter presents the development, testing, and evaluation of the Scheduling and Duty Management System with AI Application in Absence Handling for Kaizen Security Agency Corp. It reports unit and integration tests, response-time measurements, and the ISO/IEC 25010-based ratings of IT experts and end users. A supplementary assessment maps the documented AI-related behavior to selected ISO/IEC 25059:2023 quality characteristics. The interpretation distinguishes tested behavior from features that require further recorded observation.', 'Chapter IV introduction: include the supplementary AI assessment')
result_heading = paragraph('AI Quality Assessment Based on ISO/IEC 25059:2023', 'heading')
bookmark(result_heading, 'ISO_Results')
caption = paragraph('Table 24A. AI Quality Assessment Based on Testing and Observation', 'caption')
bookmark(caption, 'ISO_Table24A')
assessment = make_table(
    ['Quality characteristic', 'Behavior documented in the paper', 'Evidence and interpretation'],
    [
        ['Functional correctness', 'Ineligible candidates were excluded and the remaining replacement candidates were scored using the scheduling criteria.', 'Table 24, TC007 reports the screening and scoring result. It supports correctness of the tested rule-based screening; it does not establish that the AI selects the best eligible guard.'],
        ['Robustness', 'The rule-based ranking remained available under the AI failure conditions tested.', 'Table 24, TC007 and Section 5.1 report fallback behavior. This supports continuity of the replacement workflow in those conditions. The test logs should identify the individual failure cases.'],
        ['Transparency', 'The system provides explanatory reasoning with its replacement recommendation.', 'Sections 1.3 and 5.1 describe this feature. Table 24 does not separately report whether live explanations agree with the source records. Explanation accuracy therefore remains Not assessed in this supplementary mapping.'],
        ['User controllability', 'The administrator confirms the final replacement assignment.', 'Sections 1.3 and 3.8 describe administrator control. Table 24 does not separately record rejecting a recommendation, selecting an alternative, or cancelling an assignment. These interaction outcomes remain Not assessed in this mapping.'],
    ], [1690, 2920, 4035])
result_nodes = [result_heading,
    paragraph('The AI-assisted absence-handling feature was examined by mapping the existing test findings and documented behavior to selected ISO/IEC 25059:2023 quality characteristics. Table 24A identifies the available evidence and the limits of each interpretation. It uses the current paper’s reported results and does not treat an implemented feature as proof that every related quality requirement has been tested.'),
    caption, assessment,
    paragraph('The documented screening and fallback results provide evidence for specific aspects of functional correctness and robustness within the tested workflow. Explanation accuracy and the administrator’s rejection, alternative-selection, and cancellation actions require separate observation records before a test finding can be reported. These observations can be collected during system testing without administering another questionnaire. The findings do not establish that AI ranking is superior to rule-based ranking or that the system conforms to all requirements of ISO/IEC 25059.'),
]
insert_before(560, result_nodes, 'Section 4.1: add Table 24A after Table 24 and its legend')

# Brief alignment in Chapter V; no new measured results are supplied.
finding = paragraph('The supplementary ISO/IEC 25059 mapping identified reported evidence for candidate screening and preservation of the rule-based ranking during the tested AI failures. These findings support specific aspects of functional correctness and robustness. The paper describes explanatory reasoning and administrator confirmation, but separate observations are still needed to establish explanation accuracy and the outcomes of rejecting, changing, or cancelling a recommendation. These remaining checks are part of system testing rather than a new respondent evaluation.')
bookmark(finding, 'ISO_Findings')
insert_before(647, [finding], 'Section 5.1: summarize the evidence and remaining observations')
replace(659, 'The advisory placement of AI allows the replacement workflow to retain its rule-based candidate ranking when the AI service cannot provide usable advice. The reported tests support this fallback behavior under the conditions examined. The ISO/IEC 25059 mapping therefore supports conclusions about the documented screening and fallback behavior, while further observations are needed for explanation accuracy and administrator control. The study does not establish that AI always improves the ranking or that the observed behaviors demonstrate full conformity with the standard.', 'Section 5.2: align the AI conclusion with the available evidence')
bookmark(original[659], 'ISO_Conclusion')
replace(670, 'Analyze recorded administrator decisions against AI recommendations to examine usefulness and refine rule-based scoring weights. Maintain the golden-file contract test by running it before every release and documenting endpoint differences. Complete the remaining ISO/IEC 25059 observations by comparing live explanations with the underlying records and recording the administrator’s rejection, alternative-selection, and cancellation actions. Retain the test conditions, actual outcomes, screenshots or logs, and system version as evidence, and repeat relevant checks after changes to the model, prompt, rules, or interface.', 'Section 5.3 recommendation 4: specify the remaining observations')
bookmark(original[670], 'ISO_Recommendation')

# Main change 3: add the standard to References.
ref_heading = paragraph('Evaluation Standard', 'heading')
reference = paragraph('International Organization for Standardization, & International Electrotechnical Commission. (2023). Software engineering — Systems and software Quality Requirements and Evaluation (SQuaRE) — Quality model for AI systems (ISO/IEC Standard No. 25059:2023). https://www.iso.org/standard/80655.html')
bookmark(ref_heading, 'ISO_Reference')
insert_before(728, [ref_heading, reference], 'References: add ISO/IEC 25059:2023')

# Refresh the original manual page references from the exported review copy.
# Original list wording is retained and bookmark positions drive the cached numbers.
toc_map = {100:1, 103:213,104:217,105:225,106:246,107:258,111:283,112:294,114:306,115:318,116:329,
    119:337,120:352,121:356,122:366,123:367,124:376,125:422,126:431,127:436,128:492,129:495,
    130:499,131:535,133:553,134:554,135:577,136:630,137:631,139:641,140:654,141:661,
    142:677,143:730,144:731,145:734,146:740,147:757,148:1074}
# A combined conceptual-framework / IPO entry contains two page numbers; split it cleanly.
toc_map.pop(120)
body_caption = {}
for i,e in enumerate(original):
    if i < 210 or e.tagName != 'w:p':
        continue
    t = text_of(e).strip()
    m = re.match(r'^(Table|Figure)\s+(\d+)(?:\s*[:.]|\s+[A-Z])', t)
    if m and len(t) < 170:
        body_caption.setdefault((m.group(1),m.group(2)),i)
for i in list(range(155,189)) + list(range(195,208)):
    t = text_of(original[i])
    m = re.match(r'^(Table|Figure)\s+(\d+)', t)
    if m:
        toc_map[i] = body_caption[(m.group(1), m.group(2))]


def page_field(p, target, label=None, highlight=False):
    if label is None:
        label = re.sub(r'\s*\d+\s*$', '', text_of(p)).rstrip()
    props = direct(p, 'pPr')
    for n in list(p.childNodes):
        if n is not props:
            p.removeChild(n)
    run(p, label + ' ', highlight=highlight)
    run(p, str(page_cache.get(target, {}).get('printed_page', 1)), highlight=highlight)


for list_index, target_index in toc_map.items():
    if list_index == 100:  # Existing roman title-page label does not need conversion.
        continue
    target = f'PaperAt_{target_index}'
    if not any(e.getAttribute('w:name') == target for e in doc.getElementsByTagName('w:bookmarkStart')):
        bookmark(original[target_index], target)
    page_field(original[list_index], target)
bookmark(original[352], 'PaperAt_352')
bookmark(original[354], 'PaperAt_354')
page_field(original[120], 'PaperAt_352', '3.2 Conceptual Framework ……………………………………………………')
ipo = original[120].cloneNode(deep=True)
page_field(ipo, 'PaperAt_354', '   Input Process Output Diagram ………………………………………………')
body.insertBefore(ipo, original[121])

new_toc = original[134].cloneNode(deep=True)
page_field(new_toc, 'ISO_Results', '   AI Quality Assessment (ISO/IEC 25059) ……………………………………', True)
body.insertBefore(new_toc, original[135])
new_lot = original[178].cloneNode(deep=True)
page_field(new_lot, 'ISO_Table24A', 'Table 24A AI Quality Assessment Based on Testing and Observation ……', True)
body.insertBefore(new_lot, original[179])

# Explicit markers allow reliable navigation and layout inspection in Word.
bookmark(original[499], 'ISO_Section37')
bookmark(original[553], 'ISO_Section41')
bookmark(original[210], 'PaperBodyStart')
bookmark(original[153], 'PaperNumberingStart')
contents['word/document.xml'] = doc.toxml(encoding='UTF-8')
DEST.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(DEST,'w',zipfile.ZIP_DEFLATED) as z:
    for info in infos:
        z.writestr(info, contents[info.filename])

# Audit preservation before Word performs its normal save and field update.
with zipfile.ZipFile(DEST) as revised:
    assert revised.testzip() is None
    for name,data in contents.items():
        if name != 'word/document.xml':
            assert revised.read(name) == data
    assert len(revised.namelist()) == len(infos)
    D.parseString(revised.read('word/document.xml'))
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == source_hash
manifest = {'source':str(SOURCE),'source_sha256':source_hash,'output':str(DEST),'changes':changes,
    'preserved_original_parts':len(infos)-1,
    'existing_survey_tables_unchanged':True,
    'all_original_media_preserved':True,
    'navigation_bookmarks':['ISO_Abstract','ISO_Scope','ISO_Section37','ISO_Method','ISO_Analysis','ISO_Section41','ISO_Results','ISO_Table24A','ISO_Findings','ISO_Conclusion','ISO_Recommendation','ISO_Reference']}
(WORK/'edit_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('Created:',DEST)
print('Recorded edits:',len(changes))
print('Preserved original non-document parts:',len(infos)-1)
print('Original file unchanged; all original tables, illustrations, and attachments retained.')
