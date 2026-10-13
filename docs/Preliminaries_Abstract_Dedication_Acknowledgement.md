# PRELIMINARY PAGES

*Abstract, Dedication, and Acknowledgement for* **A Scheduling and Duty Management System with AI Application in Absence Handling** *for Kaizen Security Agency Corp.*

> Bracketed `[insert here — …]` items follow the same convention used in Chapters IV and V: they mark details only the researchers or the panel can supply.

---

# ABSTRACT

Workforce scheduling in security operations requires balancing station requirements, shift coverage, rest days, and unexpected absences, and when it is carried out manually the effort is considerable and the result is difficult to keep accurate. Kaizen Security Agency Corp., which deploys security personnel across twenty-five (25) Light Rail Transit (LRT) stations, prepared its bi-weekly duty schedules in spreadsheet applications, distributed them as files, and repaired them by telephone whenever a guard failed to report for duty. This study developed **A Scheduling and Duty Management System with AI Application in Absence Handling** to automate the preparation of bi-weekly duty schedules, to deliver duty information to the personnel it concerns, and to assist administrators in handling absences through an artificial-intelligence-assisted recommendation of replacement personnel.

The system was developed under the **Rapid Application Development (RAD)** model in three parts: a **Python (FastAPI)** web service holding the scheduling logic and exposing 71 HTTP endpoints, deployed on a cloud platform; a **Supabase (PostgreSQL)** database holding the records; and a **Flutter** client application compiled for Windows desktop and the web for administrators and for Android for head guards and security personnel. Schedule generation is demand-driven: each station declares, per shift, the required number of personnel and the named post assigned to every slot, and the system rosters exactly what that configuration requires, observing rest days, assigning relievers to cover them, and redistributing personnel across stations every rotation cycle while honouring their preferred stations. When the available personnel are not enough to fill a requirement, generation does not abort; it produces the best roster the configuration allows and records the shortfall as a reviewable note. Absence handling separates screening from recommendation: the system's own scheduling rules first remove every candidate who is unavailable, already on duty that date, also reported absent, or ineligible for the shift or post, and score the survivors on station familiarity, personnel type, workload, and declared availability; only that screened shortlist is passed to the **Google Gemini API**, which re-ranks it and supplies a reason for its recommendation. The artificial intelligence is advisory throughout — the administrator confirms every assignment, and the rule-based ranking remains available whenever the AI service does not answer.

The system was verified through 284 automated unit checks across twelve harnesses, a golden-file integration contract holding the responses of 58 read endpoints under comparison, and system testing against the deployed cloud service. A complete 15-day schedule for a single station was generated in a median of 1.7 milliseconds, and all twenty-five stations — 7,700 duty assignments in total — in 0.04 seconds. The system was then evaluated using the **ISO/IEC 25010** software quality model by 5 IT expert respondents and 211 end-user respondents comprising administrators, head guards, and security personnel of Kaizen Security Agency Corp., across the criteria of Functional Suitability, Performance Efficiency, Compatibility, Reliability, Usability, and Maintainability, obtaining an overall weighted mean of *[insert here — overall weighted mean]*, interpreted as *[insert here — interpretation]*. The study concludes that making the station configuration itself the input to generation reduces the administrator's work from constructing a roster to reviewing one, and that separating rule-based screening from AI-assisted ranking replaces an unbounded sequence of telephone calls with a single confirmation, without making station coverage depend on the availability of a third-party service.

**Keywords:** duty scheduling, workforce management, security agency, absence handling, artificial intelligence, Google Gemini, Flutter, FastAPI, Supabase, ISO/IEC 25010

---

# DEDICATION

This humble work is wholeheartedly dedicated —

**First and foremost, to our Almighty God**, the source of all wisdom, strength, and understanding. For the guidance He gave us in every decision, the perseverance He granted us in every difficulty, and the grace that carried this study from its first page to its last, we offer this work back to Him.

**To our beloved parents and families**, who gave us far more than support. For the sacrifices made quietly on our behalf, for the encouragement offered on the days when this study felt heavier than we could carry, and for the unconditional love and patience that never once ran short, this work is as much theirs as it is ours.

**To our school, [insert here — name of the school/university]**, and to our professors in **Capstone Project 1 and Capstone Project 2**, who gave us not only the knowledge and discipline required to undertake a study of this scope, but also the standards by which we learned to measure our own work. The formation we received within its halls made this study possible.

**To our adviser, [insert here — name of adviser]**, whose guidance, corrections, and generous sharing of expertise shaped this study at every stage. For the time given to reading our drafts, for the questions that made us think more carefully, and for the confidence shown in us when our own wavered, we dedicate this work.

*— The Researchers*

---

# ACKNOWLEDGEMENT

The completion of this study would not have been possible without the guidance, assistance, and encouragement of the individuals and the institution to whom the researchers wish to express their sincerest gratitude.

**Above all, to our Almighty God**, for the wisdom, strength, good health, and perseverance He bestowed upon the researchers throughout the conduct of this study. Every insight gained and every obstacle overcome in the course of this work is owed first to Him.

**To Mr. Eduardo S. Rodrigo**, our professor in **Capstone Project 1**, for laying the foundation of this study. His guidance in shaping the research problem, in refining the objectives, and in setting the direction of the project gave the researchers the clarity and the discipline with which this work began.

**To Mrs. Ann Camile M. Maupay**, our professor in **Capstone Project 2**, for her patient supervision through the development, testing, and documentation of the system. Her corrections, her suggestions, and her insistence on quality brought this study to its completion.

**To Kaizen Security Agency Corp.**, our chosen company, for granting the researchers the opportunity to study its scheduling operations and for entrusting us with the information necessary to develop a system suited to its actual needs. This study could not have been grounded in real practice without the agency's openness and cooperation.

**To Mrs. Necifora O. Cahulugan**, for her invaluable assistance in facilitating the researchers' interview with the agency's administration. Her willingness to help open that door made the data gathering of this study possible.

**To Mr. Sammy P. Dulay**, the administrator of Kaizen Security Agency Corp., for generously giving his time to be interviewed, for sharing with the researchers the realities of the agency's manual scheduling process, and for testing the developed system and providing the feedback that guided its improvement. His participation shaped this study from its requirements to its final evaluation.

**To the administrators, head guards, and security personnel of Kaizen Security Agency Corp.**, and to the **IT experts** who took part in the evaluation of the system, for their time and for the honest assessments that gave this study its findings.

**Finally, we extend our heartfelt appreciation to our families and friends** for their unwavering support, encouragement, and understanding throughout the conduct of this study. Their belief in the researchers sustained this work through every stage of its development.

*— The Researchers*
