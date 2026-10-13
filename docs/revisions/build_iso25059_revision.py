"""Build the standalone paper revision package using the Python standard library."""
from pathlib import Path
from datetime import datetime, timezone
from html import escape
import zipfile
import xml.etree.ElementTree as ET

OUT = Path(__file__).resolve().parent
NAME = "ISO_IEC_25059_Paper_Revision_Guide"
pages = []


def page(title, subtitle):
    blocks = [("title", title), ("note", subtitle)]
    pages.append(blocks)
    return blocks


def p(blocks, text):
    blocks.append(("p", text))


def h(blocks, text):
    blocks.append(("h", text))


def note(blocks, text):
    blocks.append(("note", text))


def table(blocks, heads, rows, widths):
    blocks.append(("table", heads, rows, widths))


b = page("Paper revision guide", "ISO/IEC 25059:2023 • Testing and observation • Prepared 28 September 2026")
p(b, "A Scheduling and Duty Management System with AI Application in Absence Handling\nKaizen Security Agency Corp.")
h(b, "What this revision changes")
p(b, "Add a supplementary assessment of the AI-assisted absence-handling feature through documented testing and observation. Retain the existing ISO/IEC 25010-based questionnaire, respondents, statistical treatment, and verified survey results. No additional ISO/IEC 25059 respondent questionnaire is proposed.")
h(b, "Where to add or change text")
table(b, ["Paper location", "Action", "Guide page"], [
    ["Chapter I: Scope and Delimitations", "Add one paragraph describing the AI assessment and its limits.", "2"],
    ["Chapter II: Evaluation framework", "Add a short discussion of ISO/IEC 25059 and cite the standard.", "2"],
    ["Chapter III: Methodology", "Add the assessment method, observation record, scenarios, and analysis. Keep the existing survey method.", "3–4"],
    ["Chapter IV: Section 4.3, Development and Testing", "Add an AI quality-assessment subsection before Section 4.4. Retain the survey-result tables.", "5"],
    ["Chapter V: Findings, conclusions, recommendations", "Add the three short passages provided. The abstract addition is optional.", "6"],
    ["Appendices and references", "Add the observation record and standard reference; renumber as needed.", "7–8"],
], [31, 57, 12])
h(b, "How to use this document")
p(b, "Copy the manuscript passages and adapt heading, table, and appendix numbers to your final paper. Blue notes are editing instructions, not manuscript text. Bracketed fields require actual study information. Expected results in the proposed scenario table are test criteria, not findings.")
note(b, "Source limitation: the workspace contains drafts of Chapters I, IV, and V, preliminary pages, and presentation files. Chapter III and the complete final manuscript were not available. Chapter III text is therefore a new insertion, not a tracked replacement of your original wording. Some local drafts contain unfinished survey tables; retain the verified results from your final paper.")
note(b, "No new testing was performed for this revision. Chapter IV passages identify findings already reported in your draft and the evidence still needed. This package is an edited excerpt guide; it does not replace your complete paper.")

b = page("Chapter I and Chapter II additions", "COPY the passages below. Add them at the stated locations; keep the four existing project objectives.")
h(b, "Chapter I — Scope of the Study")
note(b, "ADD after the current Scope paragraph describing the platform and Gemini integration, before the feature list.")
p(b, "The evaluation covers both the overall software and the AI-assisted absence-handling feature. The existing ISO/IEC 25010-based questionnaire assesses the respondents’ ratings of the developed system. A supplementary technical assessment uses selected applicable ISO/IEC 25059:2023 quality characteristics to organize evidence from system testing and observation. This assessment focuses on functional correctness, robustness, transparency, and user controllability in the replacement-recommendation workflow. It uses test records and observed system behavior, without administering another questionnaire.")
h(b, "Chapter I — Delimitations")
note(b, "ADD after the paragraph stating that the AI is advisory and the administrator confirms the assignment.")
p(b, "The AI quality assessment is limited to the selected characteristics, recorded scenarios, and system version examined. It does not establish full conformity with ISO/IEC 25059, demonstrate that AI recommendations are superior to rule-based ranking, or establish long-term operational benefits. Functional adaptability is outside the implemented evaluation scope because the project does not train or update the model from administrator decisions. Intervenability and societal and ethical risk mitigation are not separately established by this assessment; routine administrator confirmation alone does not demonstrate every aspect of these characteristics.")
h(b, "Chapter II — Quality Framework for the AI Component")
note(b, "ADD under the discussion of software evaluation standards, immediately after the existing ISO/IEC 25010 discussion. If your school places this material in Chapter III, use it there once.")
p(b, "ISO/IEC 25059:2023 presents a quality model for AI systems within the Systems and Software Quality Requirements and Evaluation (SQuaRE) family. It supplies concepts for defining and evaluating AI quality (International Organization for Standardization [ISO] & International Electrotechnical Commission [IEC], 2023). In this study, the model provides a framework for examining the AI-assisted replacement workflow through recorded behavior. The selected characteristics guide what the researchers examine, while the project’s scheduling requirements determine the expected outcomes of individual test cases.")
p(b, "The assessment links functional correctness to compliance with independently checked eligibility requirements, robustness to preservation of required behavior under changed or adverse conditions, transparency to the information available for reviewing a recommendation, and user controllability to the administrator’s ability to determine the final assignment. These are study-specific applications of the selected characteristics. The observation record and pass criteria are designed for this project and are not presented as an official ISO questionnaire or scoring system.")

b = page("Chapter III — Assessment method", "ADD after the existing evaluation procedure or testing-method discussion. This text supplements the existing questionnaire method.")
h(b, "Supplementary Assessment of the AI-Assisted Feature")
p(b, "The study retains its descriptive-quantitative evaluation of respondent ratings through the existing ISO/IEC 25010-based instrument. The AI-assisted absence-handling feature is also examined through a supplementary technical assessment guided by selected ISO/IEC 25059:2023 quality characteristics. This component maps documented development-test results to functional correctness, robustness, transparency, and user controllability (ISO & IEC, 2023). Existing results are identified as previously reported evidence. Where the available records are insufficient, additional observations are required before a finding can be stated.")
p(b, "The unit of analysis for the supplementary assessment is a recorded test execution of the replacement workflow. It is distinct from an individual questionnaire response. The researchers act as test observers and compare actual behavior with expected behavior defined from the agency’s requirements. The existing IT expert and end-user sample remains the sample for the questionnaire; these respondents are not automatically treated as observers or participants in additional AI tests.")
h(b, "Observation Record and Evidence")
p(b, "The instrument for this component is a structured test and observation record. Each record identifies the quality characteristic, scenario, input conditions, expected result, actual result, evidence reference, observer, execution date, and system version. The record also distinguishes live AI responses, simulated AI responses, rule-based fallback, and cached responses. Screenshots, output records, and test logs provide supporting evidence. The appendix provides the record format.")
p(b, "Expected eligibility is checked independently against the personnel, leave, absence, shift, post, and schedule records used in the test. The system-generated shortlist alone is not treated as proof that a guard is eligible. A recommendation is assessed against these constraints, while any claim that it is the best recommendation requires an additional, explicitly defined comparison method.")
h(b, "Assessment Scope")
p(b, "The supplementary assessment addresses the implemented workflow surrounding the AI service as well as the recommendations and explanations it presents. Simulated responses can test validation, fallback, caching, and decision recording. They cannot establish the quality of recommendations generated by the live AI service. Live recommendations and their explanations therefore require their own recorded observations when conclusions about model output are drawn.")
note(b, "Editing note: this wording describes a supplementary mapping of existing tests. Do not state that ISO/IEC 25059 guided the original test design unless that is supported by your study records. If you perform additional tests, record their actual dates and add their results to Chapter IV.")

b = page("Chapter III — Procedure and analysis", "ADD after the preceding subsection. This table defines proposed scenarios; it does not report completed tests.")
h(b, "Test Procedure")
p(b, "For each scenario, the researchers specify the expected behavior, prepare controlled test data, execute the workflow, and compare the observed result with the stated criterion. Existing logs may be used when their inputs, version, and outputs are traceable. Missing evidence is identified explicitly. Additional tests use a controlled test environment. For live AI evaluation, the number of independent calls is set before execution and recorded; reopening a cached response is not counted as a new model trial.")
table(b, ["ID / characteristic", "Scenario", "Expected result / observation"], [
    ["AI-01\nFunctional correctness", "Request a replacement with independently verified eligible and ineligible guards.", "The shortlist and recommendation satisfy availability, conflict, shift, and post requirements. Record the rule ranking and any AI choice separately."],
    ["AI-02\nRobustness", "Change an input that affects eligibility or ranking, then reopen the same absence.", "The current candidate context is used. An outdated cached review is not presented as current."],
    ["AI-03\nRobustness", "Simulate service unavailability, malformed output, and an unknown candidate ID as separate cases.", "Unusable advice is not applied; the eligible rule ranking remains available when valid inputs permit it. Record each failure condition separately."],
    ["AI-04\nRobustness", "Use missing required data or an empty eligible shortlist.", "The workflow requests correction or reports that no eligible candidate exists; it does not invent or assign an ineligible guard."],
    ["AI-05\nTransparency", "Inspect a live recommendation, its explanation, and the fallback display.", "The user can distinguish AI advice from fallback. Stated reasons agree with the supplied records, and relevant limitations are communicated."],
    ["AI-06\nUser controllability", "Review the AI choice, select a different eligible guard, and cancel a separate attempt.", "No assignment occurs before confirmation. The confirmed choice is applied; cancellation leaves the assignment unchanged."],
], [23, 32, 45])
h(b, "Analysis and Interpretation")
p(b, "Findings are summarized by characteristic using expected-versus-actual comparisons, defects, and evidence references. A case is marked Met only when its criterion is supported by a recorded execution; Not met identifies a documented deviation; Not assessed identifies an unexecuted case or insufficient evidence. These are project reporting labels. Questionnaire weighted means and Likert interpretations are retained only for the respondent evaluation and are not applied to these test findings.")
p(b, "Where repeated trials are used, report the number meeting the criterion and the total assessed, together with the conditions and failures. Unassessed cases are reported separately. Results apply to the observed cases and do not constitute a universal AI accuracy or conformity rating.")

b = page("Chapter IV — Results and discussion", "ADD at the end of Section 4.3, before Section 4.4 Evaluation Results. Use the next available subsection and table numbers.")
h(b, "AI Quality Assessment Guided by ISO/IEC 25059:2023")
p(b, "The existing development-test findings were mapped to selected ISO/IEC 25059:2023 quality characteristics to identify the evidence available for the AI-assisted absence-handling feature. This supplementary assessment considers functional correctness, robustness, transparency, and user controllability. The mapping below distinguishes findings already reported in the development-test account from observations still needed to support a broader conclusion.")
table(b, ["Characteristic", "Evidence already described in this chapter", "Interpretation and remaining evidence"], [
    ["Functional correctness", "TC020 reports exclusion of ineligible candidates and scoring of the remaining guards.", "Provides reported support for rule-based screening. Attach the test inputs and independent eligibility checks. The quality or superiority of the live AI ranking is not established by this result."],
    ["Robustness", "TC022 reports preservation of the rule ranking when AI advice is unavailable. TC023 reports cache invalidation when the shortlist changes.", "Supports workflow fallback and context handling within recorded conditions. The AI-review harness uses simulated responses; identify the exact conditions exercised and retain their logs."],
    ["Transparency", "The absence-handling discussion describes a recommendation with an explanation.", "Describes an implemented feature. An explanation’s presence does not establish its factual accuracy or usefulness. Record checks of live explanations against source data and the information shown to the administrator."],
    ["User controllability", "The workflow describes administrator confirmation, and TC023 reports recording the decision against the recommendation.", "Provides reported support for decision recording. Add evidence of rejecting advice, selecting another eligible guard, cancellation, and absence of assignment before confirmation."],
], [20, 35, 45])
p(b, "The reported fallback behavior indicates that replacement selection can continue through the rule-based workflow under the AI failure conditions exercised. It does not demonstrate that the AI model itself remains accurate during these conditions. Similarly, tests of cache handling and decision recording establish properties of the surrounding software rather than the quality of live model reasoning.")
p(b, "The available account therefore provides partial evidence for the selected characteristics. Stronger conclusions about live recommendations, explanations, and administrator control require the corresponding observation records. No overall ISO/IEC 25059 score is calculated. The ISO/IEC 25010 respondent ratings remain a separate source of evidence concerning the respondents’ assessment of the system.")
note(b, "Before submission: retain TC020–TC023 only if these IDs still match your final test table. Attach the underlying records, and replace descriptions of pending observations only after those observations are completed. This table adds no new pass counts or measured scores.")

b = page("Chapter V and abstract additions", "COPY the applicable passages below. Keep your verified survey findings and existing operational limitations.")
h(b, "Summary of Findings — AI Quality Assessment")
note(b, "ADD under Section 5.1.5 On Testing and System Quality, after the existing testing findings. Renumber findings if necessary.")
p(b, "A supplementary mapping of the development-test account to selected ISO/IEC 25059:2023 quality characteristics identified reported evidence for candidate screening, fallback to rule-based ranking, cache invalidation, and recording of administrator decisions. These findings concern the tested replacement workflow. The available account does not yet establish the quality of live AI recommendations and explanations or fully document the administrator’s rejection and cancellation actions. These aspects require the corresponding observation records before a complete finding can be reported for each selected characteristic.")
h(b, "Conclusions — AI Quality")
note(b, "ADD to Section 5.2, following the existing conclusion on AI-assisted absence handling.")
p(b, "The reported testing supports the use of an advisory AI component within a workflow that screens candidates through rules and records the administrator’s decision. The ISO/IEC 25059-based mapping provides a structured way to describe this evidence and its limits. The present findings support only the behaviors documented in the available test account; they do not establish full conformity with the standard or demonstrate that the AI ranking is better than the rule-based ranking. Conclusions on recommendation quality, explanation accuracy, and user control should be extended only when supported by the additional recorded observations.")
h(b, "Recommendations — Continued AI Evaluation")
note(b, "ADD to Section 5.3.2, or combine with the existing recommendations on administrator decisions and comparison of AI and rule rankings.")
p(b, "The researchers and system maintainers should retain a structured observation record for each AI-related test, including the system version, test conditions, expected behavior, actual output, and supporting evidence. Further testing should examine live explanations against the underlying personnel and schedule records, verify that administrators can reject or cancel recommendations, and test changed or incomplete inputs. Live AI recommendations and rule-based rankings should be compared against predefined criteria before claiming that AI improves selection quality. Relevant tests should be repeated after changes to the model, prompt, eligibility rules, or interface.")
h(b, "Optional abstract addition")
note(b, "ADD after the sentence describing software testing and before the ISO/IEC 25010 survey results. Use once the supplementary mapping is included in Chapters III and IV.")
p(b, "A supplementary assessment mapped the documented AI-related tests to selected ISO/IEC 25059:2023 quality characteristics, identifying available evidence for the replacement workflow and gaps requiring further observation.")
note(b, "These passages deliberately describe the current evidence boundary. After completing additional observations, update Chapters IV and V together so that their findings and conclusions agree. Retain the original survey figures; none are recalculated in this guide.")

b = page("Appendix — Test and observation record", "ADD as the next available appendix. Duplicate this form for each scenario and execution; it is completed by the test observer.")
h(b, "AI-Assisted Absence Handling: Observation Record")
table(b, ["Record field", "Entry"], [
    ["Test ID / execution number", "[AI-01 to AI-06, plus execution number]"],
    ["Quality characteristic", "[Selected ISO/IEC 25059 characteristic]"],
    ["Execution date / observer", "[Actual date, time, and observer]"],
    ["Application version / environment", "[Build or commit; test environment]"],
    ["AI configuration / response type", "[Model and prompt version, if applicable; live, simulated, cached, or fallback]"],
    ["Scenario / input reference", "[Absence, station, shift, anonymized guards, schedules, availability, and evidence-file reference]"],
    ["Independent expected outcome", "[Eligibility checks and expected system behavior established before execution]"],
    ["Steps performed", "[Actions needed to reproduce this execution]"],
    ["Actual output and observation", "[What actually occurred, including ranking, explanation, or assignment changes]"],
    ["Evidence references", "[Screenshot, log, output file, or recording identifiers]"],
    ["Finding", "[Met / Not met / Not assessed, with a short justification]"],
    ["Defect / follow-up / retest", "[Issue reference, correction, retest date and result, or not applicable]"],
], [35, 65])
h(b, "Recording instructions")
p(b, "Use expected outcomes as criteria, not as prefilled actual results. Record failed cases as well as successful ones. A screenshot of a displayed recommendation cannot by itself prove eligibility; attach the data used for independent checking. Record each simulated failure separately. Keep a cached response distinct from a new live model response.")
p(b, "For repeated trials, state the planned number of independent calls and report the actual number assessed. Where live recommendations vary, retain all assessed outputs. A difference in ranking is not automatically an error when more than one candidate meets the predefined requirements.")
note(b, "All bracketed entries on this page are blank fields for actual observations. They are not study results. Use anonymized test records in any appendix intended for distribution.")

b = page("Reference and source notes", "COPY the reference into your bibliography. The remaining source notes are for editing and evidence checking.")
h(b, "Reference to add")
p(b, "International Organization for Standardization, & International Electrotechnical Commission. (2023). Software engineering — Systems and software Quality Requirements and Evaluation (SQuaRE) — Quality model for AI systems (ISO/IEC Standard No. 25059:2023). https://www.iso.org/standard/80655.html")
p(b, "First in-text citation: (International Organization for Standardization [ISO] & International Electrotechnical Commission [IEC], 2023). Subsequent citation: (ISO & IEC, 2023). Adapt to your department’s required reference style.")
h(b, "Basis for terminology")
p(b, "The standard’s official scope and publicly available definitions were checked through ISO’s catalogue and Online Browsing Platform. The selected characteristic names come from that source. The test scenarios, observation form, and interpretation labels in this guide are project-specific proposals; they are not reproduced ISO assessment instruments.")
p(b, "Official catalogue: https://www.iso.org/standard/80655.html\nOfficial preview: https://www.iso.org/obp/ui#iso:std:iso-iec:25059:ed-1:v1:en")
h(b, "Local material used to tailor the revisions")
table(b, ["Source", "Relevant location / use"], [
    ["docs/Chapter1_Revised.md", "Sections 1.4 and 1.5: current objectives, scope, and advisory AI boundary."],
    ["docs/Chapter4_Results_and_Discussions.md", "Section 4.2.2 and Section 4.3, TC020–TC023: reported screening, fallback, cache, and decision-recording findings."],
    ["docs/Chapter5_Summary_Conclusions_Recommendations.md", "Sections 5.1.2, 5.1.5, 5.2, and 5.3: findings, conclusions, and follow-up evaluation."],
    ["backend_python/testing_ai_review.py", "Inspection confirms that the harness substitutes simulated responses for Gemini. It was not executed for this revision."],
    ["presentation/Capstone_Defense_Presentation.pptx and presentation/Speaker_Notes.md", "Context for the existing questionnaire evaluation and differences between local drafts and the final manuscript."],
], [48, 52])
h(b, "Final editing checks")
p(b, "Match subsection, table, appendix, and test-case numbers to the final manuscript. Preserve the standard edition already used for the existing ISO/IEC 25010 instrument. Keep survey means separate from test observations. Fill bracketed fields only with recorded information, and keep future work in future tense. Claims about the tests should be traceable to the relevant logs or observations.")


# Minimal, fully editable Office Open XML document.
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
XML = "http://www.w3.org/XML/1998/namespace"
ET.register_namespace("w", W)
ET.register_namespace("r", R)


def node(tag, **attrs):
    return ET.Element(f"{{{W}}}{tag}", {f"{{{W}}}{k}": str(v) for k, v in attrs.items()})


def sub(parent, tag, **attrs):
    el = node(tag, **attrs)
    parent.append(el)
    return el


def paragraph(parent, text, style="Normal"):
    para = sub(parent, "p")
    props = sub(para, "pPr")
    sub(props, "pStyle", val=style)
    for index, part in enumerate(text.split("\n")):
        run = sub(para, "r")
        if index:
            sub(run, "br")
        el = sub(run, "t")
        el.set(f"{{{XML}}}space", "preserve")
        el.text = part
    return para


def make_table(parent, heads, rows, widths):
    tbl = sub(parent, "tbl")
    props = sub(tbl, "tblPr")
    sub(props, "tblW", w=9826, type="dxa")
    sub(props, "tblLayout", type="fixed")
    margins = sub(props, "tblCellMar")
    for side in ["top", "left", "bottom", "right"]:
        sub(margins, side, w=90, type="dxa")
    borders = sub(props, "tblBorders")
    for side in ["top", "left", "bottom", "right", "insideH", "insideV"]:
        sub(borders, side, val="single", sz=4, color="D5DEE5")
    grid = sub(tbl, "tblGrid")
    tw = [round(9826 * pct / 100) for pct in widths]
    for width in tw:
        sub(grid, "gridCol", w=width)
    for i, row in enumerate([heads] + rows):
        tr = sub(tbl, "tr")
        rp = sub(tr, "trPr")
        sub(rp, "cantSplit")
        if i == 0:
            sub(rp, "tblHeader")
        for j, text in enumerate(row):
            cell = sub(tr, "tc")
            cp = sub(cell, "tcPr")
            sub(cp, "tcW", w=tw[j], type="dxa")
            sub(cp, "vAlign", val="top")
            sub(cp, "shd", fill="173D50" if i == 0 else ("F2F6F8" if i % 2 == 1 else "FFFFFF"), val="clear")
            paragraph(cell, text, "TableHead" if i == 0 else "TableText")
    paragraph(parent, "", "Spacer")


document = node("document")
body = sub(document, "body")
for index, blocks in enumerate(pages):
    if index:
        para = sub(body, "p")
        props = sub(para, "pPr")
        sub(props, "spacing", before=0, after=0, line=20, lineRule="exact")
        run = sub(para, "r")
        sub(run, "br", type="page")
    for block in blocks:
        if block[0] == "table":
            make_table(body, *block[1:])
        else:
            paragraph(body, block[1], {"title": "Title", "note": "Note", "h": "Heading2", "p": "Normal"}[block[0]])
section = sub(body, "sectPr")
header_ref = sub(section, "headerReference", type="default")
header_ref.set(f"{{{R}}}id", "rId2")
footer_ref = sub(section, "footerReference", type="default")
footer_ref.set(f"{{{R}}}id", "rId3")
sub(section, "pgSz", w=11906, h=16838)
sub(section, "pgMar", top=900, right=1040, bottom=900, left=1040, header=400, footer=400, gutter=0)

styles = node("styles")
defaults = sub(styles, "docDefaults")
rp = sub(sub(defaults, "rPrDefault"), "rPr")
sub(rp, "rFonts", ascii="Times New Roman", hAnsi="Times New Roman")
sub(rp, "sz", val=23)
sub(rp, "lang", val="en-PH")
pp = sub(sub(defaults, "pPrDefault"), "pPr")
sub(pp, "spacing", after=115, line=260, lineRule="auto")
sub(pp, "widowControl")


def style(sid, name, font, size, color="18242C", bold=False, after=115, before=0, keep=False):
    st = sub(styles, "style", type="paragraph", styleId=sid)
    if sid == "Normal":
        st.set(f"{{{W}}}default", "1")
    sub(st, "name", val=name)
    if sid != "Normal":
        sub(st, "basedOn", val="Normal")
    sub(st, "next", val="Normal")
    pr = sub(st, "pPr")
    sub(pr, "spacing", before=before, after=after, line=250 if "Table" in sid else 260, lineRule="auto")
    if keep:
        sub(pr, "keepNext")
    rp = sub(st, "rPr")
    sub(rp, "rFonts", ascii=font, hAnsi=font)
    sub(rp, "sz", val=size)
    sub(rp, "color", val=color)
    if bold:
        sub(rp, "b")
    return st


style("Normal", "Normal", "Times New Roman", 23)
style("Title", "Title", "Calibri", 35, "173D50", True, after=160, keep=True)
style("Heading2", "Heading 2", "Calibri", 25, "173D50", True, after=90, before=100, keep=True)
st = style("Note", "Editing instruction", "Calibri", 19, "36586B", after=110)
sub(st.find(f"{{{W}}}pPr"), "shd", fill="EDF4F8", val="clear")
style("TableText", "Table text", "Calibri", 20, after=30)
style("TableHead", "Table heading", "Calibri", 20, "FFFFFF", True, after=30)
style("Spacer", "Spacer", "Calibri", 4, after=15)
style("Header", "Header", "Calibri", 17, "607582", after=0)

header = node("hdr")
paragraph(header, "ISO/IEC 25059:2023  |  PAPER REVISION GUIDE", "Header")
footer = node("ftr")
foot = paragraph(footer, "Sched • Edited excerpts and observation record                                      ", "Header")
field = sub(foot, "fldSimple", instr="PAGE")
sub(sub(field, "r"), "t").text = "1"
settings = node("settings")
sub(settings, "updateFields", val="true")


def xml(el):
    return ET.tostring(el, encoding="utf-8", xml_declaration=True)


content_types = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>'''
relationships = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>'''
doc_relationships = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
</Relationships>'''
core = '''<?xml version="1.0" encoding="UTF-8"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>ISO/IEC 25059 Paper Revision Guide</dc:title>
<dc:subject>Testing and observation revisions for the Sched capstone paper</dc:subject>
<dc:creator>Capstone revision assistance</dc:creator>
<dc:description>Edited excerpts, insertion notes, and an observation record. No new test results are asserted.</dc:description>
</cp:coreProperties>'''
OUT.mkdir(parents=True, exist_ok=True)
docx_path = OUT / (NAME + ".docx")
with zipfile.ZipFile(docx_path, "w", zipfile.ZIP_DEFLATED) as z:
    for name, content in {
        "[Content_Types].xml": content_types,
        "_rels/.rels": relationships,
        "word/document.xml": xml(document),
        "word/styles.xml": xml(styles),
        "word/settings.xml": xml(settings),
        "word/header1.xml": xml(header),
        "word/footer1.xml": xml(footer),
        "word/_rels/document.xml.rels": doc_relationships,
        "docProps/core.xml": core,
    }.items():
        z.writestr(name, content)

# HTML is a review/print fallback; Markdown retains the editable source text.
html = ['<!doctype html><html lang="en"><head><meta charset="utf-8"><title>ISO/IEC 25059 Paper Revision Guide</title><style>']
html.append('''@page{size:A4;margin:16mm 18mm}body{margin:0;color:#18242c;font:11.5pt/1.16 "Times New Roman",serif}section{break-after:page}section:last-child{break-after:auto}h1{font:700 18pt Calibri,Arial,sans-serif;color:#173d50;margin:0 0 10pt}h2{font:700 12.5pt Calibri,Arial,sans-serif;color:#173d50;margin:10pt 0 5pt;break-after:avoid}p{margin:0 0 7pt}.note{font:9.5pt/1.16 Calibri,Arial,sans-serif;background:#edf4f8;color:#36586b;padding:4pt 6pt}table{border-collapse:collapse;width:100%;table-layout:fixed;margin:6pt 0 9pt;font:10pt/1.12 Calibri,Arial,sans-serif}td,th{border:0.5pt solid #d5dee5;padding:5pt;vertical-align:top;overflow-wrap:anywhere}th{background:#173d50;color:white;text-align:left}tr:nth-child(even){background:#f2f6f8}tr{break-inside:avoid}thead{display:table-header-group}.running{font:8pt Calibri,Arial,sans-serif;color:#607582;margin:0 0 12pt}''')
html.append('</style></head><body>')
md = []
for index, blocks in enumerate(pages, 1):
    html.append('<section><div class="running">ISO/IEC 25059:2023 | PAPER REVISION GUIDE</div>')
    md.append(f"\n<!-- Guide page {index} -->\n")
    for block in blocks:
        kind = block[0]
        if kind == "table":
            heads, rows, widths = block[1:]
            html.append('<table><colgroup>' + ''.join(f'<col style="width:{w}%">' for w in widths) + '</colgroup><thead><tr>')
            html.append(''.join('<th>' + escape(t).replace('\n','<br>') + '</th>' for t in heads) + '</tr></thead><tbody>')
            for row in rows:
                html.append('<tr>' + ''.join('<td>' + escape(t).replace('\n','<br>') + '</td>' for t in row) + '</tr>')
            html.append('</tbody></table>')
            md.append('| ' + ' | '.join(heads) + ' |\n| ' + ' | '.join('---' for _ in heads) + ' |')
            for row in rows:
                md.append('| ' + ' | '.join(t.replace('\n',' / ') for t in row) + ' |')
            md.append('')
        else:
            tag = {"title":"h1", "h":"h2", "p":"p", "note":"p"}[kind]
            cls = ' class="note"' if kind == "note" else ''
            html.append(f'<{tag}{cls}>' + escape(block[1]).replace('\n','<br>') + f'</{tag}>')
            md.append({"title":"# ", "h":"## ", "p":"", "note":"> EDITING NOTE: "}[kind] + block[1] + '\n')
    html.append('</section>')
html.append('</body></html>')
(OUT / (NAME + '.html')).write_text('\n'.join(html), encoding='utf-8')
(OUT / (NAME + '.md')).write_text('\n'.join(md), encoding='utf-8')

with zipfile.ZipFile(docx_path) as z:
    for entry in z.namelist():
        if entry.endswith('.xml') or entry.endswith('.rels'):
            ET.fromstring(z.read(entry))
    assert z.testzip() is None
print(f'Created and XML-validated: {docx_path}')
print(f'Content sections: {len(pages)}')
for i, blocks in enumerate(pages, 1):
    words = sum(len(block[1].split()) if block[0] != 'table' else sum(len(t.split()) for row in [block[1]] + block[2] for t in row) for block in blocks)
    print(f'Section {i}: {words} words')
