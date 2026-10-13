# CHAPTER V
# SUMMARY OF FINDINGS, CONCLUSIONS, AND RECOMMENDATIONS

This chapter presents the summary of findings, the conclusions drawn from those findings, and the recommendations arising from the development, testing, and evaluation of *A Scheduling and Duty Management System with AI Application in Absence Handling* for Kaizen Security Agency Corp. Section 5.1 summarises the findings reported in Chapter IV, organised according to the four specific objectives stated in Chapter I. Section 5.2 states the conclusions the study draws from those findings, answering each of the questions raised in the Statement of the Problem. Section 5.3 offers recommendations for the agency, for the continued development of the system, and for future researchers.

---

## 5.1 Summary of Findings

The study set out to replace a manual, spreadsheet-based scheduling process at Kaizen Security Agency Corp. with a scheduling and duty management system that generates bi-weekly duty schedules automatically, delivers them to the personnel they concern, and assists administrators in handling absences with the aid of artificial intelligence. The system was developed as three parts — a Python (FastAPI) web service holding the scheduling logic, a Supabase (PostgreSQL) database holding the records, and a Flutter application compiled for Windows desktop and the web for administrators and for Android for head guards and security personnel — and was produced in successive working builds under the Rapid Application Development model adopted in Chapter III. All fifteen modules identified in the scope of the study were completed. The findings are summarised below.

### 5.1.1 On the Automated Generation and Balancing of Duty Schedules

**1. The system produced complete bi-weekly schedules for all twenty-five stations directly from the station configuration.** Generation is demand-driven: an administrator declares, per shift, the required number of personnel and the named post assigned to each slot together with the duty hours of each post, and the system deploys exactly what that configuration asks for rather than distributing personnel evenly across stations. Verification against the scheduling rules confirmed that daily coverage matched the required headcount per shift and post for every station tested, that no guard was booked twice on the same day, that rest days were observed, that each primary head guard totalled the expected 156 hours over a 15-day period, that relievers remained within their bounded duty range, and that no reliever was assigned to a night shift.

**2. The arithmetic of the schedule ceased to be work.** A complete 15-day schedule for a station of nineteen posts was produced in a median of 1.7 milliseconds, the slowest of twenty-five runs taking 3.2 milliseconds, and all twenty-five stations — 7,700 duty assignments in total — in 0.04 seconds. Measured against the manual preparation of the same schedules in spreadsheets, this is the clearest quantitative finding of the study for the first objective.

**3. Rotation redistributed personnel between cycles while remaining reproducible.** Testing confirmed that personnel moved between stations from one rotation cycle to the next, that preferred-station placement stayed within the intended shares, that familiar personnel were retained at each station, and that regenerating the same cycle produced an identical placement. Reproducibility was found to matter operationally: an administrator who regenerates a period must not receive a different roster each time.

**4. Generation was found to be more useful when it refuses to fail.** The system does not abort when the available personnel cannot fill a requirement. It produces the best roster the configuration allows and records the shortfall as a reviewable note. The rule the system enforces is therefore not *"every post is filled"* — which no software can guarantee when the agency is short of guards — but *"every gap is either filled or flagged."* In testing, a generated station period reported seven flagged shortfalls, every one surfaced in the notes rather than silently absorbed.

**5. A data-integrity finding emerged that was not a scheduling problem at all.** Stations are joined by name in employee and rotation records but by identity in schedules. Renaming a station by deleting and re-creating it therefore stranded every guard assigned to it, and those guards dropped out of generation entirely. The system resolves this by performing renames through the Edit Station function, which updates employee and rotation records in a single transaction, and by naming any personnel who remain stranded in the generation notes.

### 5.1.2 On the AI-Assisted Handling of Absences

**6. The screening, scoring, ranking, and notification that previously required an administrator to work the telephone are now performed by the system.** When an absence is reported, the scheduling rules first remove every candidate who is unavailable, already on duty that date, also reported absent, or ineligible for the shift or post, and score the survivors on station familiarity, personnel type, workload, and declared availability. Only that screened shortlist is passed to the language model, which re-ranks it and supplies a reason for its recommendation. The administrator confirms the assignment.

**7. The most consequential finding concerns what happens when the AI does not answer.** The rule-based ranking survived every AI failure path tested — no API key configured, the feature switched off, quota exhausted, network timeout, and a malformed response from the model. In each case the administrator received the same qualified, ranked candidates the rules produced. The separation of the two stages is what makes this possible: the AI re-ranks a list it did not build, so the usefulness of the system does not depend on a third-party service being reachable. The AI is advisory, exactly as delimited in Chapter I.

**8. The cost of the AI feature is bounded by the number of absences, not by administrator behaviour.** Testing confirmed one model request per absence, cached, with a changed shortlist invalidating the cached review. Reopening the replacement screen does not spend another request. The payload sent to the model was confirmed to carry job attributes and identifiers only, with no personal data present.

**9. Two rules governing the passage of time proved as important as the choice of candidate, and both were added in response to defects found during testing.** The first is the expired-post refusal: a stale notification once still offered *Find Replacement* for a shift that had already finished, so the action now closes when the post times out and the web service independently refuses a late application, naming the post. The second is the preparation window: a guard assigned at short notice was being given the post's own start time, which is not reachable from home, so short-notice duty hours are now adjusted for travel and preparation and the notification states both the adjusted hours and the post's own hours. Thirty checks over the preparation window and twenty-five over the expired-post refusal all passed.

### 5.1.3 On the Reduction of Delay and of Extended Working Hours

**10. The unbounded portion of the replacement process was removed.** Under the manual process an absence became known by telephone or by the guard's failure to appear; the administrator reviewed the spreadsheet to establish who was free, decided from memory whom to call first, and then telephoned candidates one at a time, each refusal returning the administrator to the start of the list. With the system, the head guard files the attendance report from the station and it reaches the administrator's dashboard at once; every ineligible candidate is removed before the administrator opens the screen; the qualified candidates arrive already ranked and explained; and guards who have declared a cover offer for that rest day are ranked highest, so the administrator confirms an assignment rather than negotiating one. The reduction claimed is the replacement of an unbounded sequence of telephone calls with a single confirmation, and it does not depend on how quickly any particular administrator worked the telephone.

**11. Extended working hours end when the replacement arrives, not when the replacement is assigned.** This is why the preparation window bears on this objective and not only on the previous one: a guard assigned to a start time already past relieves no one. The adjusted, reachable reporting time — stated in the notification alongside the post's own hours — is the mechanism by which the on-duty guard's extension actually ends.

**12. Instructions no longer travel by voice.** The notification issued to a replacement names the station, the post, the adjusted duty hours, and the time to report, so nothing has to be relayed verbally or remembered.

### 5.1.4 On Accessibility, Timeliness, and Usability

**13. One record serves three clients.** The administrator application on Windows desktop and the web and the mobile application on Android for head guards and security personnel all read the same records through one web service, with access governed by role. A guard no longer requests a file or visits an office to learn where they are posted: the assigned bi-weekly schedule, past schedules, and the details of each duty are on the phone.

**14. Information reaches its readers when it changes rather than when a file is next distributed.** Publishing a schedule notifies its recipients, a decision on a request notifies the guard who filed it, and a cover assignment notifies the guard assigned. Duty status is computed against the server clock in Manila time, so what the application displays about a duty is true at the moment it is read — a property established after an early build showed a guard scheduled 0500H–1400H as *On Duty* late in the evening, which would have allowed an emergency absence to be filed against a duty already ended. Thirty-eight automated checks now hold that behaviour in place.

**15. Schedules are presented for reading rather than for decoding.** Views are organised by station, period, and shift with colour-coded indicators for rest days, absences, and covered duties; personnel can be searched by name and records filtered by station, date, shift, and period; and duty reports per station and per period together with the yearly leave report can be exported to PDF on the agency's letterhead with configurable signatories.

### 5.1.5 On Testing and System Quality

**16. The system was verified by 284 automated unit checks across twelve harnesses covering generation, placement, rotation, leave, replacement, special assignment, station rename, the server clock, and the AI modules, all of which passed.** Integration testing was carried out through a golden-file contract test that records the exact response of every read endpoint at a fixed instant and re-issues all of them after a change. Fifty-eight endpoint responses are under contract; all fifty-eight answered, no endpoint was added or lost, and no field the application reads disappeared. Of the eight responses that differed from the recording, seven differed only because a collection that held items at recording time is now empty, and the eighth carries three fields added deliberately with the preparation-window feature. System testing against the deployed cloud service returned HTTP 200 for every requested endpoint, with 573 personnel records, 25 stations, and 25 schedules served over HTTPS.

**17. Eleven defects were logged during development; ten are resolved and one remains open.** The open defect is cosmetic: at window widths of 1280 pixels and below, the four tabs of the Notifications screen together with their pending-count badges exceed the width available to the tab bar by 2.6 pixels. It affects no data and no scheduling decision, and navigation is clean at the four larger supported window sizes. It is reported rather than omitted because surfacing differences of this size before a user meets them is the purpose of the layout suite.

**18. Two write-path suites were not re-run for this report.** The suite covering sequence allocation, updates, cascading deletes, the station rename transaction, generation writing duty rows, publishing to many recipients at once, and mark-all-read counts, together with the repository-layer suite beneath both backends, mutate the database and restore it by wiping and reloading the corpus, which cannot be done against deployed data.

### 5.1.6 On the Evaluation by IT Experts and End Users

**19.** *[insert here — summary of the ISO/IEC 25010 evaluation by the five IT expert respondents: the overall weighted mean and its interpretation, and the criteria that scored highest and lowest among Functional Suitability, Performance Efficiency, Compatibility, Reliability, Usability, and Maintainability.]*

**20.** *[insert here — summary of the ISO/IEC 25010 evaluation by the 211 end-user respondents comprising administrators, head guards, and security personnel: the overall weighted mean and its interpretation, and the criteria that scored highest and lowest.]*

**Table 24. Summary of Findings Against the Specific Objectives**

| Specific Objective | Principal Finding | Evidence |
|---|---|---|
| 1. Design an automated scheduling feature that follows station requirements and posts per shift, observes rest days, and rotates personnel | Complete bi-weekly schedules were generated for all 25 stations from the station configuration, with coverage, rest days, head guard hours, and reliever bounds all verified; shortfalls are flagged rather than hidden | Median 1.7 ms per station period; 7,700 duty assignments in 0.04 s; TC004–TC016; 284 unit checks passed |
| 2. Develop an AI-based absence handling feature that recommends suitable relievers | Rules screen and score, the AI re-ranks and explains, and the administrator decides; the rule-based ranking survives every AI failure path, and one model request is spent per absence | TC020–TC026; 18 checks on the payload, 18 on the failure paths, 30 on the preparation window, 25 on the expired-post refusal |
| 3. Implement and test the system to reduce delays in assigning replacements and minimise extended working hours | An unbounded sequence of telephone calls was replaced by a single confirmation, and the preparation window gives the replacement a reporting time that can actually be met | Table 19 process comparison; TC024, TC025, TC055; Table 18 measured performance |
| 4. Evaluate the system for accessibility, timeliness, and usability | One web service serves three role-based clients from one record; information is pushed on change; duty status is read from the server clock in Manila time | 58 of 58 endpoints under contract; TC029, TC047; live deployment serving 573 personnel, 25 stations, 25 schedules |

---

## 5.2 Conclusions

On the basis of the findings summarised above, the study draws the following conclusions, stated against the questions raised in the Statement of the Problem and the objectives set in Chapter I.

**1. The manual preparation of bi-weekly duty schedules is not a problem of effort but of arithmetic, and the arithmetic is now performed by the system.** The challenges administrators encountered in organising and balancing workload — differing requirements per station and per shift, rest days that must be honoured, relievers who must cover them, and a rotation that must move personnel without disregarding their preferences — are all consequences of holding many constraints in the head at once while filling a spreadsheet. The study concludes that when the station configuration itself is made the input to generation, a complete and rule-compliant 15-day roster for twenty-five stations is produced in a fraction of a second, and the administrator's remaining work is to review it rather than to construct it. The first specific objective was therefore attained.

**2. A scheduling system is trustworthy not because it always fills every post, but because it never hides an empty one.** The study concludes that the decision to complete generation and record shortfalls as reviewable notes, rather than to abort when personnel are insufficient, is what makes the generated schedule usable in an agency that is periodically short of guards. An unexplained hole in a roster is a defect; a reported one is information the administrator needs before the day of duty. This conclusion is offered as a design principle for scheduling systems generally, not only for this one.

**3. The delay in handling absences was caused by the search and the negotiation, not by the decision, and it is the search and the negotiation that the system removes.** The study concludes that separating a rule-based screening stage from an AI ranking stage answers the second and third objectives together: the rules guarantee that no ineligible candidate ever reaches the administrator, and the AI orders the survivors and explains the order. The administrator's task becomes a confirmation rather than an open-ended sequence of telephone calls, and because guards may declare in advance their willingness to cover a rest day, the refusal loop is removed for those who have volunteered.

**4. Artificial intelligence is safest in this domain when it is placed where it can only improve an answer that already exists.** Because the language model re-ranks a list the system's own rules produced, the system continues to deliver qualified, ranked candidates when the model is unreachable, out of quota, disabled, or malformed in its reply. The study concludes that the advisory placement of AI defined in Chapter I is not a limitation accepted for safety's sake alone, but the arrangement that makes the feature dependable for an agency whose stations must be covered whether or not an external service answers that afternoon.

**5. Reducing the extension of an on-duty guard's shift is a problem of reachability, not of assignment speed.** The study concludes that assigning a replacement quickly accomplishes nothing if the reporting time given cannot be met, and that the preparation window — an automatic adjustment of duty hours for travel and preparation, with both the adjusted hours and the post's own hours stated in the notification — is the mechanism by which the third objective is actually served. The corresponding refusal to assign a replacement to a post whose duty has already ended closes the same problem from the other direction.

**6. Duty information becomes timely only when the system reasons about time as the user experiences it.** Two of the defects found during testing were of one kind: the system displaying something that had been true earlier in the day. The study concludes that computing duty status from the server wall clock in Manila time, rather than from the calendar date, is what makes what the guard reads on the phone true at the moment it is read, and that this — together with role-based access to one shared record and notifications issued on change rather than on file distribution — attains the fourth objective's requirements of accessibility and timeliness.

**7. The three parts of the system can each be correct and still disagree at their boundaries, and a contract test is what prevents that.** The study concludes that the golden-file contract over all fifty-eight read endpoints was the decisive instrument during the migration of the database to Supabase, because it holds the property the users actually depend on — that a schedule published by an administrator is the schedule the guard sees — under direct comparison rather than under assurance.

**8. The system as delivered is complete against the scope stated in Chapter I and is fit for operational use, with one cosmetic defect outstanding.** All fifteen modules were completed, 284 automated unit checks passed, all fifty-eight contracted endpoints answered, and the deployed service served the full corpus of 573 personnel records, 25 stations, and 25 schedules over HTTPS. The single open defect is a 2.6-pixel overflow of a tab bar at window widths of 1280 pixels and below, which affects no data and no scheduling decision.

**9.** *[insert here — the conclusion drawn from the ISO/IEC 25010 evaluation: what the overall weighted mean obtained from the IT experts and from the 211 end users indicates about the acceptability of the system for use at Kaizen Security Agency Corp., and how the Usability and Performance Efficiency ratings in particular answer the fourth specific objective.]*

---

## 5.3 Recommendations

In the light of the findings and conclusions, the following recommendations are offered.

### 5.3.1 For Kaizen Security Agency Corp.

**1. Rename stations only through the Edit Station function.** Because employee and rotation records join stations by name while schedules join them by identity, deleting and re-creating a station to rename it strands the personnel assigned to it and removes them from generation. Edit Station performs the rename in a single transaction and is the only safe route. This should be stated explicitly in the administrator's operating procedure.

**2. Keep the station and post configuration current, because it is the input to everything downstream.** Generation is demand-driven: the number of personnel deployed to a station, the posts they occupy, and the hours they keep are all consequences of the configuration. A configuration that has drifted from the agency's actual requirement will produce a schedule that is internally correct and operationally wrong.

**3. Review the generation notes before publishing a schedule.** The system deliberately completes generation over a staffing shortfall and records it. The notes are therefore the agency's advance warning of an uncovered post, and their value is realised only if they are read before the period is published rather than discovered on the day of duty.

**4. Encourage security personnel to declare cover offers for their rest days.** A declared cover offer raises a guard's ranking among replacement candidates, and the finding that the refusal loop disappears for volunteers holds only to the extent that guards use the feature. The agency may wish to pair this with whatever internal recognition it already applies to guards who accept short-notice duty.

**5. Retain administrative confirmation of every AI recommendation.** The recommendation is advisory by design, and the administrator holds knowledge the system does not. The value of the feature lies in the ordering and the explanation, not in the removal of the administrator's judgement.

**6. Record the operational baseline the study could not obtain.** The average time previously taken to secure a replacement under the manual process, and the average length of shift extension incurred while waiting, would allow the reduction claimed in the third objective to be expressed in elapsed time rather than in process steps. The agency is in a position to capture both from its own records, and doing so would strengthen any future evaluation of the system.

**7. Provide a short orientation for head guards on the scope rule of the attendance report.** The day head guard files the morning and afternoon shifts and the night head guard files the night shift, and each shift may be submitted only once. The rule is enforced by the system, but a head guard who expects to file all three shifts will read the enforcement as a fault.

### 5.3.2 For the Continued Development of the System

**8. Close the outstanding layout defect.** The four Notifications tabs with their pending-count badges exceed the tab bar by 2.6 pixels at 1280×720, 1152×720, and 1024×640. Shortening the tab labels at narrow widths, allowing the tab bar to scroll, or moving the badge inside the label would each resolve it, and the existing layout suite already covers all seven supported window sizes.

**9. Provision a dedicated staging database so the write-path and repository-layer suites can be re-run routinely.** These two suites cannot be executed against deployed data because they restore state by wiping and reloading the corpus. A staging instance holding a copy of the corpus would return them to the regular test cycle, where they belong, since reads and writes were shown to fail independently of one another.

**10. Address the cold start of the deployed web service.** The first request after an idle period took 23.71 seconds against sub-second times thereafter. A keep-warm request on a schedule, or a hosting tier that does not idle the instance, would remove the one measurement in Table 18 that a user would experience as the system being slow.

**11. Add the notification channels delimited out of this study once resources allow.** SMS or electronic-mail notification was excluded in Chapter I on the grounds of third-party integration cost and complexity, and in-app notification serves the agency well while the application is installed and opened. A guard who has not opened the application, however, is not reached, and short-notice covers are precisely the case where reaching them matters most.

**12. Consider learning from the administrators' decisions.** The system already records the administrator's decision against the AI's recommendation. Over a sufficient period this record would show how often the recommended candidate is the one confirmed, which is both a direct measure of the feature's usefulness and a basis for tuning the scoring weights the rules apply before the AI ever sees the list.

**13. Extend the mobile application to iOS and add offline reading of the current period.** The application is deployed for Android, and a guard on post without a data connection cannot at present consult a schedule already published to them. Caching the current period for offline reading would make the schedule available in the circumstances guards most often need it.

**14. Keep the golden-file contract in step with the system.** The contract's value depends on its being re-recorded deliberately when an endpoint is intentionally changed, and compared after every subsequent modification. It should be run as a matter of course before any release, and any difference it reports should be explained in writing before that release proceeds, as was done for the eight differences reported in Chapter IV.

### 5.3.3 For Future Researchers

**15. Study the system's effect over a full deployment period rather than at the point of delivery.** The findings of this study establish that the system behaves as specified and that its users found it acceptable. What they cannot establish is the longitudinal effect on absenteeism, overtime, and personnel satisfaction, which requires observation over months of live operation.

**16. Compare the AI ranking against the rule-based ranking under live conditions.** Because the system produces both orderings and records which candidate the administrator confirmed, a natural comparison is available to a researcher with access to the operating data: whether the AI's re-ranking measurably improves on the rules it re-ranks, and under what circumstances.

**17. Test the demand-driven scheduling approach in other operating contexts.** The station configuration, the three-group placement rule with its adjacency constraint, the reliever binding, and the fill-or-flag contract were designed around the deployment of security personnel along a rail line. Their applicability to hospitals, manufacturing shifts, or field service organisations — where the topology of the sites and the qualification of personnel differ — is an open question that this study's design does not answer.

**18. Examine the ethical and organisational dimensions of AI-assisted assignment.** This study placed the AI in an advisory position and the administrator in the deciding one, and found that arrangement to be technically dependable. Whether personnel perceive an AI-influenced assignment as fair, and how such a system should disclose its reasoning to the people it assigns, are questions of acceptance rather than of correctness, and they are worth asking before the advisory boundary is relaxed anywhere.
