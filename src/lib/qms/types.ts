// QMS Management tab: TypeScript types matching supabase/migrations (qms_ tables and views).
// If the project generates types with `supabase gen types typescript`, prefer those and keep
// this file only for the friendly names.

export type QmsRole =
  | "qms_admin" | "ceo" | "hod" | "board_treasurer" | "head_ops_systems"
  | "programme_owner" | "mentor" | "staff";

export type DocType = "MAN" | "POL" | "MAP" | "SOP" | "GUI" | "FRM" | "TMP" | "REG" | "MAT" | "REC";
export type DocStatus = "Draft" | "Submitted" | "In review" | "Returned" | "Approved" | "Obsolete";
export type DocClass = 1 | 2 | 3;
export type Approver = "hod" | "ceo" | "board" | "board_treasurer" | "programme_owner";
export type ChangeType = "Minor" | "Major";

export interface QmsDocument {
  id: string;
  code: string | null;
  previous_code: string | null;
  title: string;
  doc_class: DocClass;
  doc_type: DocType;
  domain: string | null;
  department: string | null;
  process: string | null;
  programme: string | null;
  is_governance: boolean;
  is_cross_department: boolean;
  owner_role: string;
  owner_user: string | null;
  current_version_id: string | null;
  published_version_id: string | null;
  status: DocStatus;
  approved_date: string | null;
  next_review_date: string | null;
  visible_to: string[];
  record_type: string | null;
  retention_until: string | null;
  is_external: boolean;
  licence_note: string | null;
}

export interface QmsVersion {
  id: string;
  document_id: string;
  draft_seq: number;
  major: number | null;
  minor: number | null;
  version_no: string;
  status: DocStatus;
  source_path: string | null;
  pdf_path: string | null;
  published_pdf_path: string | null;
  change_summary: string | null;
  change_type: ChangeType | null;
  is_significant: boolean;
  author_id: string | null;
  submitted_by: string | null;
  submitted_at: string | null;
  approved_by: string | null;
  approved_at: string | null;
  board_resolution_no: string | null;
  board_resolution_date: string | null;
}

export interface MyApproval {
  step_id: string;
  version_id: string;
  document_id: string;
  code: string | null;
  title: string;
  doc_type: DocType;
  department: string | null;
  version_no: string;
  submitted_at: string;
  required_role: Approver;
  required_department: string | null;
  working_days_waiting: number;
}

export interface LibraryItem {
  id: string;
  code: string | null;
  title: string;
  doc_class: DocClass;
  doc_type: DocType;
  department: string | null;
  process: string | null;
  programme: string | null;
  version_no: string;
  approved_date: string | null;
  next_review_date: string | null;
  controlled: boolean;
}

// Plain-word badge labels and colours for statuses (briefing section 6)
export const STATUS_BADGE: Record<DocStatus, { label: string; tone: "grey" | "blue" | "amber" | "red" | "green" }> = {
  Draft: { label: "Draft", tone: "grey" },
  Submitted: { label: "Waiting for check", tone: "blue" },
  "In review": { label: "Waiting for approval", tone: "amber" },
  Returned: { label: "Returned", tone: "red" },
  Approved: { label: "Approved", tone: "green" },
  Obsolete: { label: "Obsolete", tone: "grey" },
};
