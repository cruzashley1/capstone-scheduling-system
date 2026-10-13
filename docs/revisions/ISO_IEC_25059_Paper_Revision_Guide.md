
<!-- Guide page 1 -->

# Paper revision guide

> EDITING NOTE: ISO/IEC 25059:2023 • Testing and observation • Prepared 28 September 2026

A Scheduling and Duty Management System with AI Application in Absence Handling
Kaizen Security Agency Corp.

## What this revision changes

Add a supplementary assessment of the AI-assisted absence-handling feature through documented testing and observation. Retain the existing ISO/IEC 25010-based questionnaire, respondents, statistical treatment, and verified survey results. No additional ISO/IEC 25059 respondent questionnaire is proposed.

## Where to add or change text

| Paper location | Action | Guide page |
| --- | --- | --- |
| Chapter I: Scope and Delimitations | Add one paragraph describing the AI assessment and its limits. | 2 |
| Chapter II: Evaluation framework | Add a short discussion of ISO/IEC 25059 and cite the standard. | 2 |
| Chapter III: Methodology | Add the assessment method, observation record, scenarios, and analysis. Keep the existing survey method. | 3–4 |
| Chapter IV: Section 4.3, Development and Testing | Add an AI quality-assessment subsection before Section 4.4. Retain the survey-result tables. | 5 |
| Chapter V: Findings, conclusions, recommendations | Add the three short passages provided. The abstract addition is optional. | 6 |
| Appendices and references | Add the observation record and standard reference; renumber as needed. | 7–8 |

## How to use this document

Copy the manuscript passages and adapt heading, table, and appendix numbers to your final paper. Blue notes are editing instructions, not manuscript text. Bracketed fields require actual study information. Expected results in the proposed scenario table are test criteria, not findings.

> EDITING NOTE: Source limitation: the workspace contains drafts of Chapters I, IV, and V, preliminary pages, and presentation files. Chapter III and the complete final manuscript were not available. Chapter III text is therefore a new insertion, not a tracked replacement of your original wording. Some local drafts contain unfinished survey tables; retain the verified results from your final paper.

> EDITING NOTE: No new testing was performed for this revision. Chapter IV passages identify findings already reported in your draft and the evidence still needed. This package is an edited excerpt guide; it does not replace your complete paper.


<!-- Guide page 2 -->

# Chapter I and Chapter II additions

> EDITING NOTE: COPY the passages below. Add them at the stated locations; keep the four existing project objectives.

## Chapter I — Scope of the Study

> EDITING NOTE: ADD after the current Scope paragraph describing the platform and Gemini integration, before the feature list.

The evaluation covers both the overall software and the AI-assisted absence-handling feature. The existing ISO/IEC 25010-based questionnaire assesses the respondents’ ratings of the developed system. A supplementary technical assessment uses selected applicable ISO/IEC 25059:2023 quality characteristics to organize evidence from system testing and observation. This assessment focuses on functional correctness, robustness, transparency, and user controllability in the replacement-recommendation workflow. It uses test records and observed system behavior, without administering another questionnaire.

## Chapter I — Delimitations

> EDITING NOTE: ADD after the paragraph stating that the AI is advisory and the administrator confirms the assignment.

The AI quality assessment is limited to the selected characteristics, recorded scenarios, and system version examined. It does not establish full conformity with ISO/IEC 25059, demonstrate that AI recommendations are superior to rule-based ranking, or establish long-term operational benefits. Functional adaptability is outside the implemented evaluation scope because the project does not train or update the model from administrator decisions. Intervenability and societal and ethical risk mitigation are not separately established by this assessment; routine administrator confirmation alone does not demonstrate every aspect of these characteristics.

## Chapter II — Quality Framework for the AI Component

> EDITING NOTE: ADD under the discussion of software evaluation standards, immediately after the existing ISO/IEC 25010 discussion. If your school places this material in Chapter III, use it there once.

ISO/IEC 25059:2023 presents a quality model for AI systems within the Systems and Software Quality Requirements and Evaluation (SQuaRE) family. It supplies concepts for defining and evaluating AI quality (International Organization for Standardization [ISO] & International Electrotechnical Commission [IEC], 2023). In this study, the model provides a framework for examining the AI-assisted replacement workflow through recorded behavior. The selected characteristics guide what the researchers examine, while the project’s scheduling requirements determine the expected outcomes of individual test cases.

The assessment links functional correctness to compliance with independently checked eligibility requirements, robustness to preservation of required behavior under changed or adverse conditions, transparency to the information available for reviewing a recommendation, and user controllability to the administrator’s ability to determine the final assignment. These are study-specific applications of the selected characteristics. The observation record and pass criteria are designed for this project and are not presented as an official ISO questionnaire or scoring system.


<!-- Guide page 3 -->

# Chapter III — Assessment method

> EDITING NOTE: ADD after the existing evaluation procedure or testing-method discussion. This text supplements the existing questionnaire method.

## Supplementary Assessment of the AI-Assisted Feature

The study retains its descriptive-quantitative evaluation of respondent ratings through the existing ISO/IEC 25010-based instrument. The AI-assisted absence-handling feature is also examined through a supplementary technical assessment guided by selected ISO/IEC 25059:2023 quality characteristics. This component maps documented development-test results to functional correctness, robustness, transparency, and user controllability (ISO & IEC, 2023). Existing results are identified as previously reported evidence. Where the available records are insufficient, additional observations are required before a finding can be stated.

The unit of analysis for the supplementary assessment is a recorded test execution of the replacement workflow. It is distinct from an individual questionnaire response. The researchers act as test observers and compare actual behavior with expected behavior defined from the agency’s requirements. The existing IT expert and end-user sample remains the sample for the questionnaire; these respondents are not automatically treated as observers or participants in additional AI tests.

## Observation Record and Evidence

The instrument for this component is a structured test and observation record. Each record identifies the quality characteristic, scenario, input conditions, expected result, actual result, evidence reference, observer, execution date, and system version. The record also distinguishes live AI responses, simulated AI responses, rule-based fallback, and cached responses. Screenshots, output records, and test logs provide supporting evidence. The appendix provides the record format.

Expected eligibility is checked independently against the personnel, leave, absence, shift, post, and schedule records used in the test. The system-generated shortlist alone is not treated as proof that a guard is eligible. A recommendation is assessed against these constraints, while any claim that it is the best recommendation requires an additional, explicitly defined comparison method.

## Assessment Scope

The supplementary assessment addresses the implemented workflow surrounding the AI service as well as the recommendations and explanations it presents. Simulated responses can test validation, fallback, caching, and decision recording. They cannot establish the quality of recommendations generated by the live AI service. Live recommendations and their explanations therefore require their own recorded observations when conclusions about model output are drawn.

> EDITING NOTE: Editing note: this wording describes a supplementary mapping of existing tests. Do not state that ISO/IEC 25059 guided the original test design unless that is supported by your study records. If you perform additional tests, record their actual dates and add their results to Chapter IV.


<!-- Guide page 4 -->

# Chapter III — Procedure and analysis

> EDITING NOTE: ADD after the preceding subsection. This table defines proposed scenarios; it does not report completed tests.

## Test Procedure

For each scenario, the researchers specify the expected behavior, prepare controlled test data, execute the workflow, and compare the observed result with the stated criterion. Existing logs may be used when their inputs, version, and outputs are traceable. Missing evidence is identified explicitly. Additional tests use a controlled test environment. For live AI evaluation, the number of independent calls is set before execution and recorded; reopening a cached response is not counted as a new model trial.

| ID / characteristic | Scenario | Expected result / observation |
| --- | --- | --- |
| AI-01 / Functional correctness | Request a replacement with independently verified eligible and ineligible guards. | The shortlist and recommendation satisfy availability, conflict, shift, and post requirements. Record the rule ranking and any AI choice separately. |
| AI-02 / Robustness | Change an input that affects eligibility or ranking, then reopen the same absence. | The current candidate context is used. An outdated cached review is not presented as current. |
| AI-03 / Robustness | Simulate service unavailability, malformed output, and an unknown candidate ID as separate cases. | Unusable advice is not applied; the eligible rule ranking remains available when valid inputs permit it. Record each failure condition separately. |
| AI-04 / Robustness | Use missing required data or an empty eligible shortlist. | The workflow requests correction or reports that no eligible candidate exists; it does not invent or assign an ineligible guard. |
| AI-05 / Transparency | Inspect a live recommendation, its explanation, and the fallback display. | The user can distinguish AI advice from fallback. Stated reasons agree with the supplied records, and relevant limitations are communicated. |
| AI-06 / User controllability | Review the AI choice, select a different eligible guard, and cancel a separate attempt. | No assignment occurs before confirmation. The confirmed choice is applied; cancellation leaves the assignment unchanged. |

## Analysis and Interpretation

Findings are summarized by characteristic using expected-versus-actual comparisons, defects, and evidence references. A case is marked Met only when its criterion is supported by a recorded execution; Not met identifies a documented deviation; Not assessed identifies an unexecuted case or insufficient evidence. These are project reporting labels. Questionnaire weighted means and Likert interpretations are retained only for the respondent evaluation and are not applied to these test findings.

Where repeated trials are used, report the number meeting the criterion and the total assessed, together with the conditions and failures. Unassessed cases are reported separately. Results apply to the observed cases and do not constitute a universal AI accuracy or conformity rating.


<!-- Guide page 5 -->

# Chapter IV — Results and discussion

> EDITING NOTE: ADD at the end of Section 4.3, before Section 4.4 Evaluation Results. Use the next available subsection and table numbers.

## AI Quality Assessment Guided by ISO/IEC 25059:2023

The existing development-test findings were mapped to selected ISO/IEC 25059:2023 quality characteristics to identify the evidence available for the AI-assisted absence-handling feature. This supplementary assessment considers functional correctness, robustness, transparency, and user controllability. The mapping below distinguishes findings already reported in the development-test account from observations still needed to support a broader conclusion.

| Characteristic | Evidence already described in this chapter | Interpretation and remaining evidence |
| --- | --- | --- |
| Functional correctness | TC020 reports exclusion of ineligible candidates and scoring of the remaining guards. | Provides reported support for rule-based screening. Attach the test inputs and independent eligibility checks. The quality or superiority of the live AI ranking is not established by this result. |
| Robustness | TC022 reports preservation of the rule ranking when AI advice is unavailable. TC023 reports cache invalidation when the shortlist changes. | Supports workflow fallback and context handling within recorded conditions. The AI-review harness uses simulated responses; identify the exact conditions exercised and retain their logs. |
| Transparency | The absence-handling discussion describes a recommendation with an explanation. | Describes an implemented feature. An explanation’s presence does not establish its factual accuracy or usefulness. Record checks of live explanations against source data and the information shown to the administrator. |
| User controllability | The workflow describes administrator confirmation, and TC023 reports recording the decision against the recommendation. | Provides reported support for decision recording. Add evidence of rejecting advice, selecting another eligible guard, cancellation, and absence of assignment before confirmation. |

The reported fallback behavior indicates that replacement selection can continue through the rule-based workflow under the AI failure conditions exercised. It does not demonstrate that the AI model itself remains accurate during these conditions. Similarly, tests of cache handling and decision recording establish properties of the surrounding software rather than the quality of live model reasoning.

The available account therefore provides partial evidence for the selected characteristics. Stronger conclusions about live recommendations, explanations, and administrator control require the corresponding observation records. No overall ISO/IEC 25059 score is calculated. The ISO/IEC 25010 respondent ratings remain a separate source of evidence concerning the respondents’ assessment of the system.

> EDITING NOTE: Before submission: retain TC020–TC023 only if these IDs still match your final test table. Attach the underlying records, and replace descriptions of pending observations only after those observations are completed. This table adds no new pass counts or measured scores.


<!-- Guide page 6 -->

# Chapter V and abstract additions

> EDITING NOTE: COPY the applicable passages below. Keep your verified survey findings and existing operational limitations.

## Summary of Findings — AI Quality Assessment

> EDITING NOTE: ADD under Section 5.1.5 On Testing and System Quality, after the existing testing findings. Renumber findings if necessary.

A supplementary mapping of the development-test account to selected ISO/IEC 25059:2023 quality characteristics identified reported evidence for candidate screening, fallback to rule-based ranking, cache invalidation, and recording of administrator decisions. These findings concern the tested replacement workflow. The available account does not yet establish the quality of live AI recommendations and explanations or fully document the administrator’s rejection and cancellation actions. These aspects require the corresponding observation records before a complete finding can be reported for each selected characteristic.

## Conclusions — AI Quality

> EDITING NOTE: ADD to Section 5.2, following the existing conclusion on AI-assisted absence handling.

The reported testing supports the use of an advisory AI component within a workflow that screens candidates through rules and records the administrator’s decision. The ISO/IEC 25059-based mapping provides a structured way to describe this evidence and its limits. The present findings support only the behaviors documented in the available test account; they do not establish full conformity with the standard or demonstrate that the AI ranking is better than the rule-based ranking. Conclusions on recommendation quality, explanation accuracy, and user control should be extended only when supported by the additional recorded observations.

## Recommendations — Continued AI Evaluation

> EDITING NOTE: ADD to Section 5.3.2, or combine with the existing recommendations on administrator decisions and comparison of AI and rule rankings.

The researchers and system maintainers should retain a structured observation record for each AI-related test, including the system version, test conditions, expected behavior, actual output, and supporting evidence. Further testing should examine live explanations against the underlying personnel and schedule records, verify that administrators can reject or cancel recommendations, and test changed or incomplete inputs. Live AI recommendations and rule-based rankings should be compared against predefined criteria before claiming that AI improves selection quality. Relevant tests should be repeated after changes to the model, prompt, eligibility rules, or interface.

## Optional abstract addition

> EDITING NOTE: ADD after the sentence describing software testing and before the ISO/IEC 25010 survey results. Use once the supplementary mapping is included in Chapters III and IV.

A supplementary assessment mapped the documented AI-related tests to selected ISO/IEC 25059:2023 quality characteristics, identifying available evidence for the replacement workflow and gaps requiring further observation.

> EDITING NOTE: These passages deliberately describe the current evidence boundary. After completing additional observations, update Chapters IV and V together so that their findings and conclusions agree. Retain the original survey figures; none are recalculated in this guide.


<!-- Guide page 7 -->

# Appendix — Test and observation record

> EDITING NOTE: ADD as the next available appendix. Duplicate this form for each scenario and execution; it is completed by the test observer.

## AI-Assisted Absence Handling: Observation Record

| Record field | Entry |
| --- | --- |
| Test ID / execution number | [AI-01 to AI-06, plus execution number] |
| Quality characteristic | [Selected ISO/IEC 25059 characteristic] |
| Execution date / observer | [Actual date, time, and observer] |
| Application version / environment | [Build or commit; test environment] |
| AI configuration / response type | [Model and prompt version, if applicable; live, simulated, cached, or fallback] |
| Scenario / input reference | [Absence, station, shift, anonymized guards, schedules, availability, and evidence-file reference] |
| Independent expected outcome | [Eligibility checks and expected system behavior established before execution] |
| Steps performed | [Actions needed to reproduce this execution] |
| Actual output and observation | [What actually occurred, including ranking, explanation, or assignment changes] |
| Evidence references | [Screenshot, log, output file, or recording identifiers] |
| Finding | [Met / Not met / Not assessed, with a short justification] |
| Defect / follow-up / retest | [Issue reference, correction, retest date and result, or not applicable] |

## Recording instructions

Use expected outcomes as criteria, not as prefilled actual results. Record failed cases as well as successful ones. A screenshot of a displayed recommendation cannot by itself prove eligibility; attach the data used for independent checking. Record each simulated failure separately. Keep a cached response distinct from a new live model response.

For repeated trials, state the planned number of independent calls and report the actual number assessed. Where live recommendations vary, retain all assessed outputs. A difference in ranking is not automatically an error when more than one candidate meets the predefined requirements.

> EDITING NOTE: All bracketed entries on this page are blank fields for actual observations. They are not study results. Use anonymized test records in any appendix intended for distribution.


<!-- Guide page 8 -->

# Reference and source notes

> EDITING NOTE: COPY the reference into your bibliography. The remaining source notes are for editing and evidence checking.

## Reference to add

International Organization for Standardization, & International Electrotechnical Commission. (2023). Software engineering — Systems and software Quality Requirements and Evaluation (SQuaRE) — Quality model for AI systems (ISO/IEC Standard No. 25059:2023). https://www.iso.org/standard/80655.html

First in-text citation: (International Organization for Standardization [ISO] & International Electrotechnical Commission [IEC], 2023). Subsequent citation: (ISO & IEC, 2023). Adapt to your department’s required reference style.

## Basis for terminology

The standard’s official scope and publicly available definitions were checked through ISO’s catalogue and Online Browsing Platform. The selected characteristic names come from that source. The test scenarios, observation form, and interpretation labels in this guide are project-specific proposals; they are not reproduced ISO assessment instruments.

Official catalogue: https://www.iso.org/standard/80655.html
Official preview: https://www.iso.org/obp/ui#iso:std:iso-iec:25059:ed-1:v1:en

## Local material used to tailor the revisions

| Source | Relevant location / use |
| --- | --- |
| docs/Chapter1_Revised.md | Sections 1.4 and 1.5: current objectives, scope, and advisory AI boundary. |
| docs/Chapter4_Results_and_Discussions.md | Section 4.2.2 and Section 4.3, TC020–TC023: reported screening, fallback, cache, and decision-recording findings. |
| docs/Chapter5_Summary_Conclusions_Recommendations.md | Sections 5.1.2, 5.1.5, 5.2, and 5.3: findings, conclusions, and follow-up evaluation. |
| backend_python/testing_ai_review.py | Inspection confirms that the harness substitutes simulated responses for Gemini. It was not executed for this revision. |
| presentation/Capstone_Defense_Presentation.pptx and presentation/Speaker_Notes.md | Context for the existing questionnaire evaluation and differences between local drafts and the final manuscript. |

## Final editing checks

Match subsection, table, appendix, and test-case numbers to the final manuscript. Preserve the standard edition already used for the existing ISO/IEC 25010 instrument. Keep survey means separate from test observations. Fill bracketed fields only with recorded information, and keep future work in future tense. Claims about the tests should be traceable to the relevant logs or observations.
