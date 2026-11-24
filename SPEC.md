# QMS Management tab: rules on one page

Full specification: QMS Management Tab — Development Briefing (https://claude.ai/artifact/Hs7DkErsJeSzo4zPWcxru1). This page lists what the database in this pack enforces, so screen work can rely on it.

## Three classes of document

| Class | What | Approved in | Seen in Document Control |
|---|---|---|---|
| 1 Controlled | Manual, policies, process maps, procedures, guides, forms, templates, registers | QMS Management | Approved version only, Controlled badge |
| 2 Programme materials | Mentor templates, Hive Mind guides, workbooks | Programme owner | Roles and programme set on the record |
| 3 Records | Client reports, minutes, contracts, signed forms | Not approved; filed once | Roles set on the record; never edited |

## Status flow (class 1)

Draft → Submitted (owner) → In review (QMS Administrator check, within 5 working days) → Approved (approver) or Returned (comment required). Approving a new version makes the previous one Obsolete. Withdrawal (QMS Administrator, reason required) makes the document Obsolete.

Drafts show as 0.1, 0.2 … Approval sets 1.0, then 1.1 (Minor) or 2.0 (Major).

## Approval matrix (QMS-SOP-GOV-001), as coded in `qms_route()`

| Document | Approver |
|---|---|
| QMS Manual; governance policies (`is_governance`) | Board, by resolution the CEO uploads |
| Other policies, process maps, cross-department procedures (`is_cross_department`) | CEO |
| Procedures within one department; guides, forms, templates, registers | HOD of the owning department |
| HR documents | HOD HR (CEO for HR policies) |
| Any document the CEO wrote | Board Treasurer |
| The approving HOD wrote or submitted it | CEO |

## Rules (briefing section 9)

| No. | Rule | Where enforced |
|---|---|---|
| R-01 | Class 1 code QMS-TYPE-DOMAIN-###, unique, never reused | `qms_submit`, unique index |
| R-02 | No version or copy marks in titles | check constraint |
| R-03 | 0.x drafts; whole number or x.1 on approval | `qms_approve` |
| R-04 | No self-approval; moves up a level | `qms_route`, `qms_can_decide`, check constraint |
| R-05 | Approver from the matrix only | `qms_route` |
| R-06 | Return needs a comment | `qms_return`, check constraint |
| R-07 | Board resolution required for Board-level documents | `qms_approve` |
| R-08 | One live version; previous made Obsolete together | `qms_approve` |
| R-09 | Drafts never visible outside the QMS group | RLS on `qms_version`, `qms_document`, storage |
| R-10 | Approved versions cannot be edited | `qms_version_lock` trigger, column grants |
| R-11 | Review date on approval (12 months); extension needs a reason | `qms_approve`, `qms_extend_review` |
| R-12 | Retention from class and record type, never upload date | `qms_withdraw`, `qms_record_type` |
| R-13 | Significant change needs a change request | `qms_submit` |
| R-14 | Outside class 2 materials need a licence note before mentors see them | `qms_can_read_document` |
| R-15 | Mentors see only their programme's materials and documents for mentors | `qms_can_read_document` |
| R-16 | Audit log insert-only | triggers, grants |

## Who may open the tab

QMS Administrator, CEO, HODs (including HOD Reports), Board Treasurer, Head of Operations and Systems (`qms_is_qms_group()`). Everyone else reads published documents in Document Control through `qms_library`.
