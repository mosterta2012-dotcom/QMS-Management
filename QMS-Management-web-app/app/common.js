// Labels, formats and small rules shared by the screens and both back ends.

export const DOC_TYPES = {
  MAN: "Manual", POL: "Policy", MAP: "Process map", SOP: "Procedure", GUI: "Guide", FRM: "Form",
  TMP: "Template", REG: "Register", MAT: "Programme material", REC: "Record",
};
export const CLASS_LABEL = { 1: "1 Controlled", 2: "2 Programme material", 3: "3 Record" };

// Plain-word status badges (briefing section 6, same as src/lib/qms/types.ts STATUS_BADGE)
export const STATUS_BADGE = {
  Draft: { label: "Draft", tone: "grey" },
  Submitted: { label: "Waiting for check", tone: "blue" },
  "In review": { label: "Waiting for approval", tone: "amber" },
  Returned: { label: "Returned", tone: "red" },
  Approved: { label: "Approved", tone: "green" },
  Obsolete: { label: "Obsolete", tone: "grey" },
};

export const ROLE_LABEL = {
  qms_admin: "QMS Administrator", ceo: "CEO", hod: "HOD", board_treasurer: "Board Treasurer",
  head_ops_systems: "Head of Operations and Systems", programme_owner: "Programme owner",
  mentor: "Mentor", staff: "Staff",
};
export const QMS_GROUP_ROLES = ["qms_admin", "ceo", "hod", "board_treasurer", "head_ops_systems"];

export function approverLabel(role, dept) {
  switch (role) {
    case "hod": return `HOD ${dept ?? ""}`.trim();
    case "ceo": return "CEO";
    case "board": return "Board (CEO uploads the signed resolution)";
    case "board_treasurer": return "Board Treasurer";
    case "programme_owner": return "Programme owner";
    default: return role ?? "";
  }
}

export function visibleLabel(v, depts = []) {
  if (v === "all_staff") return "All staff";
  if (v === "hods") return "HODs";
  if (v === "mentors") return "Mentors";
  if (v === "qms_group") return "QMS group only";
  if (v.startsWith("dept:")) {
    const c = v.slice(5); const d = depts.find((x) => x.code === c);
    return `${d ? d.name : c} staff`;
  }
  if (v.startsWith("mentors:")) return `Mentors: ${v.slice(8)}`;
  return v;
}

export const CODE_RE = /^QMS-(MAN|POL|MAP|SOP|GUI|FRM|TMP|REG)-[A-Z]{2,4}-[0-9]{3}$/;
export const TITLE_MARKS_RE = /(\brev ?\d|\bv\d+(\.\d+)?\b|\(\d+\)|- ?copy\b|\bfinal\s*(draft|version)?\s*$)/i;

const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
/** 24 Nov 2026 */
export function fmtDate(v) {
  if (!v) return "";
  const d = typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v) ? new Date(v + "T00:00:00") : new Date(v);
  if (isNaN(d)) return String(v);
  return `${String(d.getDate()).padStart(2, "0")} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}
export function fmtDateTime(v) {
  if (!v) return "";
  const d = new Date(v);
  return `${fmtDate(d)} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}
export function isoDate(d = new Date()) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
