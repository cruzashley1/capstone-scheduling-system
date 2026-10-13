# CHAPTER I
# THE PROBLEM AND ITS BACKGROUND

## 1.1 Project Context

*(Unchanged — kept exactly as written.)*

Workforce scheduling in security operations is a complex process that involves balancing shift requirements, personnel availability, and organizational policies. When not properly managed, it can result in missed shifts, excessive overtime, and employee dissatisfaction, which may negatively affect operations, reduce morale, and lead to financial losses (Hughes, 2024). Many organizations still rely on traditional methods such as spreadsheets, phone calls, and printed schedules; however, these approaches often lead to errors, miscommunication, delays, increased administrative workload, and difficulty in tracking real-time updates. These challenges emphasize the need for more efficient and automated systems to improve personnel scheduling and management. Additionally, unexpected absences due to illness, emergencies, or lack of commitment create sudden staffing gaps, requiring administrators to spend significant time manually adjusting schedules and finding replacements (Dhamrait, 2025).

Advancements in information technology have introduced new solutions to improve workforce scheduling. Artificial Intelligence (AI), in particular, has shown significant potential in optimizing scheduling processes by analyzing multiple variables such as employee availability, workload distribution, and operational requirements. AI-driven scheduling systems can automate complex scheduling tasks, reduce human error, and support better decision-making (Kupunarapu, 2022).

## 1.2 Background of the Study

Kaizen Security Agency Corp. currently deploys 464 security personnel across twenty-five (25) Light Rail Transit (LRT) stations, where duty schedules are managed manually using spreadsheet applications such as Microsoft Excel. Staffing requirements differ from one station to another and from one shift to another, with the morning and afternoon shifts requiring the largest number of personnel and the night shift requiring the fewest, and with a head guard supervising each station on a twelve-hour duty. Administrators manually prepare bi-weekly duty schedules, while security personnel access these files to view their assignments. This manual approach creates significant challenges in organizing personnel, monitoring workload distribution, and managing absences. When a security guard is absent, administrators must manually find and contact available replacement, often encountering delays when personnel decline due to personal reasons. In worst-case scenarios, on-duty personnel are required to extend their shifts until replacements arrive, leading to fatigue and reduced performance.

To address these operational inefficiencies, this study proposes the development of "**A Scheduling and Duty Management System with AI Application in Absence Handling**." The system automates the preparation of bi-weekly duty schedules, distributes duty assignments to personnel through a mobile application, and applies an AI-based feature that recommends the most suitable replacement from a list of personnel already screened for availability, schedule compatibility, shift eligibility, and workload distribution. This eliminates the time-consuming manual process of identifying and contacting potential replacements while ensuring optimal workforce distribution.

## 1.3 Statement of the Problem

*(Unchanged — these questions describe the existing manual process.)*

This study aims to develop A Scheduling and Duty Management System with AI Application in Absence Handling. The system is designed to automate scheduling processes, provide accessible duty information, and utilize artificial intelligence (AI) to recommend suitable replacement. Through these features, the system seeks to improve scheduling efficiency, reduce administrative workload, minimize delays in shift coverage, and enhance overall personnel management.

Specifically, it seeks to answer the following questions:

1. What challenges do administrators encounter in organizing and balancing the workload of security personnel when manually preparing bi-weekly duty schedules?
2. How does the current manual process of handling employee absences affect the efficiency of assigning reliever personnel?
3. What challenges arise in finding immediate replacement personnel, and how do these delays impact the working hours of on-duty security guards?
4. How does the current use of Excel-based scheduling affect the accessibility, timeliness, and convenience of viewing duty information for administrators and security personnel?

## 1.4 Objectives of the Study

**General Objective:**

The primary objective of this study is to develop A Scheduling and Duty Management System with AI Application in Absence Handling for Kaizen Security Agency Corp, which manages security personnel assigned to Light Rail Transit (LRT) stations. The proposed system aims to improve the efficiency of scheduling processes, provide convenient access to duty assignments, and assist administrators in handling employee absences through an AI-based recommendation feature.

**Specific Objectives:**

1. **Design** a scheduling system that organizes and balances the workload of security personnel through an automated schedule generation feature that follows each station's required number of personnel and assigned posts per shift, observes rest days, and distributes personnel across stations every rotation cycle.
2. **Develop** an AI-based absence handling feature that recommends suitable reliever personnel based on availability, current schedule or day-off status, shift and post eligibility, and workload distribution, by screening candidates through system-defined scheduling rules and ranking the qualified candidates with the assistance of artificial intelligence.
3. **Implement** and test the system to reduce delays in assigning replacement personnel and minimize extended working hours of on-duty security guards.
4. **Evaluate** the developed web and mobile-based Scheduling and Duty Management System in terms of accessibility, timeliness, and usability of schedule information for administrators and security personnel.

## 1.5 Scope and Delimitations of the Study

### Scope of the Study

This study focuses on the development of a Scheduling and Duty Management System with AI Application in Absence Handling intended for security personnel assigned to Light Rail Transit (LRT) stations under Kaizen Security Agency Corp. The proposed system is developed using **Flutter** for cross-platform accessibility, providing a desktop and web-based application for administrators and a mobile application for security personnel, while a **Python (FastAPI) web service** hosted on a cloud platform handles the scheduling logic and a **Supabase (PostgreSQL) database** is utilized for secure data storage and centralized data access. Artificial intelligence is integrated through the **Google Gemini API**, which assists in ranking replacement candidates during absence handling. The system aims to improve the process of managing duty schedules, monitoring personnel assignments, and assisting administrators in handling employee absences efficiently.

- **User authentication features**: allow authorized users to log in and log out securely using credentials stored in encrypted (hashed) form, which cannot be retrieved and can only be reset by an administrator. It implements role-based access control with three roles — administrators, who manage schedules and system data; head guards, who monitor and report the attendance of personnel in their station; and security personnel, who view their assigned schedules and duty information.

- **Station and post configuration**: allows administrators to register stations and define, per shift, the required number of personnel and the named post assigned to each slot, together with the duty hours of each post. This configuration determines how many personnel the system deploys to a station and serves as the basis of schedule generation.

- **Automated schedule generation**: the system generates bi-weekly (15-day) duty schedules based on the configured station requirements, assigning regular personnel to their fixed station and shift with scheduled rest days, assigning relievers to cover those rest days, and reassigning personnel to different stations every rotation cycle while considering their preferred stations. Personnel may only be deployed to stations within their own group or an immediately adjacent group. When the available personnel are not enough to fill a requirement, the system does not stop the process; instead, it produces the best possible schedule and records the staffing problem as a note for the administrator to review.

- **Scheduling management**: the system enables administrators to create, edit, delete, publish, and manage bi-weekly duty schedules of security personnel assigned to various stations. Security personnel are able to view their assigned shifts and schedule details through the system only after a schedule has been published.

- **Schedule viewing interface**: displays generated and published schedules by station, period, and shift, showing each personnel's date, duty hours, and assigned post, with color-coded indicators for duty status such as rest days, absences, and covered duties, to make schedule monitoring easier for administrators.

- **Search and filter functions**: that allow administrators to search for security personnel by name and filter schedules and records by station, date, shift, and scheduling period. This feature supports efficient schedule management and quick access to relevant information.

- **Reporting and archiving functions**: allow administrators to generate duty schedule reports per station and per period and leave reports for the year, view historical and past schedules, and export or print reports in **PDF format** on the agency's letterhead with configurable signatories for documentation purposes.

- **Mobile application for security personnel**: through the mobile application, security personnel can view their assigned bi-weekly schedules, shift details such as date, duty hours, station and assigned post, and access their past schedules. Personnel may also file emergency absence requests before their duty begins, file leave requests, request specific day-offs for periods that are not yet scheduled, and indicate their availability to cover duties on their rest days.

- **Report Absence of Security Personnel**: through the mobile application, the head guard can view the assigned bi-weekly schedule, past schedules, shift details such as date, time and station, view the daily roster of their station, and submit an attendance report per shift identifying the personnel who are present and absent. The day head guard files the morning and afternoon shifts while the night head guard files the night shift, and each shift may only be submitted once.

- **Dashboard interface**: provides an overview of important scheduling information. The dashboard displays the total number of security personnel, schedule summaries, and daily absence, on-duty, and availability statistics to assist administrators in monitoring operations.

- **Absence handling module**: Artificial Intelligence (AI) is integrated into the system to assist administrators in identifying suitable replacements for absent security personnel. The system first applies its scheduling rules to remove candidates who are unavailable, already scheduled on that date, also reported absent, or not qualified for the shift or post, then scores the remaining candidates according to station familiarity, personnel type, workload, and declared availability. The AI reviews this screened list and recommends the most suitable replacement with an explanation, and the ranked candidates are presented to the administrator, who makes the final decision. Duties assigned on short notice are automatically adjusted to give the assigned personnel reasonable travel and preparation time, and replacements can no longer be assigned once the duty has already ended.

- **Leave management module**: allows security personnel to file leave requests and administrators to record and approve them, with the system enforcing the allowed duration per leave type, the required filing lead time, the yearly limit, and the waiting period between leaves. Approved leaves automatically exclude the personnel from schedule generation for the covered dates.

- **In-app notification module**: informs security personnel and head guards of schedule updates, decisions on their requests, and duty assignments given to them as replacements, and informs administrators of newly submitted reports and requests.

### Delimitations

This study is limited in terms of system features and implementation. The proposed system does not include SMS or email notification functionality due to the need for third-party API integration, which involves additional system configuration, security considerations, and possible subscription or usage-based costs that are beyond the resources and scope of the study. Moreover, implementing such features would increase the complexity of the system by requiring more advanced backend services for real-time message handling. Instead, the system utilizes in-app notifications within the mobile application to inform users of schedule updates. The focus of the study is to develop an efficient scheduling and absence handling system rather than a full-scale communication platform.

The system also does not include biometric, location-based, or automated time-in and time-out recording. Attendance is established through the attendance report submitted by the head guard of each station, and the system does not compute payroll, salaries, or overtime pay. The artificial intelligence component is advisory in nature; it recommends and ranks replacement candidates, but the final assignment is always confirmed by the administrator, and the system remains fully functional using its rule-based ranking when the AI service is unavailable. The mobile application is deployed for Android devices, while the administrative application is deployed for Windows desktop and web browsers. Finally, the study covers only the security personnel of Kaizen Security Agency Corp. assigned to Light Rail Transit (LRT) stations.

## 1.6 Significance of the Study

**Administrators.** The system will provide administrators with a centralized platform for managing duty schedules and assigning security guards to different stations. It will also assist them in handling employee absences by generating AI-based recommendations for suitable replacement personnel, reducing the time and effort required for manual schedule adjustments.

**Future Researchers.** This study may serve as a reference for future researchers who plan to develop similar systems related to personnel scheduling, duty management, or AI-assisted decision support in other organizations or industries.

**Kaizen Security Agency Corporation.** The proposed system will help improve the efficiency and organization of managing security personnel schedules across various LRT stations. By automating the scheduling process and integrating an AI-assisted absence handling feature, the organization can minimize scheduling conflicts, ensure continuous station security, and enhance operational efficiency.

**Researchers.** The researchers will gain valuable knowledge and experience in developing a real-world information system that integrates scheduling management and artificial intelligence concepts. The study will also enhance their technical skills in system development using modern technologies such as Flutter, FastAPI, Supabase, and AI integration.

**Security Personnel.** Security guards will benefit from easier access to their duty schedules and assigned station locations through the system. This will allow them to conveniently check their weekly assignments, reducing confusion and improving communication regarding duty responsibilities. Additionally, the system enables faster identification of replacement personnel in cases of absence, helping to prevent unnecessary extension of working hours and reducing fatigue among security staff.

## 1.7 Operational Definition of Terms

**Absence Handling** refers to a system feature that records when a scheduled security personnel member is unavailable for duty and suggests suitable relievers based on availability, schedule, shift and post eligibility, and workload, for the administrator's approval.

**Administrator (Manager)** refers to authorized personnel responsible for managing the scheduling system, creating and updating the duty schedules, assigning security guards to stations, and handling absence reports within the system.

**Artificial Intelligence** refers to the language model service integrated into the system that reviews the list of qualified replacement candidates prepared by the system and recommends the most suitable replacement security guard, together with the reason for the recommendation, when an absence occurs.

**Bi-weekly Schedule** refers to the work schedule generated by the system that covers a 15-day assignment of security personnel per station, covering the 1st to the 15th and the 16th to the last day of the month.

**Cover Offer** refers to a declaration submitted by a security personnel indicating their willingness to be assigned duty on a rest day, which raises their ranking among replacement candidates.

**Duty** refers to the assignment, responsibility, or task given to a security personnel as displayed and managed within the scheduling system.

**FastAPI** refers to the Python web framework used to build the backend service of the system, which contains the schedule generation logic and provides data to the web and mobile applications.

**Flutter** refers to the development framework used to build the cross-platform mobile, desktop, and web applications of the proposed system.

**Head Guard** refers to the security personnel assigned to supervise a station on a twelve-hour duty and who submits the attendance report of the personnel deployed in that station.

**Leave** refers to an approved absence covering a range of dates during which the security personnel is excluded from schedule generation.

**Post** refers to the specific station area or responsibility assigned to a security personnel within a shift, such as platform, roving, or head guard, each with its own duty hours.

**Preparation Window** refers to the automatic adjustment of duty hours applied when a replacement is assigned on short notice, giving the assigned personnel time to travel and report for duty.

**Reliever** refers to a security personnel whose function is to cover the rest days of regular personnel and who may be suggested by the system to temporarily replace an absent guard based on availability and workload balance.

**Rotation Cycle** refers to the monthly redistribution of security personnel across stations, which considers their preferred stations while keeping a number of familiar personnel in each station.

**Scheduling System** refers to the developed web, desktop, and mobile application that automates the creation, management, and distribution of security personnel duty schedules.

**Security Personnel** is a security guard and user of the mobile application who is assigned to LRT stations and can view their schedules and receive updates regarding their duties.

**Station Group** refers to the division of the LRT stations into three groups along the line, which limits the deployment of security personnel to their own group or an immediately adjacent group.

**Supabase** refers to the cloud database service used in the system for storing employee records, stations, schedules, requests, and user credentials accessed by the web and mobile applications.
