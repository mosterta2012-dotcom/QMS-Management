-- =====================================================================
-- QMS Management tab: starting lists and settings
-- Run after the migrations (supabase db reset runs seed.sql automatically).
-- Values in [square brackets] in notes are still to be decided.
-- =====================================================================

insert into public.qms_department (code, name) values
  ('GOV', 'Governance'),
  ('QMS', 'QMS'),
  ('OPS', 'Operations'),
  ('TD', 'Training and Development'),
  ('SG', 'Sustainability and Growth'),
  ('ME', 'M&E (outsourced)'),
  ('REP', 'Reports'),
  ('FIN', 'Finance'),
  ('HR', 'Human Resources'),
  ('PR', 'Marketing and PR'),
  ('EXE', 'Executive');

-- Level 2 processes from QMS-MAP-GOV-001 Process Map Register
insert into public.qms_process (code, name, department) values
  ('GOV-01', 'Policy Development and Approval', 'GOV'),
  ('GOV-02', 'Risk Management', 'GOV'),
  ('GOV-03', 'Board Reporting', 'GOV'),
  ('GOV-04', 'Annual Planning and Budgeting', 'GOV'),
  ('GOV-05', 'Communication (proposed)', 'GOV'),
  ('QMS-01', 'Document Control', 'QMS'),
  ('QMS-02', 'Internal Audit', 'QMS'),
  ('QMS-03', 'Continuous Improvement', 'QMS'),
  ('QMS-04', 'Client Reporting Quality Review', 'QMS'),
  ('QMS-05', 'Asset Management', 'QMS'),
  ('OPS-01', 'Project Start-Up', 'OPS'),
  ('OPS-02', 'Project Tracking', 'OPS'),
  ('OPS-03', 'Project Closure', 'OPS'),
  ('T&D-01', 'Beneficiary Journey', 'TD'),
  ('T&D-02', 'Mentor Management', 'TD'),
  ('T&D-03', 'Training Delivery', 'TD'),
  ('SG-01', 'Opportunity Management', 'SG'),
  ('SG-02', 'Client Handover', 'SG'),
  ('SG-03', 'Marketing', 'SG'),
  ('M&E-01', 'Framework Development', 'ME'),
  ('M&E-02', 'Quarterly Monitoring', 'ME'),
  ('M&E-03', 'Reporting: mentor quarterly programme reports', 'REP'),
  ('FIN-01', 'Payment Request (PR)', 'FIN'),
  ('FIN-02', 'Asset Payment Request (APR)', 'FIN'),
  ('FIN-03', 'Operational Payment Request (OPR)', 'FIN'),
  ('FIN-04', 'Internship Payment Request (IPR)', 'FIN'),
  ('FIN-05', 'Bursary Payment Request (BPR)', 'FIN'),
  ('FIN-06', 'Donations and Section 18A Receipts (proposed)', 'FIN'),
  ('FIN-07', 'Procurement', 'FIN'),
  ('FIN-08', 'Internship Travel (ITV)', 'FIN'),
  ('FIN-09', 'Bursary Travel (BTV)', 'FIN'),
  ('FIN-10', 'Internal Travel (TVT)', 'FIN'),
  ('FIN-11', 'Payroll', 'FIN'),
  ('FIN-12', 'Tax Compliance (VAT and PBO) (proposed)', 'FIN'),
  ('HR-01', 'Recruitment', 'HR'),
  ('HR-02', 'Onboarding', 'HR'),
  ('HR-03', 'Performance Management', 'HR'),
  ('HR-04', 'Remote Work', 'HR'),
  ('HR-05', 'Offboarding', 'HR');

-- Retention schedule from QMS-POL-INF-003 (100 = permanent; HR records follow HR-01-SCH-01)
insert into public.qms_record_type (code, name, retention_years, retention_trigger) values
  ('GOV-PERM', 'Constitution, certificates, SARS letters, Board minutes and resolutions', 100, 'permanent'),
  ('FIN-AFS', 'Annual financial statements, audit and NPO annual reports', 100, 'permanent'),
  ('FIN-ACC', 'Accounting records (ledgers, invoices, payment requests, bank statements, quotations, proofs of payment)', 7, 'end of financial year'),
  ('FIN-VAT', 'VAT records and returns', 7, 'date return submitted'),
  ('FIN-DON', 'Donation records and section 18A receipts', 7, 'end of tax year'),
  ('FIN-PAY', 'Payroll, PAYE, UIF and COIDA records', 7, 'end of tax year'),
  ('COM-CON', 'Client contracts and service agreements', 7, 'end of contract (contract term + 7 years)'),
  ('FIN-SUP', 'Supplier records and due diligence files', 7, 'last transaction'),
  ('OPS-BEN', 'Beneficiary application and programme records', 5, 'programme closure'),
  ('OPS-REP', 'Client reports and evidence packs', 7, 'end of contract (contract term + 7 years)'),
  ('OPS-SAT', 'Satisfaction survey raw responses', 2, 'end of cohort'),
  ('OPS-LRN', 'Accredited training and learner records (Angels copies)', 5, 'completion'),
  ('GOV-CMP', 'Complaints and feedback', 3, 'complaint closed'),
  ('GOV-FRD', 'Fraud, whistleblowing and investigation files', 5, 'matter closed'),
  ('INF-PAIA', 'PAIA requests and POPIA data subject requests', 5, 'request closed'),
  ('INF-BRE', 'Personal information breach records', 5, 'incident closed'),
  ('PR-CONS', 'Consent and marketing opt-out records', 1, 'consent withdrawn or contact removed'),
  ('QMS-REC', 'QMS records: audits, management reviews, corrective actions', 5, 'record closed'),
  ('QMS-SUP', 'Superseded controlled documents', 5, 'superseded'),
  ('FIN-TRV', 'Travel requests, bookings and claims', 7, 'end of financial year'),
  ('FIN-AST', 'Asset register and disposal records', 7, 'asset disposal (life of asset + 7 years)'),
  ('SYS-LOG', 'System audit logs', 3, 'log date [to confirm]');

insert into public.qms_settings (key, value, note) values
  ('review_months',            '12',  'Default review period after approval'),
  ('check_working_days',       '5',   'QMS Administrator check turnaround'),
  ('approval_nudge_days',      '3',   '[D-05] reminder to approver, repeated'),
  ('approval_escalate_days',   '10',  '[D-05] escalate to CEO (or Board Treasurer)'),
  ('review_reminder_days',     '30',  'Review-due reminder'),
  ('ack_working_days',         '10',  'Policy acknowledgement window (Release 2)'),
  ('superseded_retention_years','5',  'QMS-POL-INF-003: superseded controlled documents'),
  ('notification_retention_years','2','[to confirm]');

-- South African public holidays (Public Holidays Act; Sunday holidays move to Monday)
insert into public.qms_non_working_day (day, reason) values
  ('2026-12-16', 'Day of Reconciliation'),
  ('2026-12-25', 'Christmas Day'),
  ('2027-01-01', 'New Year''s Day'),
  ('2027-03-22', 'Human Rights Day (observed)'),
  ('2027-03-26', 'Good Friday'),
  ('2027-03-29', 'Family Day'),
  ('2027-04-27', 'Freedom Day'),
  ('2027-06-16', 'Youth Day'),
  ('2027-08-09', 'National Women''s Day'),
  ('2027-09-24', 'Heritage Day'),
  ('2027-12-16', 'Day of Reconciliation'),
  ('2027-12-27', 'Goodwill Day (observed)');

-- December office closure: add each closure day once the dates are set, e.g.
-- insert into public.qms_non_working_day (day, reason)
-- select d::date, 'December closure' from generate_series('[2026-12-14]'::date, '[2027-01-04]'::date, '1 day') d
-- on conflict (day) do nothing;

-- Roles: link each person's Supabase auth user to their QMS role(s). Use roles, not names.
-- insert into public.qms_user_role (user_id, role, department) values
--   ('<auth user id>', 'qms_admin',        'OPS'),
--   ('<auth user id>', 'ceo',              'EXE'),
--   ('<auth user id>', 'head_ops_systems', 'OPS'),
--   ('<auth user id>', 'hod',              'FIN'),   -- one row per HOD and department
--   ('<auth user id>', 'hod',              'REP'),   -- HOD Reports
--   ('<auth user id>', 'board_treasurer',  null);
-- Every staff member also gets ('<id>', 'staff', '<department>'); mentors get ('<id>', 'mentor', null, '<programme>').
-- Master Document Register starting list: the documents drafted in Batches 1 to 5.
-- All load as class 1 Drafts (none is approved yet). The QMS Administrator sets the
-- process code and uploads each Word file before submitting it. QMS-05 asset documents
-- keep their working codes in previous_code until recoded (decision D-11).
insert into public.qms_document (code, previous_code, title, doc_class, doc_type, domain, department, is_governance, owner_role, visible_to) values
  (null, 'QMS-05', 'Asset Management Procedure', 1, 'SOP', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05 Asset Management Procedure.docx (Draft)
  (null, 'QMS-05-FRM-01', 'Asset Purchase Request', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-01 Asset Purchase Request.docx (Draft)
  (null, 'QMS-05-FRM-02', 'Equipment Issue and Acknowledgement', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-02 Equipment Issue and Acknowledgement.docx (Draft)
  (null, 'QMS-05-FRM-03', 'Asset Return and Internal Transfer', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-03 Asset Return and Internal Transfer.docx (Draft)
  (null, 'QMS-05-FRM-04', 'Loss, Theft and Damage Report', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-04 Loss, Theft and Damage Report.docx (Draft)
  (null, 'QMS-05-FRM-05', 'Donation Received Record', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-05 Donation Received Record.docx (Draft)
  (null, 'QMS-05-FRM-06', 'Asset Donation or Transfer Certificate', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-06 Asset Donation or Transfer Certificate.docx (Draft)
  (null, 'QMS-05-FRM-07', 'Store Booking, Check-out and Return', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-07 Store Booking, Check-out and Return.docx (Draft)
  (null, 'QMS-05-FRM-08', 'Device Preparation and Pre-handover Check', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-08 Device Preparation and Pre-handover Check.docx (Draft)
  (null, 'QMS-05-GUI-01', 'Staff Guide', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-GUI-01 Staff Guide.docx (Draft)
  (null, 'QMS-05-GUI-02', 'Factotum Guide', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-GUI-02 Factotum Guide.docx (Draft)
  (null, 'QMS-05-GUI-03', 'Asset Coordinator Guide', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-GUI-03 Asset Coordinator Guide.docx (Draft)
  (null, 'QMS-05-GUI-04', 'Management Guide', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-GUI-04 Management Guide.docx (Draft)
  (null, 'QMS-05-GUI-05', 'Department Asset Contact Guide', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-GUI-05 Department Asset Contact Guide.docx (Draft)
  (null, 'QMS-05-WF-01', 'Asset Management Workflows', 1, 'MAP', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-WF-01 Asset Management Workflows.docx (Draft)
  ('QMS-GUI-GOV-001', null, 'Staff Guide Document Control and QMS Management', 1, 'GUI', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-GUI-GOV-001_Staff_Guide_Document_Control_and_QMS_Management_Draft_0.2.docx (Draft 0.2)
  ('QMS-GUI-OPS-001', null, 'Staff Guide Travel Hub', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-GUI-OPS-001_Staff_Guide_Travel_Hub_Draft_0.1.docx (Draft 0.1)
  ('QMS-MAN-GOV-001', null, 'Quality Management System Manual', 1, 'MAN', 'GOV', 'GOV', true, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-MAN-GOV-001_Quality_Management_System_Manual_v2.0_DRAFT.docx (v2.0 DRAFT)
  ('QMS-MAP-GOV-001', null, 'Process Map Register', 1, 'MAP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-MAP-GOV-001_Process_Map_Register_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-POL-FIN-002', null, 'Travel and Subsistence Policy', 1, 'POL', 'FIN', 'FIN', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-POL-FIN-002_Travel_and_Subsistence_Policy_v2.0_DRAFT.docx (v2.0 DRAFT)
  ('QMS-POL-FIN-003', null, 'Asset Management Policy', 1, 'POL', 'FIN', 'FIN', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-POL-FIN-003_Asset_Management_Policy_Draft_0.3.docx (Draft 0.3)
  ('QMS-POL-GOV-007', null, 'Code of Ethics and Conduct', 1, 'POL', 'GOV', 'GOV', true, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-POL-GOV-007_Code_of_Ethics_and_Conduct_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-POL-GOV-008', null, 'Anti-Fraud Bribery and Corruption Policy', 1, 'POL', 'GOV', 'GOV', true, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-POL-GOV-008_Anti-Fraud_Bribery_and_Corruption_Policy_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-POL-INF-003', null, 'Records Retention and Destruction Policy', 1, 'POL', 'INF', 'QMS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-POL-INF-003_Records_Retention_and_Destruction_Policy_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-REG-COM-001', null, 'Compliance Obligations Register', 1, 'REG', 'COM', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-COM-001_Compliance_Obligations_Register_v1.1_DRAFT.xlsx (v1.1 DRAFT)
  ('QMS-REG-GOV-008', null, 'Context and Interested Parties Register', 1, 'REG', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-GOV-008_Context_and_Interested_Parties_Register_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-REG-GOV-009', null, 'Quality Objectives and KPI Plan', 1, 'REG', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-GOV-009_Quality_Objectives_and_KPI_Plan_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-REG-GOV-010', null, 'Internal Audit Programme and Stage 1 Readiness', 1, 'REG', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-GOV-010_Internal_Audit_Programme_and_Stage_1_Readiness_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-REG-GOV-011', null, 'Risk Incident and Corrective Action Register', 1, 'REG', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-GOV-011_Risk_Incident_and_Corrective_Action_Register_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-REG-INF-003', null, 'Systems and Operator Inventory', 1, 'REG', 'INF', 'QMS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-INF-003_Systems_and_Operator_Inventory_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-SOP-COM-008', null, 'NPO Act Statutory Compliance Procedure', 1, 'SOP', 'COM', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-COM-008_NPO_Act_Statutory_Compliance_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-COM-009', null, 'Terrorist-Financing Risk and Partner Due Diligence Procedure', 1, 'SOP', 'COM', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-COM-009_Terrorist-Financing_Risk_and_Partner_Due_Diligence_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-FIN-006', null, 'Donations and Section 18A Receipts Procedure', 1, 'SOP', 'FIN', 'FIN', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-FIN-006_Donations_and_Section_18A_Receipts_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-FIN-007', null, 'VAT Compliance Procedure', 1, 'SOP', 'FIN', 'FIN', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-FIN-007_VAT_Compliance_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-FIN-008', null, 'Payroll Administration and Statutory Compliance Procedure', 1, 'SOP', 'FIN', 'FIN', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-FIN-008_Payroll_Administration_and_Statutory_Compliance_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-001', null, 'Document Control Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-001_Document_Control_Procedure_v2.0_DRAFT.docx (v2.0 DRAFT)
  ('QMS-SOP-GOV-006', null, 'Complaints and Feedback Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-006_Complaints_and_Feedback_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-007', null, 'Client Report Quality Review Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-007_Client_Report_Quality_Review_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-008', null, 'Programme Design and Development Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-008_Programme_Design_and_Development_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-009', null, 'Communication Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-009_Communication_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-010', null, 'Change Management Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-010_Change_Management_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-011', null, 'Client and Beneficiary Satisfaction Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-011_Client_and_Beneficiary_Satisfaction_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-012', null, 'Knowledge Management Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-012_Knowledge_Management_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-OPS-001', null, 'Client-Funded Programme Evidence Control Procedure', 1, 'SOP', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']);  -- QMS-SOP-OPS-001_Client-Funded_Programme_Evidence_Control_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)

-- First draft version for each seeded document (no file attached yet)
insert into public.qms_version (document_id, draft_seq, author_id)
select id, 1, null from public.qms_document where current_version_id is null;
update public.qms_document d set current_version_id = v.id
from public.qms_version v where v.document_id = d.id and d.current_version_id is null;
