# QMS Management tab: acceptance tests (briefing section 13)
# Run with real people in their roles (test accounts). Release 1 is accepted when T-01 to T-12 pass.
# Roles, not names. T-13 to T-20 are Release 2 and Phase 3.

Feature: QMS Management tab, Release 1

  Background:
    Given test users exist for QMS Administrator, CEO, Board Treasurer, HOD Finance, HOD Operations, a staff member and a mentor on Scatec E4C

  Scenario: T-01 HOD drafts and submits a departmental procedure
    Given the HOD Finance creates "QMS-SOP-FIN-0xx" with a Word file and its PDF
    When the HOD Finance presses Submit
    Then the status is "Waiting for check"
    And the QMS Administrator gets a notification
    And the staff member cannot see the draft in Document Control

  Scenario: T-02 QMS Administrator sends it for approval
    When the QMS Administrator presses Send for approval
    Then it is routed to the approver from the matrix
    And the status is "Waiting for approval"

  Scenario: T-03 The author cannot approve their own document
    Given the HOD Finance wrote the procedure
    Then the HOD Finance sees no Approve button and a message that the next level approves
    And the approval is routed to the CEO

  Scenario: T-04 Return needs a comment
    When the approver presses Return without a comment
    Then the return is blocked until a comment is entered
    And after a comment the owner is notified

  Scenario: T-05 CEO approves a 0.2 policy draft
    When the CEO approves it
    Then the version is 1.0
    And the review date is 12 months ahead
    And the PDF appears in Document Control with the Controlled badge
    And staff are notified

  Scenario: T-06 A minor update is approved
    Given version 1.0 is live
    When version 1.1 is approved as a Minor change
    Then 1.0 is Obsolete and only 1.1 is visible to staff

  Scenario: T-07 Governance policy needs the Board resolution
    Given a governance policy is waiting for the CEO
    When the CEO approves without a resolution file
    Then the approval is refused
    When the CEO uploads the signed resolution with number and date
    Then the policy is Approved and the resolution is linked

  Scenario: T-08 CEO is the author
    Given the CEO wrote a register
    When it is sent for approval
    Then it is routed to the Board Treasurer

  Scenario: T-09 Download is stamped
    When the staff member downloads a published procedure
    Then the PDF says "Uncontrolled copy when printed or downloaded" with today's date

  Scenario: T-10 Search
    When I search Document Control for "QMS-SOP-GOV-006" and for process "FIN-01"
    Then the correct documents are found in both tabs

  Scenario: T-11 No access for staff
    When the staff member opens the QMS Management address directly
    Then the page and the data are refused

  Scenario: T-12 Audit log
    When the QMS Administrator opens the Audit log after T-01 to T-11
    Then every action is listed with user, time and version
    And no row can be edited or deleted

Feature: QMS Management tab, Release 2 and Phase 3

  Scenario: T-13 Review date 30 days away
    Then the owner and QMS Administrator are notified and it appears in Reviews due

  Scenario: T-14 Extend a review without a reason
    Then it is blocked; with a reason the new date and reason are logged

  Scenario: T-15 Staff acknowledge a published policy
    Then the acknowledgement is recorded and shown in Acknowledgements

  Scenario: T-16 Acknowledgement not done in 10 working days
    Then the staff member is reminded, then their HOD

  Scenario: T-17 Significant change without a change request
    Then submission is blocked with a message

  Scenario: T-18 A client report is filed as a record
    Then its retention date comes from the schedule, not the upload date, and it cannot be edited

  Scenario: T-19 Mentor opens Document Control
    Then they see only class 2 materials for their programme and documents for mentors

  Scenario: T-20 Outside workbook without a licence note
    Then it cannot be made visible to mentors
