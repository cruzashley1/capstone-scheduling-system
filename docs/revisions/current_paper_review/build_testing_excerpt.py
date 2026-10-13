"""Standalone revision of Section 4.1: integrate the AI mapping into Table 24."""
from pathlib import Path
from xml.dom import minidom as D
import json,zipfile,hashlib,copy

ROOT=Path('C:/prototype/docs/revisions')
WORK=ROOT/'current_paper_review'
NAME='Section_4_1_Testing_Evidence_Update'
SOURCE=Path('C:/Users/user/OneDrive/Documents/RevisedPaper.docx')
manifest=json.loads((WORK/'edit_manifest.json').read_text(encoding='utf-8'))
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==manifest['source_sha256'], 'Source paper has changed; re-read it before editing.'
blocks=json.loads((WORK/'paper_blocks.json').read_text(encoding='utf-8'))
web=copy.deepcopy(next(b for b in blocks if b['i']==556)['rows'][2:])
mobile=copy.deepcopy(next(b for b in blocks if b['i']==561)['rows'][2:])
evidence=json.loads((WORK/'past_testing_evidence.json').read_text(encoding='utf-8'))
past_cases=evidence['cases']
past_by_id={case['combined_id']:case for case in past_cases}

def clean(s):
    return ' '.join(s.replace(' | ', ' ').split())

web=[[clean(c) for c in row] for row in web]
mobile=[[clean(c) for c in row] for row in mobile]
web_rows=[]
for row in web:
    mapping='—'
    if row[0]=='TC007':
        case=past_by_id['TC007']
        row[2]=case['condition']+' (Past record '+case['original_id']+'.)'
        row[3]=case['expected']
        row[4]=case['actual']
        mapping=case['mapping']
    web_rows.append(row[:5]+[mapping,row[5]])
web_rows.extend([
    ['TC010','AI Recommendation Explanation',
     'A live AI explanation is compared with the personnel and schedule records supplied for the absence; the AI and fallback displays are inspected.',
     'The explanation agrees with the supplied records, and the display distinguishes AI advice from rule-based fallback.',
     'Past TC034 supports the null-review display only. Comparison of a live explanation with its exact input records remains undocumented.',
     'Transparency','Not assessed'],
    ['TC011','Administrator Control of AI Advice',
     'The administrator rejects an AI recommendation, selects another eligible guard, and cancels a separate assignment attempt.',
     'The confirmed eligible choice is applied; no assignment occurs before confirmation; cancellation leaves the assignment unchanged.',
     'Past TC023 supports direct decision recording. The full select, cancel, and confirm workflow has no documented observation result.',
     'User controllability','Not assessed'],
])
for case in past_cases:
    if case['combined_id']=='TC007':
        continue
    web_rows.append([
        case['combined_id'],case['module'],
        case['condition']+' (Past record '+case['original_id']+'.)',
        case['expected'],case['actual'],case['mapping'],case['status']
    ])

for row in mobile:
    if row[0]=='TC003':
        row[4]='[Record the observed duty-status and phone-layout outcome after checking the test evidence.]'
        row[5]='Needs verification'
    elif row[0]=='TC004':
        row[3]='A valid emergency absence request filed before duty begins is accepted; filing after the duty has ended is refused with a clear reason.'
    elif row[0]=='TC006':
        row[4]='[Record whether the day-off request was saved against the correct unscheduled period after checking the test evidence.]'
        row[5]='Needs verification'
    elif row[0]=='TC0010':
        row[0]='TC010'

with zipfile.ZipFile(ROOT/'ISO_IEC_25059_Paper_Revision_Guide.docx') as z:
    parts={n:z.read(n) for n in z.namelist()}
d=D.parseString(parts['word/document.xml'])
body=d.getElementsByTagName('w:body')[0]
while body.firstChild:body.removeChild(body.firstChild)
W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R='http://schemas.openxmlformats.org/officeDocument/2006/relationships'
plain=[]

def el(tag,**attrs):
    n=d.createElementNS(W,'w:'+tag)
    for k,v in attrs.items():n.setAttributeNS(W,'w:'+k,str(v))
    return n

def run(parent,text,bold=False,highlight=False):
    r=el('r')
    if bold or highlight:
        rp=el('rPr')
        if bold:rp.appendChild(el('b'))
        if highlight:rp.appendChild(el('highlight',val='yellow'))
        r.appendChild(rp)
    for i,line in enumerate(text.split('\n')):
        if i:r.appendChild(el('br'))
        t=el('t');t.setAttribute('xml:space','preserve');t.appendChild(d.createTextNode(line));r.appendChild(t)
    parent.appendChild(r)

def paragraph(text,style='Normal',parent=None,bold=False,highlight=False):
    e=el('p');pp=el('pPr');pp.appendChild(el('pStyle',val=style));e.appendChild(pp)
    run(e,text,bold=bold,highlight=highlight)
    (body if parent is None else parent).appendChild(e)
    if parent is None:plain.append(text+'\n')
    return e

def page_break():
    e=el('p');pp=el('pPr');pp.appendChild(el('spacing',before=0,after=0,line=20,lineRule='exact'));e.appendChild(pp)
    r=el('r');r.appendChild(el('br',type='page'));e.appendChild(r);body.appendChild(e)

def section(landscape=True):
    s=el('sectPr')
    hr=el('headerReference',type='default');hr.setAttributeNS(R,'r:id','rId2');s.appendChild(hr)
    fr=el('footerReference',type='default');fr.setAttributeNS(R,'r:id','rId3');s.appendChild(fr)
    s.appendChild(el('type',val='nextPage'))
    if landscape:
        s.appendChild(el('pgSz',w=16838,h=11906,orient='landscape'))
        s.appendChild(el('pgMar',top=730,bottom=730,left=919,right=919,header=300,footer=300,gutter=0))
    else:
        s.appendChild(el('pgSz',w=11906,h=16838))
        s.appendChild(el('pgMar',top=1000,bottom=1000,left=1050,right=1050,header=400,footer=400,gutter=0))
    return s

def table(heads,rows,widths):
    t=el('tbl');pr=el('tblPr');pr.appendChild(el('tblW',w=sum(widths),type='dxa'));pr.appendChild(el('tblLayout',type='fixed'))
    borders=el('tblBorders')
    for name in ['top','bottom','left','right','insideH','insideV']:borders.appendChild(el(name,val='single',sz=4,color='99A8B1'))
    pr.appendChild(borders)
    mar=el('tblCellMar')
    for name in ['top','bottom','left','right']:mar.appendChild(el(name,w=85,type='dxa'))
    pr.appendChild(mar);t.appendChild(pr)
    grid=el('tblGrid')
    for width in widths:grid.appendChild(el('gridCol',w=width))
    t.appendChild(grid)
    for i,row in enumerate([heads]+rows):
        tr=el('tr');rp=el('trPr');rp.appendChild(el('cantSplit'))
        if i==0:rp.appendChild(el('tblHeader'))
        tr.appendChild(rp)
        for j,(text,width) in enumerate(zip(row,widths)):
            cell=el('tc');cp=el('tcPr');cp.appendChild(el('tcW',w=width,type='dxa'));cp.appendChild(el('vAlign',val='top'))
            cp.appendChild(el('shd',fill='173D50' if i==0 else ('F0F4F6' if i%2 else 'FFFFFF'),val='clear'))
            cell.appendChild(cp)
            pending=i>0 and row[-1] in ['Not assessed','Needs verification']
            paragraph(text,'TableHead' if i==0 else 'TableText',parent=cell,highlight=pending and j in [len(row)-1,4])
            tr.appendChild(cell)
        t.appendChild(tr)
    body.appendChild(t)
    paragraph('','Spacer')
    plain.append('| '+' | '.join(heads)+' |\n| '+' | '.join('---' for _ in heads)+' |')
    plain.extend('| '+' | '.join(row)+' |' for row in rows)
    plain.append('')

paragraph('4.1 Development and Testing','Title')
paragraph('Unit and Integration Testing','Heading2')
paragraph('Editing note — This updated copy incorporates the additional past test records. Replace the Unit and Integration Testing subsection and Tables 24–25 with this excerpt; continue with Response Time Testing. Remove any earlier separate Table 24A. Keep the evidence notes and unfinished observation sheets as working materials until completed, and remove editing notes before submission.','Note')
paragraph('Unit and integration testing examined whether the web and mobile applications performed the required scheduling, absence-handling, and duty-management functions. The tables report each test condition, expected behavior, documented actual result, and status. Table 24 also identifies the selected ISO/IEC 25059:2023 quality characteristics relevant to the AI-assisted replacement workflow. This mapping uses testing and observation rather than a separate respondent questionnaire.')
paragraph('Table 24. Unit and Integration Testing for Web Application','Caption')
table(['Test\nCase ID','Component / Module','Test Condition','Expected Behavior','Actual Result','Selected ISO/IEC 25059 Characteristic','Status'],web_rows,[1000,1850,3050,3100,3100,1900,1000])
paragraph('Legend: Passed — the past test record reports an outcome meeting the stated expectation, within the evidence scope noted below; it does not indicate a new execution for this revision. Failed — an observed outcome did not meet the expectation. Not assessed — the complete stated observation has not been documented, even if partial supporting tests exist. A dash (—) means no characteristic is assigned within this selected AI assessment.','Small')
paragraph('TC007 and TC012–TC018 incorporate historical records TC020–TC026 and TC034. They provide reported evidence for screening, context construction, fallback, caching, decision recording, replacement time constraints, and the null-review display. The AI context and review scripts use mock data and simulated responses; the panel tests use supplied test responses. These results do not establish the factual accuracy of a live explanation or the complete administrator interaction. TC010 and TC011 therefore remain Not assessed. Findings are interpreted within each tested scenario and separately from the ISO/IEC 25010 questionnaire means.')
paragraph('Editing note — Original case IDs are retained in the conditions and evidence notes for traceability. Historical execution dates, builds, and raw run logs were not supplied with the additional result rows; recover them from your records or document a new run. Do not substitute the screenshot date for the execution date. Use the observation sheets at the end to complete TC010 and TC011. No new application tests were executed for this document update.','Note')

page_break()
paragraph('Unit and Integration Testing — Mobile Application','Heading2')
paragraph('Table 25. Unit and Integration Testing for Mobile Application','Caption')
table(['Test\nCase ID','Component / Module','Test Condition','Expected Behavior','Actual Result','Status'],mobile,[800,1600,3800,3800,3700,1300])
paragraph('Legend: Passed — the reported actual result met the expected behavior for the tested case. Failed — the recorded actual result did not meet the expected behavior. Needs verification — the existing result entry does not establish the outcome for the stated scenario and must be checked against the test evidence.','Small')
paragraph('Editing note — In the supplied paper, mobile TC003 repeats the schedule-viewing result and TC006 repeats the leave-request result, although both were marked Passed. Their actual outcomes are left for verification here. TC004’s expected behavior has been corrected to match the absence-request scenario, and TC0010 has been corrected to TC010. Other mobile results are retained as reported. Fill the bracketed cells using the actual test records before submitting the paper.','Note')

# The portrait section contains method wording and the supporting working records.
break_p=el('p');break_pp=el('pPr');break_pp.appendChild(section(True));break_p.appendChild(break_pp);body.appendChild(break_p)
paragraph('Necessary related wording','Title')
paragraph('These are short additions for the method and reference. The main replacement excerpt ends after Table 25 above.','Note')
paragraph('Chapter III — 3.7 Evaluation Procedure','Heading2')
paragraph('Add under “Evaluation Instrument”, after the paragraph describing the existing Google Forms questionnaire. If your current copy already contains “AI Testing and Observation”, use this wording there once.','Note')
paragraph('The ISO/IEC 25010-based questionnaire remains the instrument for the respondent evaluation. A supplementary assessment maps documented unit and integration test results and researcher observations to selected ISO/IEC 25059:2023 quality characteristics: functional correctness, robustness, transparency, and user controllability (International Organization for Standardization [ISO] & International Electrotechnical Commission [IEC], 2023). These characteristics are identified in the existing web application testing table in Chapter IV, together with the relevant test conditions, expected behaviors, actual results, and statuses.')
paragraph('For each assessed case, the researchers compare the actual behavior with a predefined expected outcome and retain the test inputs, observer, execution date, system version, and supporting screenshots or logs. The record distinguishes live AI responses from simulated, cached, or unavailable responses. A behavior without a documented observation remains Not assessed. The AI-related findings are interpreted descriptively and are not combined with the questionnaire means. This procedure does not require another respondent questionnaire or an additional ISO/IEC 25059 rating scale.')
paragraph('References','Heading2')
paragraph('Add this entry if it is not already present.','Note')
paragraph('International Organization for Standardization, & International Electrotechnical Commission. (2023). Software engineering — Systems and software Quality Requirements and Evaluation (SQuaRE) — Quality model for AI systems (ISO/IEC Standard No. 25059:2023). https://www.iso.org/standard/80655.html')
paragraph('Consistency checks for the earlier edited copy','Heading2')
paragraph('Remove the separate Table 24A and its list-of-tables entry. Change any remaining references to that assessment to Table 24. Keep the existing ISO/IEC 25010 questionnaire, respondents, and survey-result tables. In Section 3.7, use “six selected characteristics” for the existing six-item ISO/IEC 25010 list. Keep Chapter V statements about pending observations until the actual results are documented. Refresh page numbers after pasting.','Note')

page_break()
paragraph('Supporting evidence notes','Title')
paragraph('Working appendix — Give this appendix the next available letter/title only if including it in the paper. Attach the original test records and execution logs with their original case IDs. These notes distinguish historical results from code inspection and pending observations.','Note')
paragraph(evidence['basis'])
for case in past_cases:
    paragraph(case['original_id']+' → Table 24 '+case['combined_id']+' — '+case['module'],'Heading2')
    paragraph(case['scope'])
paragraph('Record counts','Heading2')
paragraph('Table 24 contains 18 scenario rows: 16 reported Passed and two Not assessed. Seven reported rows were added; the eighth supplied historical case expands the existing TC007. Scenario rows and script assertions are different units. Do not add the shared 18-check review suite twice or describe all panel tests as null-response tests. Table 25 retains eight reported Passed cases and two results needing verification.')

for protocol in evidence['observation_protocol']:
    page_break()
    paragraph(protocol['id']+' observation sheet','Title')
    paragraph(protocol['title'],'Heading2')
    paragraph('Working test procedure — No outcome has been entered. Expected behaviors and examples below are not test findings.','Note')
    paragraph('Setup: '+protocol['setup'])
    for number,step in enumerate(protocol['steps'],1):
        paragraph(str(number)+'. '+step)
    paragraph('Evidence to retain: '+protocol['evidence'],'Small')
    paragraph(protocol['limit'],'Small')
    paragraph('Complete after execution','Heading2')
    paragraph('Run ID: __________    Observer: __________\nExecution date/time and time zone: __________\nBuild/commit and environment: __________\nScenario / input record references: __________\nAI mode and response source: __________\nModel / prompt version (if applicable): __________\nActual outcome for each step: __________\nEvidence file references: __________\nResult: Passed / Failed / Not assessed\nUnexecuted criteria or discrepancies: __________','Small')
body.appendChild(section(False))
parts['word/document.xml']=d.toxml(encoding='UTF-8')

styles=D.parseString(parts['word/styles.xml'])
def child(parent,tag):
    return next((c for c in parent.childNodes if c.nodeType==c.ELEMENT_NODE and c.tagName=='w:'+tag),None)
for s in styles.getElementsByTagName('w:style'):
    sid=s.getAttribute('w:styleId')
    for fonts in s.getElementsByTagName('w:rFonts'):
        if sid in ['Normal','TableText','TableHead','Heading2','Title']:
            fonts.setAttribute('w:ascii','Times New Roman');fonts.setAttribute('w:hAnsi','Times New Roman')
    if sid in ['TableText','TableHead']:
        for size in s.getElementsByTagName('w:sz'):size.setAttribute('w:val','21')
        for spacing in s.getElementsByTagName('w:spacing'):
            spacing.setAttribute('w:line','240');spacing.setAttribute('w:after','0')
    if sid=='Title':
        for size in s.getElementsByTagName('w:sz'):size.setAttribute('w:val','30')
    if sid=='Heading2':
        for size in s.getElementsByTagName('w:sz'):size.setAttribute('w:val','25')
    if sid=='Normal':
        for size in s.getElementsByTagName('w:sz'):size.setAttribute('w:val','23')
        for spacing in s.getElementsByTagName('w:spacing'):
            spacing.setAttribute('w:line','260');spacing.setAttribute('w:after','110')

def add_style(sid,name,size,italic=False,keep=False):
    s=styles.createElementNS(W,'w:style');s.setAttribute('w:type','paragraph');s.setAttribute('w:styleId',sid)
    for tag,val in [('name',name),('basedOn','Normal'),('next','Normal')]:
        n=styles.createElementNS(W,'w:'+tag);n.setAttribute('w:val',val);s.appendChild(n)
    pp=styles.createElementNS(W,'w:pPr')
    spacing=styles.createElementNS(W,'w:spacing');spacing.setAttribute('w:after','90');spacing.setAttribute('w:line','250');spacing.setAttribute('w:lineRule','auto');pp.appendChild(spacing)
    if keep:pp.appendChild(styles.createElementNS(W,'w:keepNext'))
    s.appendChild(pp)
    rp=styles.createElementNS(W,'w:rPr');sz=styles.createElementNS(W,'w:sz');sz.setAttribute('w:val',str(size));rp.appendChild(sz)
    if italic:rp.appendChild(styles.createElementNS(W,'w:i'))
    s.appendChild(rp);styles.documentElement.appendChild(s)
add_style('Caption','Table caption',23,italic=True,keep=True)
add_style('Small','Legend',20)
parts['word/styles.xml']=styles.toxml(encoding='UTF-8')

for path,text in [('word/header1.xml','SECTION 4.1  |  UNIT AND INTEGRATION TESTING'),('word/footer1.xml','Sched • Combined testing-table revision                                             ')]:
    x=D.parseString(parts[path]);x.getElementsByTagName('w:t')[0].firstChild.data=text;parts[path]=x.toxml(encoding='UTF-8')
core=D.parseString(parts['docProps/core.xml'])
core.getElementsByTagName('dc:title')[0].firstChild.data='Section 4.1: Unit and Integration Testing — Combined ISO Assessment'
core.getElementsByTagName('dc:description')[0].firstChild.data='Updated testing subsection incorporating historical test evidence, scope notes, and two unexecuted observation procedures. No new test outcomes are claimed.'
parts['docProps/core.xml']=core.toxml(encoding='UTF-8')

dest=ROOT/(NAME+'.docx')
with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
    for n,data in parts.items():z.writestr(n,data)
with zipfile.ZipFile(dest) as z:
    assert z.testzip() is None
    for n in z.namelist():
        if n.endswith('.xml') or n.endswith('.rels'):D.parseString(z.read(n))
assert len(web_rows)==18 and len(mobile)==10
assert [r[0] for r in web_rows]==[f'TC{i:03}' for i in range(1,19)]
assert [r[0] for r in mobile]==[f'TC{i:03}' for i in range(1,11)]
assert sum(r[-1]=='Passed' for r in web_rows)==16
assert sum(r[-1]=='Not assessed' for r in web_rows)==2
assert sum(r[-1]=='Needs verification' for r in mobile)==2
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==manifest['source_sha256']
(WORK/(NAME+'.txt')).write_text('\n'.join(plain),encoding='utf-8')
(WORK/'testing_evidence_update_data.json').write_text(json.dumps({'web_rows':web_rows,'mobile_rows':mobile,'historical_case_crosswalk':{c['original_id']:c['combined_id'] for c in past_cases},'source_sha256':manifest['source_sha256']},ensure_ascii=False,indent=2),encoding='utf-8')
guide=['# Completing the two AI observation checks','',
       'Status: prepared procedure; not executed. Use the updated Section 4.1 Word/PDF for the integrated testing table and historical evidence notes.','',
       'Keep the existing ISO/IEC 25010 questionnaire results. Complete the following checks through researcher observation and retain the evidence.','']
for protocol in evidence['observation_protocol']:
    guide+=['## '+protocol['id']+' — '+protocol['title'],'',protocol['setup'],'']
    guide += [str(i)+'. '+step for i,step in enumerate(protocol['steps'],1)]
    guide+=['','Evidence: '+protocol['evidence'],'',protocol['limit'],'']
guide+=['## Record each run','',
        '| Field | Entry |','| --- | --- |',
        '| Run ID / test case | |','| Observer | |','| Execution date/time + time zone | |',
        '| Build/commit + environment | |','| Scenario / input record references | |',
        '| AI mode: live, simulated, cached, disabled, unavailable | |',
        '| Model / prompt version / response source | |','| Actual outcome for each step | |',
        '| Evidence file references | |','| Result: Passed, Failed, Not assessed | |',
        '| Unexecuted criteria or discrepancies | |','',
        'For TC010, also make a claim comparison:','',
        '| Exact factual claim | Context field/value | Underlying record | Supported / contradicted / unsupported |',
        '| --- | --- | --- | --- |','| | | | |','',
        'Enter actual results only after execution. If some steps were not performed, preserve that limitation; do not mark the whole row Passed. Keep failed runs when documenting a later correction and retest.','',
        'Table 25 mobile TC003 and TC006 also still need their original evidence checked, or a new observation recorded.','']
(ROOT/'AI_Observation_Checklist.md').write_text('\n'.join(guide),encoding='utf-8')
print('Created:',dest)
print('Table 24: 16 reported Passed cases and 2 unassessed AI observation cases.')
print('Table 25: 10 cases; 2 original result entries marked for verification.')
print('Original paper unchanged.')
