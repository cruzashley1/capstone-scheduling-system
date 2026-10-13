# Capstone defense speaker notes

24 slides | Suggested delivery: 18.0 minutes, excluding Q&A.

Prepared from the supplied manuscript. Academic results are reported values; application benchmarks and tests were not rerun to produce these slides.

## 01. Title
Suggested time: 25 seconds

Introduce the researchers and the study. Our project supports the scheduling office of Kaizen Security Agency Corp. and personnel deployed to LRT stations. The presentation explains the operational problem, development approach, implemented solution, reported evaluation results, and limitations.

Sources: Manuscript title page (PDF p. 1).

## 02. Project context
Suggested time: 40 seconds

Explain the existing workflow: administrators prepare spreadsheets, distribute files, and search for available replacements when someone is absent. Each station has different staffing needs, so a general calendar is insufficient. The study focuses on both planned scheduling and the daily changes caused by absences.

Defense note: use 25 stations as the operational scope. The 573 figure elsewhere in the manuscript is a deployed personnel-record count, not the evaluation sample. Counts visible in appendix screenshots reflect different data snapshots.

Sources: Manuscript Ch. I, PDF pp. 16–23; Ch. V, PDF pp. 139–142.

## 03. Objectives
Suggested time: 45 seconds

Walk through the four objectives in order. Objective 1 concerns roster constraints. Objective 2 concerns selection among eligible candidates. Objective 3 concerns the operational replacement process, while Objective 4 concerns user access and acceptance.

Defense note: do not claim a measured reduction in overtime. The manuscript provides processing benchmarks and workflow improvements, but no comparable before-and-after field timing for replacement arrival or shift extensions.

Sources: Manuscript Ch. I, PDF pp. 17–18; Ch. V, PDF pp. 139–147.

## 04. Scope and delimitations
Suggested time: 45 seconds

The project serves the agency’s LRT security operations. Attendance is reported by head guards rather than captured through biometrics or location tracking. All notification features described here are in-app. Guards can view published schedules, submit requests, and volunteer to cover a rest-day duty.

Key terms: a post is a named duty position; a reliever covers eligible duty gaps or rest days; an absence replacement is an administrator-confirmed assignment. The 15-day period is the manuscript’s operational meaning of bi-weekly. Internet connectivity is required for the deployed service.

Sources: Manuscript Ch. I, PDF pp. 18–28; local README.md.

## 05. Significance
Suggested time: 35 seconds

Relate each benefit to a real user. Administrators gain one place to prepare and update schedules. Security personnel can check duty information without requesting a spreadsheet. The agency gains better visibility of uncovered posts. The researchers gain experience integrating a cross-platform client, scheduling service, database, and optional AI review.

Frame reduced fatigue and extended-duty exposure as intended operational benefits. Long-term effects require follow-up measurement.

Sources: Manuscript Ch. I, PDF pp. 24–25.

## 06. Related literature
Suggested time: 40 seconds

Summarize themes rather than reciting every author. As reviewed in the manuscript, local literature emphasizes workload allocation and organizational readiness, while foreign literature links scheduling quality with coverage and employee workload. These ideas motivate configurable staffing requirements, clear duty information, and administrator control.

Citation note: these are summaries of the literature review supplied in the paper. The presentation does not independently verify the original publications or add external literature.

Sources: Manuscript Ch. II, PDF pp. 29–35; references, PDF pp. 148–155.

## 07. Related studies and research gap
Suggested time: 50 seconds

Use the three examples to separate scheduling, preference-aware placement, and absence prediction. The manuscript’s synthesis identifies a need for an integrated operational response when an absence occurs. Our implementation connects absence reporting, eligibility screening, recommendation, administrator approval, schedule update, and notification.

Defense note: the contribution is this integration in the agency’s setting. Do not claim the first such system worldwide. The project does not train a model to predict absenteeism; the predictive study is related work only.

Sources: Manuscript Ch. II, PDF pp. 38, 43, 45–46.

## 08. Research and development method
Suggested time: 45 seconds

Explain the four phases using one example: absence reporting was prototyped, checked against head-guard shift scope, tested, and refined. The research evaluation uses a descriptive-quantitative approach, while RAD is the software-development method.

Timeline backup: the manuscript describes planning and gathering requirements early in the year, design and development through midyear, and refinement and documentation later. Avoid claiming all future timeline entries were completed on the presentation-preparation date.

Team backup: Cruz led coordination, documentation, and testing; Cahulugan handled full-stack development; Regacho supported quality assurance and literature work; Acop supported documentation and literature work.

Sources: Manuscript Ch. III, PDF pp. 47–50, 101–104, 107.

## 09. Conceptual framework
Suggested time: 45 seconds

Explain the IPO diagram from left to right. Inputs include both stable requirements, such as station posts, and changing records, such as leave and absences. Rules enforce eligibility and constraints. Outputs provide the schedule and the information needed to act on it.

Defense note: the algorithm generates the roster. Gemini is used in reviewing replacement candidates, and the administrator makes the final assignment. Keep those responsibilities distinct.

Sources: Manuscript Ch. III, PDF pp. 50–51; scheduler.py, replacements.py, ai_service.py.

## 10. Architecture and requirements
Suggested time: 45 seconds

Flutter provides the role-specific user interfaces. FastAPI handles the rules and communicates with Supabase PostgreSQL. The optional Gemini service receives a screened candidate context through the backend. All clients work from shared records.

Hardware backup: the paper lists Android 7.0 with 2 GB RAM as a minimum and Android 10+ with 4 GB RAM as recommended. Avoid presenting these listed requirements as new device-compatibility test results.

Defense note: if Gemini is unavailable, the backend still produces the rule-based candidate ranking. Internet access is still needed for the deployed backend; offline schedules are a recommendation.

Sources: Manuscript Ch. III, PDF pp. 51–58; README.md; backend_python/requirements.txt; scheduling_system/pubspec.yaml.

## 11. System analysis and design
Suggested time: 45 seconds

The diagrams in the manuscript describe the boundary of the system, the responsibilities of each actor, the flow of records, and how the records relate. A station-period schedule expands into individual duty assignments. Absence handling updates those assignments and records the applied replacement.

Database defense: the manuscript states that the schedule-to-duty-assignment relationship is enforced by the database; many other relationships are logical joins resolved by the application. Do not claim every relationship is protected by a foreign key. Credentials are stored separately from employee profile records.

Sources: Manuscript Ch. III, PDF pp. 58–81; backend_python/schema/001_initial.sql, 002_auth_accounts.sql, 003_ai_suggestions.sql.

## 12. Evaluation procedure
Suggested time: 55 seconds

Five IT experts and 211 end users evaluated the system. End users include administrators, head guards, and security personnel. The paper describes a Google Forms rating instrument and a five-point Likert scale. Six selected ISO/IEC 25010 criteria were used; the manuscript’s phrase “eight” is inconsistent with its six-item list and results.

Calculation defense: individual item scores summarize response frequencies; criterion ratings average their items; overall ratings average six criteria. Four end-user criteria weight the role-specific ratings equally. The paper reports a respondent-count-weighted sensitivity result of 4.67, still Highly Acceptable. Do not invent a sampling formula or per-role sample split absent from the provided text.

Sources: Manuscript Ch. III, PDF pp. 105–110; Ch. IV, PDF pp. 126–138.

## 13. Ethical considerations
Suggested time: 40 seconds

Explain both research ethics and system safeguards. Participation was voluntary, results were aggregated, and agency records were used for the study’s operational purpose. Passwords are hashed, and different roles have different views.

AI privacy defense: employee identifiers and job attributes can still be linkable; describe the payload as minimized rather than fully anonymous. Names and contact details are excluded from the stated AI context. AI suggestions and the administrator’s actual decision are kept separately for review. The presentation does not make a new legal-compliance determination.

Sources: Manuscript Ch. III, PDF pp. 110–113; backend_python/replacements.py, ai_service.py, ai_review.py, passwords.py.

## 14. Implemented system overview
Suggested time: 35 seconds

Use the dashboard screenshot to orient the panel. Point to the operational summary and the sidebar modules, then move quickly to scheduling and absence handling. This is a real screenshot embedded in the supplied paper.

Defense note: dashboard counts are a captured snapshot, not study-wide evaluation metrics. This image shows 574 employees; the manuscript separately reports 573 records during deployment testing. Do not treat these as the same measurement. If demonstrating the live application, explain that current data can differ from the documentation screenshot.

Sources: Manuscript Appendix D, PDF p. 167; local Flutter administrator screens.

## 15. Automated scheduling results
Suggested time: 55 seconds

These are reported manuscript benchmarks, not new measurements. The paper reports a median of 1.7 milliseconds to compute one 15-day station schedule and 0.04 seconds for 25 stations producing 7,700 assignments. Explain that these numbers describe the generation computation; they do not measure the entire UI, database write, publishing, network, or AI request.

Operational defense: the system produces the best roster permitted by available staffing and reports gaps. It cannot create guards when the agency is understaffed. Do not promise complete coverage in every possible staffing situation.

Sources: Manuscript Ch. IV, PDF p. 116; Ch. V, PDF pp. 139–140; scheduler.py, schedule_notes.py.

## 16. AI-assisted absence handling
Suggested time: 70 seconds

The candidate list exists before Gemini is consulted. The backend first removes conflicts and ineligible roles, then scores the remaining candidates. Gemini can consider recent cover burden, consecutive duties, and fairness when comparing those candidates. Its output must refer to an identifier from the supplied shortlist. The administrator confirms the final assignment.

Defense note: this is a rule-based scheduling and ranking system with generative-AI decision support. It does not train a new model, predict future absences, or let a model autonomously schedule personnel. Cached reviews are reused only while their candidate context remains valid. The paper reports fallback testing for missing configuration, disabled AI, quota failures, timeouts, and malformed responses.

Sources: Manuscript PDF pp. 73–74, 118, 140; replacements.py, ai_service.py, ai_review.py.

## 17. Replacement workflow and delay
Suggested time: 60 seconds

Explain the change in steps rather than inventing a percentage improvement. The system surfaces a screened list and prioritizes personnel who have already offered cover. This reduces the need for an administrator to construct the list and relay each detail manually.

Preparation example: for a 05:00–17:00 post assigned at 09:00, the configured policy sets the replacement’s duty to 10:00–19:00. That allows an hour for preparation and extends the original end by two hours. If assigned early enough, original hours remain. Applying a replacement after the original post has ended is refused.

Limitation: an assignment does not establish that the guard has arrived. Travel feasibility and actual reductions in overtime require field observation.

Sources: Manuscript Ch. V, PDF pp. 140–141, 145–147; backend_python/prep_window.py and replacements.py.

## 18. Mobile access and duty information
Suggested time: 45 seconds

Use the first screenshot to show that the guard has personal duty information on the phone. Use the second to show that head guards report station attendance within their assigned shift scope. The day head guard reports morning and afternoon; the night head guard reports night. Duplicate shift submissions are prevented.

The deployed app requires connectivity and uses in-app notifications. Avoid promising SMS, operating-system push delivery, or offline access. Duty status is calculated against the server’s Manila time. The reported usability and accessibility findings should be read alongside the evaluation ratings on the next slides.

Sources: Manuscript Ch. IV, PDF pp. 120–125; Appendix D, PDF pp. 194 and 204; Flutter mobile screens.

## 19. Development and testing
Suggested time: 50 seconds

State exactly what each number measures. The manuscript reports 284 automated checks across twelve backend harnesses. The 58 figure describes read endpoint coverage and responses; do not call it a complete write-path validation or a claim that all response snapshots were byte-identical. The live deployment test returned HTTP 200 for the requested endpoints.

The open issue is a reported 2.6-pixel notification-tab overflow at window widths of 1280 pixels and below. The paper recommends a staging database for write-path tests. These figures were taken from the manuscript; no new application test suite or deployed-data mutation was performed when building this deck.

Sources: Manuscript Ch. IV, PDF pp. 114–125; Ch. V, PDF pp. 142, 146.

## 20. Evaluation results
Suggested time: 70 seconds

The IT experts reported an overall rating of 4.79 and end users 4.74, both in the 4.21–5.00 Highly Acceptable range. The highest expert rating is usability, 4.93. The highest end-user rating is functional suitability, 4.92. Performance efficiency is the lowest-rated criterion for both: 4.53 and 4.59.

Interpretation: the respondents found the system acceptable, while responsiveness remains a priority for improvement. Ratings measure respondent assessment; they are not a causal experiment proving reductions in overtime or improved deployment outcomes.

Weighting defense: the manuscript’s role-balanced end-user overall is 4.74. Its respondent-count-weighted sensitivity value is 4.67, also Highly Acceptable. Keep the two respondent panels separate rather than claiming a single pooled average.

Sources: Manuscript Ch. IV, PDF pp. 126–138, especially Tables 26 and 33.

## 21. Summary of findings
Suggested time: 40 seconds

Return to the four objectives and match each to the available evidence. Scheduling has rule checks and computation benchmarks. Absence handling has candidate validation and fallback tests. Workflow efficiency is supported by a reduction in manual steps, with operational timing still an open measurement. User access and acceptance are supported by implemented mobile features and respondent ratings.

This distinction lets the group defend what was actually demonstrated without overstating long-term business outcomes.

Sources: Manuscript Ch. V, PDF pp. 139–142; Ch. IV, PDF pp. 126–138.

## 22. Conclusions
Suggested time: 40 seconds

State the contribution in practical terms: the administrator reviews a generated roster and a prepared replacement shortlist instead of building both manually. The integration keeps duty records and personnel views connected. The respondent ratings support acceptability in the studied setting.

Boundary: the study does not establish that AI always outperforms the rule-based ranking. It also does not guarantee full coverage under understaffing or prove long-term reductions in overtime. Those are suitable topics for future field evaluation.

Sources: Manuscript Ch. V, PDF pp. 143–145; recommendations, PDF pp. 146–147.

## 23. Recommendations
Suggested time: 45 seconds

Give the agency practical first steps: train users, keep station records accurate, and review generation notes before publishing. For development, resolve the reported narrow-screen layout issue, improve hosting responsiveness, and test writes in a separate staging database. SMS/email, iOS, and offline caching are future extensions rather than existing features.

For research, collect a manual baseline and post-adoption timing for replacement assignment, arrival, and overtime. Compare administrator choices with AI recommendations and with the rule-based list. Examine fairness and user satisfaction over sustained operation.

Sources: Manuscript Ch. V, PDF pp. 146–147.

## 24. Questions and discussion
Suggested time: 15 seconds

DEFENSE QUICK REFERENCE

1. What is the main contribution? An integrated workflow linking station-based scheduling, absence reporting, eligible-candidate ranking, administrator approval, and notification.

2. Where is the AI? Gemini reviews an already-screened shortlist and explains a replacement recommendation. Rules generate the roster and enforce eligibility.

3. Why use AI if rules already rank candidates? It can add contextual reasoning about recent cover burden and consecutive duties. Its incremental value should be evaluated against administrator choices; superiority was not established by the reported ratings.

4. What if AI fails? The rule-based shortlist remains usable. Invalid candidate identifiers are rejected.

5. What if there are too few guards? Generate the available roster and expose staffing gaps for review; no software can create missing personnel.

6. Did the system reduce overtime? It streamlines coordination and sets adjusted reporting hours. Actual overtime reduction needs a field baseline and post-adoption measurement.

7. How were results evaluated? Five IT experts and 211 end users rated six criteria. Overall scores were 4.79 and 4.74; both are Highly Acceptable.

8. What does 1.7 ms measure? Reported schedule-generation computation for one station period, not the full end-to-end application response.

9. Is the AI data anonymous? Names and contact details are excluded, but identifiers and job records can still be linkable. Use the term minimized rather than fully anonymous.

10. Can it run offline? The deployed backend requires internet. Offline schedule caching is recommended future work.

11. What remains unresolved? The paper reports a small notification-tab layout issue and recommends staging tests, responsiveness improvements, and longitudinal field evaluation.

12. Why are some project documents incomplete? The supplied final PDF includes evaluation results absent from older local drafts. This presentation takes its academic results from the PDF.

Sources: Supplied manuscript and selected local implementation modules; source locations are provided in each slide’s notes.
