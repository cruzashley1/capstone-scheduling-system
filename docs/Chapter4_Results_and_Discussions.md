# CHAPTER IV
# RESULTS AND DISCUSSION

> **Note on the chapter title.** The outline supplied carries the heading *"The Problem and Its Background."* That is the title of Chapter I. Chapter IV is titled **Results and Discussion**. The corrected title is used here.

This chapter presents the results and detailed discussions of the development, testing, and evaluation of *A Scheduling and Duty Management System with AI Application in Absence Handling* for Kaizen Security Agency Corp. Section 4.1 describes the developed system as a whole. Section 4.2 presents the results organized according to the four specific objectives stated in Chapter I, with the corresponding system screenshots and a discussion of the findings for each. Section 4.3 reports the unit and integration testing conducted on the web and mobile applications. Section 4.4 presents the evaluation results obtained from the IT experts and the end users.

---

## 4.1 Project Overview

*A Scheduling and Duty Management System with AI Application in Absence Handling* is a web, desktop, and mobile system developed for Kaizen Security Agency Corp., a security agency that deploys security personnel across twenty-five (25) Light Rail Transit (LRT) stations. Before the system, duty schedules were prepared manually in spreadsheet applications, distributed as files, and repaired by telephone whenever a guard failed to report. The system replaces that process with a single source of duty information that administrators maintain, that security personnel and head guards read on their own phones, and that repairs itself with the assistance of artificial intelligence when an absence is reported.

The system is built in three parts. A **Python (FastAPI) web service** holds the scheduling logic and exposes **71 HTTP endpoints** (28 GET, 32 POST, 5 PUT, and 6 DELETE) covering authentication, employee and station records, schedule generation and publishing, attendance reports, absence and special requests, cover offers, leave, replacements, notifications, and the AI review. It is deployed on a cloud platform (Render). A **Supabase (PostgreSQL)** database provisioned in the `ap-northeast-2` region holds the records, reached through the session connection pooler; its schema was applied in four ordered migration scripts. A **Flutter** client application of approximately **90 Dart source files and 55,000 lines** is compiled for Windows desktop and the web for administrators, and for Android for security personnel and head guards, over a shared service layer that speaks to the web service.

The system serves three roles, each with its own interface and its own authority:

| Role | Platform | What the role does in the system |
|---|---|---|
| **Administrator** | Windows desktop and web browser | Registers stations and configures the required number of personnel and the named post per slot for each shift; maintains personnel records; generates, edits, publishes, and archives bi-weekly schedules; reviews AI-ranked replacement candidates and confirms the assignment; acts on absence, leave, day-off, and special requests; exports reports |
| **Head Guard** | Android mobile application | Views the assigned bi-weekly and past schedules; views the daily roster of the assigned station; submits the attendance report per shift identifying who is present and absent |
| **Security Personnel** | Android mobile application | Views the assigned bi-weekly and past schedules and duty details; files emergency absence, leave, and day-off requests; declares availability to cover duties on rest days; receives duty and schedule notifications |

Credentials are held in a separate `auth_accounts` table and hashed with bcrypt. Passwords are never stored or displayed in readable form: an administrator may reset a password but cannot read one, and the password field shown on an employee record is a mask.

Artificial intelligence is applied at exactly one point in the system — the ranking of replacement candidates when an absence is reported. The system's own scheduling rules first remove every candidate who is unavailable, already on duty that date, also absent, or not eligible for the shift or post, and score the survivors on station familiarity, personnel type, workload, and declared availability. Only that screened shortlist is sent to the language model (Google Gemini, pinned to `gemini-2.5-flash` with lighter fallback models, a 10-second response budget, and a stored per-absence cache). The payload carries job attributes and identifiers only, never personal data. Every failure path — no API key, feature switched off, exhausted quota, network timeout, or a malformed answer — falls back to the rule-based ranking, so the administrator always receives the same qualified candidates whether or not the AI answered. The AI is advisory throughout; the administrator makes the final assignment.

At the time of this writing the deployed system holds **573 personnel records across 25 LRT stations**, with generated and published bi-weekly schedules for the current period.

**Table 13. Development Status of System Modules**

| # | Module / Feature | Delivered Component | Status |
|---|---|---|---|
| 1 | User authentication and role-based access | Login, logout, bcrypt-hashed credentials in `auth_accounts`, administrator-initiated password reset, three roles | Completed |
| 2 | Station and post configuration | Per-shift required headcount, named post per slot, per-post duty windows, Edit Station with synchronised rename | Completed |
| 3 | Automated schedule generation | 15-day bi-weekly generation from station requirements, rest days, reliever cover, three-group placement with adjacency rule | Completed |
| 4 | Rotation cycle | Monthly redistribution across stations honouring preferred stations while retaining familiar personnel per station | Completed |
| 5 | Schedule management | Create, edit, delete, publish, publish-all, historical periods | Completed |
| 6 | Schedule viewing interface | By station, period, and shift, with colour-coded duty status | Completed |
| 7 | Search and filter | Personnel by name; schedules and records by station, date, shift, and period | Completed |
| 8 | Reporting and archiving | Per-station and per-period duty reports, yearly leave report, PDF export on agency letterhead with configurable signatories | Completed |
| 9 | Mobile application for security personnel | Assigned and past schedules, shift details, emergency absence filing, leave filing, day-off requests, cover availability | Completed |
| 10 | Head guard attendance reporting | Station roster view, per-shift attendance report, day/night scope rule, single submission per shift | Completed |
| 11 | Administrator dashboard | Personnel totals, schedule summaries, daily absence, on-duty, and availability statistics | Completed |
| 12 | Absence handling with AI ranking | Rule-based screening and scoring, AI re-ranking with explanation, administrator confirmation, preparation window, expired-post refusal | Completed |
| 13 | Leave management | Per-type day caps, filing lead time, yearly limit, cooldown between leaves, exclusion from generation | Completed |
| 14 | In-app notifications | Schedule publication, request decisions, cover assignments, new reports and requests | Completed |
| 15 | Post-generation notes | Staffing gaps and configuration problems recorded as reviewable notes instead of aborting generation | Completed |

*[insert here — the figure of the system architecture, if the panel requires one: Flutter clients → FastAPI web service on Render → Supabase PostgreSQL, with the Gemini API attached to the absence-handling path only.]*

---

## 4.2 Presentation of Results

This section presents the results of the study according to the four specific objectives stated in Chapter I. Each objective is restated, the delivered feature that answers it is described, the corresponding system screenshots are presented, and the findings are discussed.

---

### Specific Objective 1

> **Design a scheduling system that organizes and balances the workload of security personnel through an automated schedule generation feature that follows each station's required number of personnel and assigned posts per shift, observes rest days, and distributes personnel across stations every rotation cycle.**

#### Description of Specific Objective 1

The first objective addresses the administrative burden identified in Chapter I: the manual preparation of bi-weekly duty schedules in spreadsheets for twenty-five stations, each with different staffing requirements per shift. The objective was met by an automated schedule generation feature whose input is the station configuration itself, so that the schedule the system produces is a direct consequence of what the agency has declared each station needs.

Four mechanisms deliver this objective:

**Station and post configuration as the driver of generation.** An administrator registers a station and defines, for each of the three shifts (morning, afternoon, and night), the required number of personnel and the named post assigned to each slot, together with the duty hours of each post. Generation is demand-driven: the system deploys to a station exactly what that station's configuration asks for, rather than distributing personnel evenly. The head guard is counted inside the morning and night shifts; the afternoon shift carries no head guard post.

**Bi-weekly (15-day) generation with rest days.** The system generates schedules covering the 1st to the 15th and the 16th to the last day of the month. Regular personnel are assigned to their fixed station and shift with scheduled rest days, and relievers are assigned to cover those rest days. Relievers are never assigned to a night shift, and each reliever's total duty days are held within a bounded range so that the cover work is shared rather than concentrated.

**Rotation across stations every cycle.** Every rotation cycle, personnel are redistributed across stations. The redistribution honours each guard's preferred station where it can — regular personnel and head guards are placed at a preferred station in 85–90% of cases and relievers in 60–75% — while deliberately retaining a number of familiar personnel at each station so that no station receives an entirely unfamiliar complement. Personnel may only be deployed to stations within their own group or an immediately adjacent group, following the three-group division of the LRT line.

**Gaps flagged, never hidden.** When the available personnel cannot fill a requirement, generation does not fail. It produces the best roster the configuration allows and records the shortfall as a note for the administrator to review. This design decision is discussed further below.

#### System Screenshots

**Figure 1.** *Station and Post Configuration*
*[insert here the screenshot of the Station Detail screen showing one station's per-shift configuration: the required number of personnel for morning, afternoon, and night, the named post assigned to each slot, and the duty hours of each post.]*

Figure 1 presents the Station and Post Configuration screen, which provides the administrator with the means to declare what each station requires before any schedule is generated. For each of the three shifts, the administrator sets the required number of personnel and names the post assigned to every slot, together with the duty hours attached to that post. This configuration is the input from which generation works: the system deploys to a station exactly what that station has been declared to need, rather than distributing personnel evenly across all stations. The head guard post is counted within the morning and night shifts, while the afternoon shift carries none.

**Figure 2.** *Station Management Interface*
*[insert here the screenshot of the Station Management screen listing all 25 LRT stations with their configured requirements.]*

Figure 2 presents the Station Management interface, which provides a consolidated view of all twenty-five LRT stations under the agency together with their configured staffing requirements. It serves as the administrator's entry point for registering a new station, opening an existing one for editing, and confirming at a glance that every station carries a complete configuration before a scheduling period is generated. Because generation is driven by this configuration, a station left unconfigured here produces staffing notes rather than a filled roster.

**Figure 3.** *Generate Schedule Interface*
*[insert here the screenshot of the Generate Schedule screen, showing the period selection and the station or group selection before generation is run.]*

Figure 3 presents the Generate Schedule interface, which provides the administrator with the controls that begin automated generation. The administrator selects the scheduling period — the 1st to the 15th, or the 16th to the last day of the month — and the station or station group to be generated. No further input is required, because every constraint the generator honours has already been declared in the station configuration, in the personnel records, and in the approved leave and day-off requests on file.

**Figure 4.** *Generated Bi-weekly Schedule*
*[insert here the screenshot of the Schedule Detail screen showing a generated 15-day schedule for one station, with each personnel's date, duty hours, assigned post, and the colour-coded duty status indicators for rest days, absences, and covered duties.]*

Figure 4 presents the generated bi-weekly schedule, which displays the completed 15-day roster for a single station. Each row shows a member of personnel with the dates of duty, the duty hours, and the assigned post, while the colour-coded indicators distinguish ordinary duty from rest days, absences, and covered duties. This is the working view in which the administrator reviews a generated period before publishing it, and the view from which the schedule is exported for the agency's records.

**Figure 5.** *Post-Generation Notes*
*[insert here the screenshot of the notes panel produced after generation, showing a recorded staffing shortfall or configuration problem presented for the administrator's review.]*

Figure 5 presents the post-generation notes panel, which provides the administrator with an account of every problem the generator encountered but did not stop for. When the available personnel cannot fill a requirement, generation produces the best roster the configuration allows and records the shortfall here rather than failing. The panel also reports configuration problems, such as personnel stranded by a station that no longer matches their record. Its purpose is to ensure that every gap in a roster is either filled or flagged, so that an administrator never discovers an empty post on the day of duty.

**Figure 6.** *Rotation Cycle Result*
*[insert here the screenshot showing the same personnel assigned to different stations across two consecutive rotation cycles — either two schedule periods side by side, or the employee schedule dialog showing the change of station between cycles.]*

Figure 6 presents the rotation cycle result, which demonstrates the redistribution of personnel across stations between one cycle and the next. The same personnel appear at different stations in consecutive periods, showing that deployment is not static. Rotation honours each guard's preferred station where it can, while deliberately retaining a number of familiar personnel at each station, and confines every movement to the guard's own station group or an immediately adjacent one.

**Figure 7.** *Published Schedule as Received by Security Personnel*
*[insert here the screenshot of the mobile application's schedule screen showing an individual guard's assigned bi-weekly schedule with dates, duty hours, station, and post.]*

Figure 7 presents the published schedule as received by security personnel, which shows the same generated roster from the perspective of the guard it concerns. Once the administrator publishes a period, each member of personnel sees their own assigned duties — dates, duty hours, station, and post — on their own device. The figure is presented alongside the administrator's view to demonstrate that both are drawn from the same record, and that publication is the single act that makes a schedule visible to the personnel it assigns.

#### Findings and Discussion

The automated generation feature produced complete bi-weekly schedules from the configured station requirements for all twenty-five stations. Verification against the scheduling rules — reported in full in Section 4.3 — confirmed that for every station tested, daily coverage matched the station's required headcount per shift and post, no guard was booked twice on the same day, rest days were observed, head guard hours totalled the expected 156 hours per primary head guard over the 15-day period, relievers stayed within their bounded duty range, and no reliever was ever assigned to a night shift. Rotation was confirmed to move personnel between cycles while keeping preferred-station placement within the intended shares and retaining familiar personnel at each station, and placement was confirmed to be reproducible: the same cycle regenerated produces the same result, which matters because an administrator who regenerates a period must not receive a different roster each time.

The measured cost of generation is negligible. A complete 15-day schedule for a station of nineteen posts is produced in a **median of 1.7 milliseconds**, the slowest of twenty-five runs taking **3.2 milliseconds**, and all twenty-five stations — **7,700 duty assignments in total** — in **0.04 seconds**. Set against the manual preparation of the same schedules in spreadsheets, this is the clearest quantitative result of the study for this objective: the arithmetic of the schedule ceased to be work at all.

One design decision deserves particular note, because it changes what the system promises. Generation does **not** fail when the available personnel cannot fill a requirement. It produces the best roster the configuration allows and records the shortfall as a note. The rule the system therefore enforces is not *"every post is filled"* — which no software can guarantee when the agency is short of guards — but *"every gap is either filled or flagged."* An unexplained hole in the roster is a defect; a reported one is information the administrator needs. In testing, a generated station period reported seven flagged shortfalls, every one of them surfaced in the notes rather than silently absorbed. This is the behaviour that makes the generated schedule trustworthy: the administrator is never in the position of discovering an empty post on the day of duty.

A further finding concerns data integrity rather than scheduling. Stations are joined by **name** in employee and rotation records but by **identity** in schedules. An administrator who renames a station by deleting and re-creating it therefore strands every guard assigned to it, and those guards drop out of generation entirely. The system resolves this by performing renames through the Edit Station function, which updates employee and rotation records in a single transaction, and by naming any remaining stranded personnel in the generation notes. This was found by testing rather than in production, and is recorded in the defect log in Section 4.3.

---

### Specific Objective 2

> **Create an AI-based absence handling feature that recommends suitable reliever personnel based on availability, current schedule or day-off status, shift and post eligibility, and workload distribution, by screening candidates through system-defined scheduling rules and ranking the qualified candidates with the assistance of artificial intelligence.**

#### Description of Specific Objective 2

The second objective addresses the problem identified in Chapter I as the most costly in practice: when a guard fails to report, an administrator must find a replacement by manually reviewing who is free and telephoning candidates in turn, often meeting refusals. The objective was met by an absence handling feature in which the system does the screening and the ranking, and the administrator does only the deciding.

The feature works in two stages, and the division between them is deliberate.

**Stage one — screening and scoring by system-defined rules.** When an absence is reported, the system removes from consideration every candidate who is unavailable, already scheduled on that date, also reported absent, or not eligible for the shift or the post. The survivors are scored on the four factors named in the objective: station familiarity, personnel type, workload, and declared availability. A guard who has declared a cover offer for that rest day is raised in the ranking. This stage is entirely rule-based and produces a ranked shortlist on its own.

**Stage two — re-ranking with the assistance of artificial intelligence.** Only the screened shortlist is sent to the language model, which reviews the qualified candidates and recommends the most suitable replacement together with the reason for the recommendation. The payload carries job attributes and identifiers only — no personal data. One absence costs exactly one model request regardless of how many times the administrator reopens the screen, because the review is cached against the absence and invalidated only if the shortlist itself changes.

**The administrator decides.** The ranked candidates and the AI's explanation are presented, and the administrator confirms the assignment. The system records the administrator's actual decision against the recommendation that was made, so that the two can be compared.

Two further rules govern the assignment itself. A replacement assigned at short notice automatically receives a **preparation window** — the duty hours are adjusted to give the guard reasonable travel and preparation time, and the notification states both the adjusted hours and the post's own hours. And a post whose duty has **already ended** can no longer receive a replacement; the system refuses, names the post, leaves the schedule untouched, and sends no notification.

#### System Screenshots

**Figure 8.** *Attendance Report Submitted by the Head Guard*
*[insert here the screenshot of the mobile application's attendance report screen, showing the head guard marking a guard absent for the shift.]*

Figure 8 presents the attendance report screen, which provides the head guard with the means to record, from the station itself, which personnel reported for the shift and which did not. The report is the system's sole means of establishing attendance, as the study does not include biometric or location-based time recording. Scope is fixed by role — the day head guard files the morning and afternoon shifts and the night head guard files the night shift — and each shift may be submitted only once.

**Figure 9.** *Absence Received in the Administrator Interface*
*[insert here the screenshot of the Absent Management screen showing the reported absence awaiting action, with the affected station, shift, and post.]*

Figure 9 presents the Absent Management screen, which provides the administrator with the reported absence as it arrives from the station, identifying the affected personnel together with the station, shift, and post left uncovered. It is the point at which the absence becomes actionable: the record carries everything needed to begin the search for a replacement, and it is from this record that the screened candidate list is opened.

**Figure 10.** *Rule-Screened and Ranked Replacement Candidates*
*[insert here the screenshot of the Find Replacement screen showing the qualified candidates in ranked order with the factors behind each ranking — station familiarity, personnel type, workload, and declared availability.]*

Figure 10 presents the Find Replacement screen, which displays the candidates who remain after the system's scheduling rules have been applied. Every guard who is unavailable, already on duty that date, also reported absent, or ineligible for the shift or post has already been removed, and those remaining are ordered by station familiarity, personnel type, workload, and declared availability. The administrator is therefore choosing among qualified candidates rather than compiling a list of them, which is the step the manual process required.

**Figure 11.** *AI Recommendation with Explanation*
*[insert here the screenshot of the AI review panel showing the recommended replacement and the reason given for the recommendation.]*

Figure 11 presents the AI review panel, which displays the language model's recommendation together with the reason given for it. The model receives only the shortlist the rules have already screened and re-ranks it; it does not select candidates of its own. The explanation is shown so that the administrator can weigh the recommendation rather than accept it blindly. When the model returns nothing — because the service is unreachable, the quota is exhausted, or the answer is malformed — this panel draws nothing and the rule-based ranking stands unchanged.

**Figure 12.** *Confirmation of the Assignment by the Administrator*
*[insert here the screenshot of the confirmation dialog or the confirmed assignment reflected in the schedule.]*

Figure 12 presents the confirmation of the assignment, which shows the administrator's decision being recorded and the schedule updated to reflect the replacement. This step is what distinguishes an advisory recommendation from an automated one: the artificial intelligence orders the list and supplies a reason, but no personnel are assigned until the administrator confirms. The system stores the decision alongside the recommendation that was made, so that the two can be compared.

**Figure 13.** *Cover Assignment Notification with the Preparation Window*
*[insert here the screenshot of the notification received in the mobile application by the assigned replacement, showing the station, the post, the adjusted duty hours, and the time to report.]*

Figure 13 presents the cover assignment notification, which shows what the assigned replacement receives on their own device. It names the station, the post, the adjusted duty hours, and the time to report. The adjustment is the preparation window: a guard assigned at short notice is given travel and preparation time rather than the post's own start time, and the notification states both so that the guard understands what was changed. This is the notification that replaces the telephone call of the manual process.

**Figure 14.** *Refusal of a Replacement for a Post That Has Already Ended*
*[insert here the screenshot showing the Find Replacement action closed, or the refusal message naming the post whose duty has timed out.]*

Figure 14 presents the refusal of a replacement for a post that has already ended, which demonstrates the boundary the system places on absence handling. Once the duty hours of a post have passed, the replacement action closes and the web service refuses any late attempt, naming the post concerned. Nothing is written to the schedule and no notification is sent. The rule exists because assigning a replacement to a shift that has already finished records an action without relieving anyone.

**Figure 15.** *Cover Availability Declared by Security Personnel*
*[insert here the screenshot of the mobile application's cover availability screen, where a guard declares willingness to be assigned duty on a rest day.]*

Figure 15 presents the cover availability screen, which provides security personnel with the means to declare, in advance, a willingness to be assigned duty on a rest day. A declared cover offer raises the guard's position among replacement candidates, so that when an absence occurs the administrator is choosing first among personnel who have already indicated willingness. This is the mechanism that converts the manual process's sequence of telephone calls and refusals into a single confirmation.

#### Findings and Discussion

The absence handling feature performed the screening, scoring, ranking, and notification that previously required an administrator to work the telephone. Testing confirmed that the rule stage correctly excludes every ineligible candidate before the AI is consulted, that the payload sent to the model contains only job attributes and identifiers, and that each candidate carries exactly the ranking fields and nothing more.

The most consequential finding concerns what happens when the AI does not answer. The rule-based ranking survives **every** AI failure path tested: no API key configured, the feature switched off, quota exhausted, network timeout, and a malformed response from the model. In each case the administrator receives the same qualified, ranked candidates that the rules produced. This is not a fallback added late; it is the reason the two stages were separated in the first place. The AI re-ranks a list it did not build, so the system's usefulness does not depend on a third-party service being reachable — a property that matters for an agency whose stations must be covered whether or not an external API is available that afternoon. The AI is, as Chapter I delimited it, advisory: it changes the order of a list and supplies a reason, and the administrator makes the assignment.

Testing also confirmed the cost discipline: one model request per absence, cached, with a changed shortlist invalidating the cached review. This bounds the operating cost of the feature to the number of absences rather than the number of times an administrator looks at the screen.

The two governing rules on the assignment itself were both added in response to defects found during testing, and both concern the passage of time rather than the choice of candidate. The first was that a notification filed on one date still offered *Find Replacement* two days later, which would have allowed an administrator to assign a replacement to a shift that had already finished. The action now closes when the post times out, and the web service independently refuses a late application, naming the post. The second was the preparation window: a guard assigned at short notice was being given the post's own start time, which is not reachable from home. The duty hours are now adjusted, and the notification states both the adjusted hours and the post's own hours, so the guard knows what was changed and why. The complete set of thirty checks over the preparation window and twenty-five over the expired-post refusal all pass.

---

### Specific Objective 3

> **Test the system to reduce delays in assigning replacement personnel and minimize extended working hours of on-duty security guards.**

#### Description of Specific Objective 3

The third objective is the operational consequence of the second. Chapter I identified that when a guard is absent, administrators spend significant time manually identifying and contacting replacements, and that in the worst case the on-duty guard is required to extend the shift until a replacement arrives — producing fatigue and reduced performance. This objective concerns whether the delivered system shortens the interval between an absence becoming known and a replacement being assigned and notified.

The system attacks that interval at four points:

1. **The absence becomes known immediately.** The head guard files the attendance report from the station on a phone, and it reaches the administrator's dashboard at once, rather than through a telephone call or an end-of-shift report.
2. **The candidate search is eliminated.** The screened and ranked shortlist is produced by the system on the absence record itself. The administrator does not compile a list of who is free; the list is already there.
3. **The assignment is a confirmation, not a negotiation.** Guards who have declared availability to cover a rest day are already ranked higher, so the administrator is choosing among personnel who have indicated willingness rather than telephoning candidates who may refuse.
4. **The replacement is notified in the application.** The notification names the station, the post, the adjusted duty hours, and the time to report, so the assigned guard needs no further call to know where to go and when.

The preparation window is what connects this objective to the second half of its wording. Minimising the extended working hours of the on-duty guard requires the replacement to actually arrive, which requires the replacement to have been given a reachable reporting time. Assigning a guard to a start time already past does not relieve the guard on post; it only records that someone was assigned.

#### System Screenshots

**Figure 16.** *Absence Reported from the Station and Received on the Dashboard*
*[insert here the screenshot pairing the head guard's submitted attendance report with the administrator dashboard showing the absence and the daily absence count updated.]*

Figure 16 pairs the head guard's submitted attendance report with the administrator's dashboard receiving it, and demonstrates the first interval the system removes. Under the manual process the absence reached the administrator by telephone or at the end of the shift; here it is filed from the station and appears on the dashboard at once, with the daily absence count updated. The absence becomes actionable at the moment it is observed, rather than at the moment someone finds time to report it.

**Figure 17.** *Ranked Shortlist Available Immediately on the Absence Record*
*[insert here the screenshot of the Find Replacement screen opened directly from the reported absence, showing that no manual search step is required.]*

Figure 17 presents the ranked shortlist opened directly from the reported absence, and demonstrates the second interval the system removes. No search is performed by the administrator: the screening and the ordering have already been carried out on the absence record, so the list exists before it is asked for. The step that consumed the most administrator time under the manual process — establishing who was free and eligible — is absent from the workflow entirely.

**Figure 18.** *Replacement Notified with Reporting Time*
*[insert here the screenshot of the cover assignment notification received by the replacement, with the timestamp visible, showing the adjusted duty hours and the time to report.]*

Figure 18 presents the replacement notification with its timestamp visible, and demonstrates the final interval, between the administrator's confirmation and the replacement knowing where and when to report. The notification carries the station, the post, the adjusted duty hours, and the reporting time, so that nothing needs to be relayed by voice. The adjusted hours are what allow the guard on post to be relieved: a reachable reporting time is the difference between a replacement who is assigned and a replacement who arrives.

**Figure 19.** *Administrator Dashboard — Daily Absence, On-Duty, and Availability Statistics*
*[insert here the screenshot of the dashboard panels showing total personnel, schedule summaries, and the daily absence, on-duty, and availability counts.]*

Figure 19 presents the administrator dashboard, which provides the daily operational picture from which absences are noticed and acted upon: the total personnel on record, summaries of the current scheduling periods, and the counts of personnel absent, on duty, and available for the day. It is the screen on which a reported absence first becomes visible, and the counts give the administrator an immediate sense of the cover available before any individual absence is opened.

**Figure 20.** *Measured System Response Times*
*[insert here the figure or chart presenting the measured performance values from Table 18, if the panel prefers a graphical presentation.]*

Figure 20 presents the measured response times reported in Table 18 in graphical form. It distinguishes the cost of the scheduling logic itself — a complete bi-weekly schedule for a station produced in under four milliseconds — from the response time the user experiences, which is governed by network transfer and by the hosting tier. The distinction matters to this objective because it locates the remaining delay outside the system's scheduling decisions.

#### Findings and Discussion

The technical portion of this objective was measured directly. **Table 18** reports the results.

**Table 18. Measured Performance**

| Measurement | Result |
|---|---|
| Generation of one 15-day station period (median) | 1.7 ms |
| Generation of one 15-day station period (slowest of 25 runs) | 3.2 ms |
| Generation of 25 station periods, 7,700 duty assignments in total | 0.04 s |
| Deployed service — station list (11 KB) | 0.73 s |
| Deployed service — absence requests (6 KB) | 0.69 s |
| Deployed service — full personnel roster, 573 records (249 KB) | 1.18 s |
| Deployed service — all schedules with duty assignments (1.3 MB) | 3.23 s |
| Deployed service — first request after idle (cloud instance cold start) | 23.71 s |
| AI review — response budget per absence, with fallback ranking on timeout | 10 s |
| AI review — model requests spent per absence | 1 (cached) |

The steps that previously consumed an administrator's time are now bounded by these figures. Producing the ranked shortlist is not a search the administrator performs but a response the service returns, and the AI review is capped at a ten-second budget after which the rule-based ranking is presented regardless. The scheduling logic itself is not the constraint on responsiveness: response time as the user experiences it is dominated by network transfer and by the hosting plan, most visibly in the cold start of the idle cloud instance, which is a characteristic of the free hosting tier used for the study rather than of the system. The heaviest payload — the full set of schedules with all duty assignments — is the natural candidate for pagination should the agency deploy on a paid tier or add stations.

**Where the delay actually was.** The measurements above establish that the *system* contributes no delay of operational significance. But the delay this objective addresses was never in the arithmetic — it was in the steps a person had to perform between learning of an absence and having a replacement on the way. Chapter I documents those steps: administrators must manually find and contact an available replacement, often encountering delays when personnel decline for personal reasons, and in the worst case the on-duty guard extends the shift until someone arrives.

The reduction is therefore demonstrated structurally rather than by stopwatch: the steps that consumed the time have been removed from the administrator's hands, not merely made quicker. Table 19 compares the manual process as documented in Chapter I against the delivered system, step by step.

**Table 19. Replacement Handling: The Manual Process Compared with the Developed System**

| Step | Manual Process (as documented in Chapter I) | With the Developed System | What Changed |
|---|---|---|---|
| The absence becomes known | Reported by telephone, or discovered when the guard fails to appear, or at the end of the shift | The head guard files the attendance report from the station on a phone; it reaches the administrator's dashboard at once | The report travels with the guard rather than after the shift |
| Working out who is free | The administrator reviews the spreadsheet to establish who is not already on duty, not on a rest day, not already absent, and eligible for the shift and post | Every ineligible candidate is removed before the administrator opens the screen | The search step no longer exists as work |
| Deciding whom to ask first | Judgement recalled from memory — who is nearby, who is usually willing, whose workload is light | The qualified candidates are scored on station familiarity, personnel type, workload, and declared availability, then re-ranked by the AI with a stated reason | The ordering is explicit, repeatable, and explained rather than recalled |
| Securing the replacement | Candidates telephoned one at a time; each refusal sends the administrator back to the list to start again | Guards who have declared a cover offer for that rest day are already ranked highest, so the administrator confirms an assignment rather than negotiating one | The refusal loop is removed for guards who have volunteered in advance |
| Telling the replacement where and when to report | Verbal instructions given by telephone | The notification names the station, the post, the adjusted duty hours, and the time to report | Nothing has to be relayed by voice or remembered |
| Relieving the guard on post | The on-duty guard extends the shift until a replacement arrives | The preparation window gives the replacement a reachable reporting time, and a post whose duty has already ended cannot be assigned at all | The replacement is given a time they can actually meet, which is what ends the extension |

Read down the middle column, the administrator's remaining work in a replacement is to open the absence, look at a ranked list, and confirm. Reading down the left, the same work is a spreadsheet review followed by an unbounded sequence of telephone calls whose length depends on how many people decline. That difference — an unbounded sequence of calls replaced by a single confirmation — is the reduction this objective claims, and it does not depend on how fast any particular administrator worked the telephone.

The final row is the one that connects to the second half of the objective. The extended working hours of the on-duty guard end when the replacement arrives, not when the replacement is assigned. This is why the preparation window matters to this objective and not only to the previous one: a guard assigned to a start time already past does not relieve anyone. The thirty checks over the preparation window confirm that short-notice covers receive an adjusted, reachable reporting time and that the notification states both the adjusted hours and the post's own hours.

*[insert here — optional, and only if the agency can supply it: the average time previously taken to secure a replacement under the manual process, and the average length of shift extension incurred while waiting. Elapsed-time figures would strengthen the comparison above, but the argument does not depend on them.]*

*[insert here — any absence actually handled during the deployment period, with the interval observed between the head guard's report and the replacement's notification.]*

The respondents' own assessment of timeliness is reported separately in Section 4.4, where the Performance Efficiency criterion captures whether the users experienced the system as fast enough for the work.

---

### Specific Objective 4

> **Evaluate the developed web and mobile-based Scheduling and Duty Management System in terms of accessibility, timeliness, and usability of schedule information for administrators and security personnel.**

#### Description of Specific Objective 4

The fourth objective concerns the last of the problems stated in Chapter I: that Excel-based scheduling made duty information difficult to access, slow to reach the people it concerned, and inconvenient to read. The objective was met by delivering the same schedule to every role on the device that role actually carries, and it is evaluated formally through the ISO/IEC 25010 instrument reported in Section 4.4.

**Accessibility.** One web service serves three clients — the administrator application on Windows desktop and the web, and the mobile application on Android for head guards and security personnel — all reading the same records. A guard no longer requests a file or visits an office to learn where they are posted; the assigned bi-weekly schedule, the past schedules, and the details of each duty are on the phone. Access is governed by role, so each user sees the information belonging to their role and no more.

**Timeliness.** Schedule information reaches its readers when it changes rather than when a file is next distributed. Publishing a schedule notifies its recipients; a decision on a request notifies the guard who filed it; a cover assignment notifies the guard assigned. Duty status is computed against the server clock in Manila time, so what the application shows about a duty is true at the moment it is read.

**Usability.** Schedules are presented by station, period, and shift with colour-coded indicators for rest days, absences, and covered duties. Personnel can be searched by name, and schedules and records filtered by station, date, shift, and period. Duty reports per station and per period and the yearly leave report can be exported to PDF on the agency's letterhead with configurable signatories, for the documentation the agency must keep regardless of the system.

#### System Screenshots

**Figure 21.** *Administrator Dashboard*
*[insert here the screenshot of the administrator dashboard showing total personnel, schedule summaries, and the daily absence, on-duty, and availability statistics.]*

Figure 21 presents the administrator dashboard, which provides the single view from which the state of operations can be read: total personnel, schedule summaries, and the daily absence, on-duty, and availability statistics. In terms of this objective it demonstrates accessibility for the administrator — information that previously required opening and cross-reading several spreadsheet files is presented on one screen and drawn from one record.

**Figure 22.** *Schedule Viewing Interface with Colour-Coded Duty Status*
*[insert here the screenshot of the Schedule Detail screen showing a station's period with the colour-coded indicators for rest days, absences, and covered duties.]*

Figure 22 presents the schedule viewing interface, which displays a station's period with colour-coded indicators distinguishing ordinary duty from rest days, absences, and covered duties. The colour coding is what makes a fifteen-day roster readable at a glance rather than cell by cell, and addresses the convenience of viewing duty information identified as a problem in Chapter I.

**Figure 23.** *Search and Filter*
*[insert here the screenshot showing personnel searched by name, and schedules filtered by station, date, shift, and period.]*

Figure 23 presents the search and filter functions, which provide the administrator with direct access to a particular record without reading through the whole. Personnel may be searched by name, and schedules and records filtered by station, date, shift, and period. This addresses the accessibility of information in a system holding 573 personnel across 25 stations, where locating a single assignment by inspection would not be practical.

**Figure 24.** *Security Personnel Mobile Interface*
*[insert here the screenshot of the security personnel home screen and the Today's Duty card, showing the current duty status.]*

Figure 24 presents the security personnel mobile interface, showing the home screen and the Today's Duty card, which reports the guard's current duty status. The card is computed against the server clock in Manila time rather than the date alone, so that a guard whose duty has ended is not shown as on duty later the same evening. In terms of this objective it demonstrates both accessibility — the schedule is carried by the guard rather than requested from an office — and timeliness, in that what the card states is true at the moment it is read.

**Figure 25.** *Head Guard Station Overview*
*[insert here the screenshot of the head guard's station overview showing the daily roster of personnel on duty for the shift with their assigned posts.]*

Figure 25 presents the head guard's station overview, which provides the daily roster of the assigned station, listing the personnel on duty for the shift with their assigned posts. It gives the head guard the information needed to supervise the station and to complete the attendance report, drawn from the same published schedule the personnel themselves see.

**Figure 26.** *In-App Notifications*
*[insert here the screenshot of the notifications screen showing schedule publication, request decisions, and cover assignment notifications.]*

Figure 26 presents the notifications screen, which displays the in-app messages carrying schedule publications, decisions on filed requests, and cover assignments. As delimited in Chapter I, the system uses in-app notification rather than SMS or email. Its contribution to this objective is timeliness: information reaches its reader when it changes, rather than when a schedule file is next distributed.

**Figure 27.** *Exported PDF Report on Agency Letterhead*
*[insert here the screenshot of a generated duty schedule report or yearly leave report exported to PDF, showing the agency letterhead and the configured signatories.]*

Figure 27 presents the exported PDF report, showing a duty schedule or yearly leave report produced on the agency's letterhead with the configured signatories. It exists because the agency's documentation requirements do not disappear when scheduling is automated: the report gives the agency a printable record in the form it already uses, without returning to manual preparation.

**Figure 28.** *Login and Role-Based Access*
*[insert here the screenshot of the Sched login screen, and the three landing screens for administrator, head guard, and security personnel showing that each role receives its own interface.]*

Figure 28 presents the login screen together with the three landing screens, demonstrating role-based access. A single set of credentials resolves to one of three interfaces — administrator, head guard, or security personnel — and each user is presented with the information belonging to their role and no more. Credentials are held hashed and cannot be read back by an administrator, only reset.

#### Findings and Discussion

The delivered system makes duty information available to each role on the device that role uses, and keeps the three views consistent by serving them from one record rather than from distributed copies. The integration testing reported in Section 4.3 was designed specifically around this property: the golden-file contract holds the responses of all fifty-eight read endpoints under comparison, so that a change beneath the service cannot silently alter what a guard's phone displays. A schedule published by an administrator is the schedule the guard sees, and the contract test is the evidence for that rather than an assurance.

Two findings from testing bear directly on the *timeliness* of the information as the user reads it. The first is that duty status must be computed from the server wall clock and not from the date alone: a guard scheduled 0500H–1400H was, in an early build, still shown *On Duty* late in the evening, and could therefore file an emergency absence for a duty that had already ended. Duty status is now read from the server clock in Manila time, and thirty-eight automated checks hold that behaviour in place. The second is the corresponding rule on the administrator's side, where a stale notification still offered *Find Replacement* for a shift that had finished. Both defects were of the same kind — the system displaying something that had been true earlier in the day — and both are now closed.

The formal evaluation of accessibility, timeliness, and usability against the ISO/IEC 25010 criteria, by the IT experts and by the administrators, head guards, and security personnel of Kaizen Security Agency Corp., is presented in **Section 4.4**.

*[insert here — discussion of the respondents' assessment of accessibility, timeliness, and usability once the evaluation results in Section 4.4 have been gathered, relating the Usability and Performance Efficiency ratings back to this objective.]*

---

## 4.3 Development and Testing

Following the Rapid Application Development (RAD) model adopted in Chapter III, the system was produced in successive working builds rather than in a single pass. Each build added one operational capability — station and post configuration, schedule generation, publishing, absence reporting, replacement handling, leave management, and the AI review — and each was exercised against an executable set of rules before the next was started. Because each capability was tested as it was built, the majority of defects were found by the tests rather than by users, and each fix was locked in by a test that fails if the defect returns.

### Unit and Integration Testing

Testing was carried out at three levels. **Unit testing** exercised the scheduling rules and the interface widgets in isolation, with controlled rosters and a frozen clock. **Integration testing** exercised the boundary between the application, the web service, and the database. **System testing** exercised the deployed cloud service over the public internet. All results reported below were obtained from actual test runs; the run recorded here was executed on the current build.

The tests are organised into the two applications the system delivers. The **web application** comprises the FastAPI web service, which holds all the scheduling logic, together with the administrator interface compiled for Windows desktop and the web. The **mobile application** comprises the Android interface used by head guards and security personnel.

Across both applications, **[insert here — total]** automated checks were executed: **284** over the scheduling rules and the web service, and **[insert here]** over the application interface.

#### Table 20. Unit and Integration Test Results — Web Application

| Test Case ID | Component/Module | Test Condition | Expected Behavior | Actual Result | Status |
|---|---|---|---|---|---|
| **Web Application** | | | | | |
| TC001 | Authentication | Administrator logs in with valid credentials | Access is granted and the administrator interface is loaded | Access granted; the administrator interface loaded with role-based navigation | Passed |
| TC002 | Authentication | Login is attempted with an incorrect password | Access is refused and no session is created | Access refused; no session created | Passed |
| TC003 | Authentication | Password is stored and an administrator resets it | The password is stored hashed and is never displayed; the old password stops working and the new one is accepted | Credentials stored bcrypt-hashed in `auth_accounts`; the stored value is never returned to the interface; the reset password took effect | Passed |
| TC004 | Station Configuration | A station is registered with the required number of personnel and a named post for each slot, per shift | The configuration is saved and becomes the basis of generation for that station | Configuration saved; generation deployed exactly the configured number to each shift and post | Passed |
| TC005 | Station Configuration | A station is renamed through Edit Station | Employee and rotation records are updated in the same transaction and no personnel are stranded | Records updated together; any remaining stranded personnel were named in the generation notes; an empty schedule could not be published | Passed (9 checks) |
| TC006 | Station Configuration | Per-post duty windows are edited in Edit Station | The duty-window column, the post re-staggering, and the nine-hour rule are applied | Duty windows re-staggered correctly and the nine-hour rule enforced | Passed (9 cases) |
| TC007 | Schedule Generation | A 15-day period is generated from the station configuration | Daily coverage equals the station's required headcount for every shift and post | Coverage matched the requirement for every station tested; all shortfalls were flagged by the engine | Passed |
| TC008 | Schedule Generation | The generated period is checked for conflicts and rest days | No guard is booked twice on the same day and rest days are observed | No double booking on any day; rest days observed | Passed |
| TC009 | Schedule Generation | Reliever assignments are checked across the period | Relievers cover rest days, stay within their bounded duty range, and are never assigned a night shift | All relievers within the 10–13 day range; no reliever assigned to a night shift | Passed |
| TC010 | Schedule Generation | Head guard hours are totalled over the period | Each primary head guard totals the expected hours for a 15-day period | 156h of 156h per primary head guard; 48h substitute | Passed |
| TC011 | Schedule Generation | A period is generated when the available personnel cannot fill the requirement | Generation completes and records the shortfall as a reviewable note rather than aborting | Schedule produced; seven shortfalls recorded as notes, every one flagged | Passed |
| TC012 | Rotation Cycle | Two consecutive rotation cycles are generated | Personnel are redistributed across stations, preferred-station shares stay within target, and familiar personnel are retained per station | Personnel moved between cycles; preferred-station shares within target; familiar personnel retained | Passed (47 checks) |
| TC013 | Rotation Cycle | The same cycle is generated a second time | The placement is reproducible for a given cycle | Identical placement produced on re-run | Passed |
| TC014 | Placement | Personnel are placed from the station setup | Placement is demand-driven and per-station roster caps by size band are respected | Placement followed the configured demand; roster caps respected | Passed (34 checks) |
| TC015 | Placement | Personnel without a preferred station are placed | Those without a preference are the ones held back when demand is exceeded | Personnel with no preferred station were the ones benched | Passed |
| TC016 | Special Assignment | A guard is pinned to a station already at its required number | The pinned assignment is honoured and the surplus is reported in the notes | Pinned assignment honoured; surplus named in the notes | Passed (15 checks) |
| TC017 | Special Assignment | A pinned assignment clashes with an existing schedule | Nothing is saved, the conflict is reported, and regeneration resolves it to exactly one station | Nothing saved; HTTP 409 returned naming the covered period; regeneration resolved to one station | Passed (14 checks) |
| TC018 | Schedule Management | An empty generated schedule is published | Publishing is refused and Publish All skips it, naming the schedule skipped | Publishing refused; Publish All skipped it and reported which | Passed |
| TC019 | Schedule Management | A populated schedule is published | The schedule becomes visible to its recipients and each is notified | Schedule published; notifications delivered to all recipients | Passed |
| TC020 | Absence Handling | An absence is reported and candidates are screened | Candidates who are unavailable, already on duty, also absent, or ineligible for the shift or post are removed, and the survivors are scored | Ineligible candidates removed; survivors scored on station familiarity, personnel type, workload, and declared availability | Passed |
| TC021 | Absence Handling (AI) | The screened shortlist is sent to the language model | Only job attributes and identifiers are sent; each candidate carries exactly the ranking fields; the payload is serialisable | No personal data present in the payload; ranking fields exact; payload JSON-serialisable as sent | Passed (18 checks) |
| TC022 | Absence Handling (AI) | The AI is unavailable — no key, feature off, quota exhausted, timeout, or malformed answer | The rule-based ranking is returned unchanged in every case | The rule-based ranking survived every failure path; the administrator received the same qualified candidates | Passed (18 checks) |
| TC023 | Absence Handling (AI) | The replacement screen is reopened several times for the same absence | Exactly one model request is spent per absence, and a changed shortlist invalidates the cached review | One model call per absence; cache invalidated when the shortlist changed; the administrator's decision recorded against the recommendation | Passed |
| TC024 | Absence Handling | A replacement is assigned at short notice | Duty hours are adjusted for travel and preparation, and the notification states both the adjusted and the post's own hours | Preparation window applied; notification stated both sets of hours; a duty needing no adjustment carried none | Passed (30 checks) |
| TC025 | Absence Handling | A replacement is assigned to a post whose duty has already ended | The assignment is refused naming the post, the schedule is untouched, and no notification is sent | Refused with the post named; schedule unchanged; no notification sent; a post not yet timed out was still covered normally | Passed (25 checks) |
| TC026 | Absence Handling | Find Replacement is left open until the post times out | The action closes once the post it would cover has timed out | The action closed at timeout | Passed (24 cases) |
| TC027 | Leave Management | Leave requests are filed against each rule | The per-type day cap, the filing lead time, the yearly limit, and the cooldown from the end of the previous leave are each enforced | All four rules enforced; refusals named the blocking rule | Passed (54 checks) |
| TC028 | Leave Management | A schedule is generated over an approved and a pending leave | Approved leave excludes the guard from generation; pending leave does not | Guard on approved leave excluded; guard with pending leave scheduled for 13 duties with the roster warning that the decision is still owed | Passed |
| TC029 | Server Clock | A duty-time decision is made while the server runs in a different timezone | Duty decisions are read from the server clock in Manila time | A head guard on post at 2100H fell inside the 1700H–0500H night window | Passed (10 checks) |
| TC030 | Post-Generation Notes | Generation produces staffing and configuration problems | Notes are grouped and ranked, and the wording is shared between the web service and the interface | Notes grouped and ranked; the note vocabulary matched between service and interface | Passed (9 cases) |
| TC031 | Dashboard | The dashboard analytics panels are computed | Personnel totals and the daily absence, on-duty, and availability statistics are arithmetically correct | All analytics values computed correctly | Passed (31 cases) |
| TC032 | Dashboard | A summary card is hovered repeatedly | No duplicate-key error is raised during the card's animation | No error raised on repeated hover | Passed (2 cases) |
| TC033 | Notifications | The Notifications screen is opened with pending items | The pending counts on all tabs are populated on open, and each tab refreshes its own | All three counts populated on open | Passed |
| TC034 | AI Review Panel | The AI returns nothing for an absence | The AI panel occupies no space and draws nothing | Panel rendered at zero size with no content | Passed (17 cases) |
| TC035 | Application Layout | The administrator screens are navigated at each supported window size | No layout overflow is raised at any of the seven supported sizes, 1920×1080 down to 1024×640 | Clean at 1920×1080, 1600×900, 1440×900, and 1366×768. At 1280×720, 1152×720, and 1024×640 the four Notifications tabs with their pending-count badges exceed the tab bar by 2.6 px | **Failed** (3 of 7) |
| TC036 | Application Startup | The application is launched | The application builds and shows the Sched login screen | Login screen rendered | Passed |
| TC037 | Integration — Read Contract | All read endpoints are re-issued after the database migration with the clock frozen | Every endpoint answers, none is added or missing, and no field the application reads disappears | 58 of 58 endpoints answered; 50 responses structurally identical; 8 differed — 7 because a collection recorded with items is now empty, and 1 carrying three fields added deliberately with the preparation window | Passed |
| TC038 | System — Live Deployment | The deployed cloud service is called over HTTPS from a client machine | The service answers the read endpoints with the deployed data | All requested endpoints returned HTTP 200; the roster returned 573 personnel, 25 stations, and 25 schedules | Passed |
| TC039 | Reporting | A duty schedule report and the yearly leave report are exported to PDF | The report is produced on the agency letterhead with the configured signatories | [insert here — result of the manual export test] | [insert here] |
| TC040 | Search and Filter | Personnel are searched by name and schedules filtered by station, date, shift, and period | The matching records are returned | [insert here — result of the manual search and filter test] | [insert here] |

#### Table 21. Unit and Integration Test Results — Mobile Application

| Test Case ID | Component/Module | Test Condition | Expected Behavior | Actual Result | Status |
|---|---|---|---|---|---|
| **Mobile Application** | | | | | |
| TC041 | Authentication | A security personnel logs in with issued credentials | Access is granted and the security personnel interface is loaded | [insert here — result of the manual login test] | [insert here] |
| TC042 | Authentication | A head guard logs in with issued credentials | Access is granted and the head guard interface is loaded | [insert here] | [insert here] |
| TC043 | Authentication | The user changes their password from the mobile application | The new password takes effect on the next login | [insert here] | [insert here] |
| TC044 | Schedule Viewing | A guard opens the assigned bi-weekly schedule | The dates, duty hours, station, and assigned post are displayed for each duty | [insert here] | [insert here] |
| TC045 | Schedule Viewing | A guard opens a past schedule period | The archived period is displayed | [insert here] | [insert here] |
| TC046 | Schedule Viewing | The duty window carried on each schedule entry is rendered | The per-post stagger ladder and the entry's duty window are displayed correctly | Stagger ladder and duty window rendered correctly | Passed (18 cases) |
| TC047 | Duty Status | A guard scheduled 0500H–1400H opens the application at 2000H | The guard is not shown *On Duty*, because the duty has ended | Duty status computed from the server wall clock; the guard was not shown On Duty after 1400H | Passed (38 cases) |
| TC048 | Duty Status | The Today's Duty card is rendered in each possible duty status at phone width | The card renders in every status without overflow | Rendered in all statuses at phone width with no overflow | Passed (8 cases) |
| TC049 | Absence Request | A guard files an emergency absence before the duty begins | The request is filed and appears as pending | [insert here] | [insert here] |
| TC050 | Absence Request | A guard attempts to file an emergency absence after the duty has ended | The system prevents it and explains why | Filing blocked once the duty window had passed | Passed |
| TC051 | Leave Request | A guard files a leave request that breaches a rule | The request is refused and the rule that blocks it is stated — day cap, lead time, yearly limit, or cooldown | Refusals named the blocking rule in each case | Passed (54 checks) |
| TC052 | Leave Request | A guard files a valid leave request | The request is accepted and appears as pending | [insert here] | [insert here] |
| TC053 | Day-off Request | A guard requests a specific day off for a period not yet scheduled | The request is filed against the correct period | [insert here] | [insert here] |
| TC054 | Cover Availability | A guard declares availability to cover a duty on a rest day | The cover offer is recorded and raises the guard's ranking among replacement candidates | [insert here] | [insert here] |
| TC055 | Cover Assignment | A guard receives a cover assignment given on short notice | The notification states the station, the post, the adjusted duty hours, and the time to report | Notification carried the station, post, and adjusted hours; a duty needing no adjustment carried no preparation wording | Passed (18 cases) |
| TC056 | Station Overview | A head guard opens the daily roster of the assigned station | The personnel on duty for the shift are listed with their assigned posts | [insert here] | [insert here] |
| TC057 | Attendance Reporting | The day head guard files the attendance report | The morning and afternoon shifts are within scope and may be filed | Day scope filed morning and afternoon only | Passed (7 cases) |
| TC058 | Attendance Reporting | The night head guard files the attendance report | Only the night shift is within scope; the report never falls back to all shifts | Night scope filed the night shift only | Passed |
| TC059 | Attendance Reporting | A head guard attempts to submit the same shift a second time | The duplicate submission is prevented | Second submission for the same shift refused | Passed |
| TC060 | Notifications | A schedule is published while the guard is logged in | The notification is received and opens the published schedule | [insert here] | [insert here] |
| TC061 | Notifications | A decision is made on a filed request | The guard is notified of the decision | [insert here] | [insert here] |

*Note: the test cases whose Actual Result is marked [insert here] are those verified by manual execution on the device rather than by an automated check. Their results are to be recorded from the test run conducted with the agency.*

#### Table 22. Summary of Test Execution

| Test Level | Scope | Checks Executed | Result |
|---|---|---|---|
| Unit — scheduling rules and web service | 12 standalone harnesses over generation, placement, rotation, leave, replacement, special assignment, station rename, server clock, and the AI modules | 284 | 284 passed |
| Unit — application interface | 13 Flutter test files over the widgets and the pure functions behind them | [insert here] | [insert here] |
| Integration — read contract | Golden-file comparison of all GET endpoint responses with the clock frozen | 58 endpoints | 58 of 58 answered; no endpoint added or missing |
| System — live deployment | The deployed cloud service answering over HTTPS | All requested endpoints | HTTP 200; 573 personnel, 25 stations, 25 schedules |
| **Total automated checks** | | **[insert here]** | **[insert here]** |

#### Discussion of the Testing Results

**On the integration instrument.** Integration testing addressed the risk that the three parts of the system can each be correct in isolation and still disagree at their boundaries. This mattered most during the migration of the database to Supabase (PostgreSQL), where the application and the web service had to keep speaking to each other unchanged while everything underneath them was replaced. The instrument built for this is a **golden-file contract test**: it records the exact response of every read endpoint at a fixed instant, then re-issues all of them after a change and reports any difference as a unified diff. Fifty-eight endpoint responses are under contract. Because several endpoints answer relative to *today* — the leave windows, the special-request windows, the station overviews, and cover offers — the server clock must be frozen at the same instant for the recording and for every comparison, otherwise the calendar alone produces eleven failures that no one can act on.

Of the eight responses that differed from the recorded contract, **none is a change to the shape of the response the application depends on**. Seven differ only because a collection that held items when the contract was recorded is now empty — the pinned special assignments of a schedule, and the day-off list of a station overview — so the keys of the absent items are absent with them. The eighth, the replacements endpoint, carries three fields more than the recording (`originalTimeIn`, `originalTimeOut`, and `prepAdjusted`), which were added deliberately with the preparation-window feature after the contract was recorded. No field the application reads has disappeared and no endpoint has vanished, which is the property the contract exists to protect.

Two further suites — the write-path suite over sequence allocation, updates, deletes with cascade, the station rename transaction, generation writing duty rows, publishing to many recipients at once, and mark-all-read counts, and the repository-layer suite beneath both backends — were **not re-run for this report**, because they mutate the database and restore it by wiping and reloading the corpus, which cannot be done against the deployed data.

**On the one open defect.** The layout suite (TC035) reports three failures. They are a single defect reported once for each window size at which it appears — 1280×720, 1152×720, and 1024×640. At widths of 1280 pixels and below, the four tabs of the Notifications screen together with their pending-count badges exceed the width available to the tab bar by 2.6 pixels. Navigation is clean at the four larger sizes. The defect is cosmetic: it affects no data and no scheduling decision, and it appears only when a pending-count badge is displayed. It is reported here rather than omitted, because the purpose of the layout suite is precisely to surface differences of this size before a user meets them.

#### Table 23. Defect Log

| # | Defect | Effect | Resolution | Status |
|---|---|---|---|---|
| 1 | A guard scheduled 0500H–1400H was still shown *On Duty* late in the evening | The guard could file an emergency absence for a duty that had already ended | Duty status is computed from the server wall clock, not from the date alone | Resolved |
| 2 | A notification filed on one date still offered *Find Replacement* two days later | An administrator could assign a replacement to a shift that had already finished | The replacement action closes when the post times out, and the web service refuses a late apply, naming the post | Resolved |
| 3 | The repository factory returned a document-shaped repository regardless of the configured backend | Every read was correct while eleven write endpoints answered HTTP 500 | The factory honours the backend setting; a separate write-path suite was built, because reads and writes fail independently | Resolved |
| 4 | Pending-count badges on the Notifications tabs stayed blank until the tab was opened | A full inbox read as an empty one | The three counts are fetched when the screen opens, and each tab still refreshes its own | Resolved |
| 5 | Deleting and re-creating a station to rename it stranded the personnel assigned to it | Affected personnel were left out of generation entirely | Renaming through Edit Station updates employee and rotation records in one transaction; any remaining stranded personnel are named in the generation notes | Resolved |
| 6 | An empty generated schedule could be published | The published schedule showed no guards on any day | Publishing refuses an empty schedule and Publish All skips it, reporting which one was skipped | Resolved |
| 7 | The head guard report scope fell back to all shifts | The night head guard could file the morning and afternoon shifts | Scope is fixed by role — day files morning and afternoon, night files night — and each shift may be submitted once | Resolved |
| 8 | Repeated hovering of a dashboard summary card raised a duplicate-key error | The card's icon animation threw during interaction | Keys were made unique across the animation | Resolved |
| 9 | Schedule-generation notes and their display used divergent wording | A staffing note could be produced that the application could not present | The note vocabulary is shared between the web service and the application and asserted by the tests | Resolved |
| 10 | A replacement assigned at short notice was given the post's own start time | The assigned guard could not physically reach the post by the stated time, so the guard on post still extended | Short-notice covers receive a preparation window; the notification states both the adjusted hours and the post's own hours | Resolved |
| 11 | Four Notifications tabs with pending-count badges overflow the tab bar by 2.6 pixels at 1280×720, 1152×720, and 1024×640 | Cosmetic only; a debug layout warning, no data affected | Not yet applied | **Open** |

---

## 4.4 Evaluation Results

> *This section is retained exactly as supplied and is to be completed when the evaluation results are gathered. The sub-section numbering below (4.2.1 and 4.2.2) is as it appears in the supplied outline; under this chapter's numbering it should read 4.4.1 and 4.4.2.*

### 4.2.1 Evaluation by IT Experts

Following the ISO 25010 software quality model, an evaluation was carried out on the *[insert here]*.

The study involved 5 IT expert respondents *[insert here]*.

The evaluation focused on Functional Suitability, Reliability, Performance Efficiency, Usability, Compatibility, and Maintainability. Each criterion was measured using a 5-point Likert scale, providing insights into the system's effectiveness, accuracy, and adaptability.

**Table #. Software Evaluation of Functional Suitability Criterion by IT Expert**

| Criterion | Overall Rating | Interpretation |
|---|---|---|
| Functional Suitability | | |
| Performance Efficiency | | |
| Compatibility | | |
| Reliability | | |
| Usability | | |
| Maintainability | | |
| **Overall System Rating :** | | |

Table # presents the ISO 25010 software evaluation results for the *[insert here]*.

### 4.2.2 Evaluation by End Users

The end-user evaluation involved 211 respondents comprising Admin, Head Guards, and Security Personnel of Kaizen Security Agency Corp. The evaluation procedure followed the same ISO 25010 framework *[insert here]*.

**Table #. Software Evaluation of Functional Suitability Criterion**

| Criterion | Sub-Criterion | Rating | Interpretation |
|---|---|---|---|
| **FUNCTIONAL SUITABILITY** | Admin: The web dashboard provides complete employee, station, and schedule management functions needed for my administrative tasks. | | |
| | Head Guard: The mobile app allows me to report attendance and view my station overview effectively. | | |
| | Security: The mobile app provides all necessary functions for viewing my duty schedule and submitting requests. | | |
| | **Overall Rating** | | |

Table # presents the ISO 25010 software evaluation results for *[insert here]*.

**Table #. Software Evaluation of Performance Efficiency Criterion**

| Criterion | Sub-Criterion | Rating | Interpretation |
|---|---|---|---|
| **PERFORMANCE EFFICIENCY** | Admin: The web dashboard loads and responds quickly during schedule generation. | | |
| | Head Guard: The mobile app performs smoothly when reporting attendance and checking schedules during my shift. | | |
| | Security: The mobile app loads my duty schedule quickly and runs without lag on my smartphone. | | |
| | **Overall Rating** | | |

Table # presents the ISO 25010 software evaluation results for the *[insert here]*.

**Table #. Software Evaluation of Reliability Criterion**

| Criterion | Sub-Criterion | Rating | Interpretation |
|---|---|---|---|
| **RELIABILITY** | All: The system is consistently available whenever I need to access schedules or submit reports. | | |
| | All: The system handles errors and connection issues without crashing or losing my data. | | |
| | All: The AI-generated schedules and attendance data are accurate and dependable for daily operations. | | |
| | **Overall Rating** | | |

Table # presents the ISO 25010 software evaluation results for the *[insert here]*.

**Table #. Software Evaluation of Compatibility Criterion**

| Criterion | Sub-Criterion | Rating | Interpretation |
|---|---|---|---|
| **COMPATIBILITY** | Admin: The web dashboard works properly on my computer/browser and displays consistent data across sessions. | | |
| | Head Guard: The mobile app works properly on my smartphone and syncs attendance data correctly with the Admin dashboard. | | |
| | Security: The mobile app works properly on my smartphone and shows consistent schedule data with the Admin's records. | | |
| | **Overall Rating** | | |

Table # presents the ISO 25010 software evaluation results for the *[insert here]*.

**Table #. Software Evaluation of Usability Criterion**

| Criterion | Sub-Criterion | Rating | Interpretation |
|---|---|---|---|
| **USABILITY** | Admin: The web dashboard is easy to learn and use for managing employees, stations, schedules, and handling attendance reports. | | |
| | Head Guard: The mobile app is easy to use for reporting attendance and checking my station overview. | | |
| | Security: The mobile app is easy to learn and use for checking my duty schedule and submitting requests. | | |
| | **Overall Rating** | | |

Table # presents the ISO 25010 software evaluation results for the *[insert here]*.

**Table #. Software Evaluation of Maintainability Criterion**

| Criterion | Sub-Criterion | Rating | Interpretation |
|---|---|---|---|
| **MAINTAINABILITY** | All: The system's design appears well-structured and organized, suggesting it can be maintained and improved in the future. | | |
| | All: Errors or issues in the system can be **identified and explained clearly** when reported to the development team. | | |
| | All: The system documentation and structure support future maintenance and new user training. | | |
| | **Overall Rating** | | |

**Table #. Software Evaluation Summary**

| Criterion | Overall Rating | Interpretation |
|---|---|---|
| Functional Suitability | | |
| Performance Efficiency | | |
| Compatibility | | |
| Reliability | | |
| Usability | | |
| Maintainability | | |
| **Overall System Rating :** | | |

Table # presents the summary of the software evaluation results for *[insert here]*.

### Findings and Discussion

This section presents the major findings of the study *[insert here]*.
