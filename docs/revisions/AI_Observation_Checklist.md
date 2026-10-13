# Completing the two AI observation checks

Status: prepared procedure; not executed. Use the updated Section 4.1 Word/PDF for the integrated testing table and historical evidence notes.

Keep the existing ISO/IEC 25010 questionnaire results. Complete the following checks through researcher observation and retain the evidence.

## TC010 — Check the AI explanation against its inputs

Use an isolated test environment with fictitious guards, one absent guard, and at least two rule-eligible alternatives. Use a duty date/time whose cover window is still open. Give the alternatives different, known station familiarity and recent cover counts. Record the build and take a snapshot of the input records.

1. Open the absence's Find Replacement screen. Obtain a fresh live AI review. Record the response source, model/prompt version where available, and the exact context sent to the model. A cached response is not a new live trial; a simulated response is only a display test.
2. Save the raw review and a screenshot of the AI Recommendation panel. Record the recommended and runner-up IDs, rationale, and any risk/trade-off text. Compare the displayed text with the returned review.
3. List each factual claim in the explanation and match it to the context and underlying records. For example, a claim of two recent covers must match coversLast30Days = 2. Claims about rest, availability, or familiarity also need supporting inputs; record unsupported claims as such.
4. Record whether the panel clearly labels AI advice. In a separate run, disable AI or use a controlled unavailable response in the test environment; inspect whether the AI panel disappears and rule-based candidates remain usable. Label this run disabled/simulated/unavailable as appropriate.
5. Complete the observation sheet. Pass only if every applicable criterion is met: supported factual claims, faithful display, clear AI labeling, and usable fallback without a false AI recommendation. An observed mismatch is Failed; a missing live review or missing input capture leaves the relevant part Not assessed.

Evidence: Input/context snapshot; raw review; labeled-panel screenshot; claim-by-claim comparison; disabled/unavailable screenshot; date/time, observer, build, and AI mode for each run.

One successful observation supports that scenario only. For broader evidence, predefine contrasting scenarios and report all their outcomes; no particular sample count is asserted here as an ISO requirement.

## TC011 — Check administrator choice, cancellation, and confirmation

Use an isolated test absence with an open cover window, at least two eligible guards, and a displayed recommendation. Call the recommended guard A and another eligible guard B. A controlled simulated review is acceptable for this workflow check if its mode is recorded. Capture the initial schedule, replacement record, relevant absence status, and test notification count.

1. Open Find Replacement and record the AI-recommended guard A. Verify that simply opening/viewing the recommendation has not assigned a replacement or changed the schedule.
2. Choose eligible guard B from the candidate list. Capture the confirmation dialog naming B. Before confirming, verify that the schedule and replacement assignment remain unchanged.
3. Click Cancel. Refresh/read the stored state and verify that no replacement was assigned, no replacement notification was created, and the schedule remains unchanged. In the absence-approval flow, verify that cancellation has not approved the request. An AI review/cache entry may exist without an assignment.
4. Start a separate assignment attempt for B, then click Assign in the confirmation dialog. Verify the stored replacement and affected schedule identify B, even though the AI recommended A. Check the notification recipient and, when applicable, the absence approval.
5. Inspect the AI decision record: the original recommended ID should remain A and the assigned ID should be B with a decision time. Save before/after evidence. Pass only if all workflow criteria are observed; any incorrect change is Failed. Leave unexecuted parts Not assessed.

Evidence: Initial state; recommendation A; confirmation dialog for B; unchanged state after Cancel; persisted schedule/replacement/notification after Assign; decision record; date/time, observer, build, and AI mode.

Selecting B instead of A is the override. The current screen does not require a separate Reject AI button. A passing direct decision-recording unit test alone does not complete this UI observation.

## Record each run

| Field | Entry |
| --- | --- |
| Run ID / test case | |
| Observer | |
| Execution date/time + time zone | |
| Build/commit + environment | |
| Scenario / input record references | |
| AI mode: live, simulated, cached, disabled, unavailable | |
| Model / prompt version / response source | |
| Actual outcome for each step | |
| Evidence file references | |
| Result: Passed, Failed, Not assessed | |
| Unexecuted criteria or discrepancies | |

For TC010, also make a claim comparison:

| Exact factual claim | Context field/value | Underlying record | Supported / contradicted / unsupported |
| --- | --- | --- | --- |
| | | | |

Enter actual results only after execution. If some steps were not performed, preserve that limitation; do not mark the whole row Passed. Keep failed runs when documenting a later correction and retest.

Table 25 mobile TC003 and TC006 also still need their original evidence checked, or a new observation recorded.
