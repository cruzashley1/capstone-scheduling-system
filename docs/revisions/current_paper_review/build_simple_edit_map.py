from pathlib import Path
from xml.dom import minidom as D
import zipfile,json

ROOT=Path('C:/prototype/docs/revisions')
locations=json.loads((ROOT/'current_paper_review/page_locations.json').read_text(encoding='utf-8-sig'))
pages={e['bookmark']:e for e in locations['locations']}
with zipfile.ZipFile(ROOT/'ISO_IEC_25059_Paper_Revision_Guide.docx') as z:
    parts={n:z.read(n) for n in z.namelist()}
d=D.parseString(parts['word/document.xml'])
body=d.getElementsByTagName('w:body')[0]
section=body.getElementsByTagName('w:sectPr')[0].cloneNode(True)
while body.firstChild:body.removeChild(body.firstChild)
W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'

def el(tag,**attrs):
    e=d.createElementNS(W,'w:'+tag)
    for k,v in attrs.items():e.setAttributeNS(W,'w:'+k,str(v))
    return e

def p(text,style='Normal'):
    e=el('p');pr=el('pPr');pr.appendChild(el('pStyle',val=style));e.appendChild(pr)
    r=el('r');t=el('t');t.setAttribute('xml:space','preserve');t.appendChild(d.createTextNode(text));r.appendChild(t);e.appendChild(r)
    body.appendChild(e)
    return e

def loc(key):
    return f"printed page {pages[key]['printed_page']} (PDF page {pages[key]['physical_page']})"

p('Read this first: what changed','Title')
p('Based on your actual RevisedPaper.docx • All edits are already placed in the Word review copy.','Note')
p('Open RevisedPaper_ISO25059_Edited.docx. Yellow highlighting marks added or replaced text. Your original file is unchanged. You can review the edits in context instead of copying passages from the earlier guide.')
p('The three main changes','Heading2')
p('1. Chapter III — 3.7 Evaluation Procedure','Heading2')
p('Location: '+loc('ISO_Section37')+'. Search in Word for “AI Testing and Observation”.','Note')
p('This section now explains both methods: your existing ISO/IEC 25010 questionnaire measures respondent ratings; selected ISO/IEC 25059 characteristics are examined through tests and researcher observations. It explains what to observe and record. There is no new respondent questionnaire.')
p('2. Chapter IV — 4.1 Development and Testing','Heading2')
p('New subsection: '+loc('ISO_Results')+'. Search for “Table 24A”.','Note')
p('The new assessment table comes immediately after Table 24 and its legend. It connects your existing TC007 screening and fallback results to functional correctness and robustness. It identifies the two checks that still need separate observation records.')
p('3. References','Heading2')
p('Location: '+loc('ISO_Reference')+'. Search for “Evaluation Standard”.','Note')
p('The ISO/IEC 25059:2023 reference has been added for the new citation in Section 3.7.')
p('Small related changes are already done','Heading2')
p('Short passages in the abstract, Section 1.3, and Sections 5.1–5.3 now agree with the revised method and findings. “Eight” criteria was corrected to “six”, and the Chapter IV subtitle was corrected. The existing questionnaire, respondents, and survey tables are retained. Page references in the contents and lists were refreshed.')
p('What you still need to do','Heading2')
p('Record actual tests of (1) whether live AI explanations agree with the personnel and schedule data, and (2) whether the administrator can reject a recommendation, choose another eligible guard, and cancel without assigning anyone. Save the test date, conditions, actual outcome, and screenshot or log.')
p('Table 24A currently marks those interaction and explanation checks as Not assessed. After completing them, update those entries and the related Chapter V sentences using your actual observations. Remove the yellow highlighting when you have finished reviewing the edits.','Note')
body.appendChild(section)
parts['word/document.xml']=d.toxml(encoding='UTF-8')
styles=D.parseString(parts['word/styles.xml'])
for st in styles.getElementsByTagName('w:style'):
    sid=st.getAttribute('w:styleId')
    if sid in ['Normal','Heading2','Note']:
        for spacing in st.getElementsByTagName('w:spacing'):
            spacing.setAttribute('w:after','75')
            spacing.setAttribute('w:line','240')
            if sid=='Heading2':spacing.setAttribute('w:before','80')
        if sid=='Normal':
            for size in st.getElementsByTagName('w:sz'):size.setAttribute('w:val','22')
parts['word/styles.xml']=styles.toxml(encoding='UTF-8')
header=D.parseString(parts['word/header1.xml'])
header.getElementsByTagName('w:t')[0].firstChild.data='REVISEDPAPER.DOCX  |  SIMPLE EDIT MAP'
parts['word/header1.xml']=header.toxml(encoding='UTF-8')
footer=D.parseString(parts['word/footer1.xml'])
footer.getElementsByTagName('w:t')[0].firstChild.data='Sched • Guide to the highlighted paper edits                                       '
parts['word/footer1.xml']=footer.toxml(encoding='UTF-8')
core=D.parseString(parts['docProps/core.xml'])
core.getElementsByTagName('dc:title')[0].firstChild.data='Read This First: Changes to RevisedPaper.docx'
parts['docProps/core.xml']=core.toxml(encoding='UTF-8')
dest=ROOT/'Read_This_First_ISO25059_Changes.docx'
with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
    for n,data in parts.items():z.writestr(n,data)
print('Created',dest)
