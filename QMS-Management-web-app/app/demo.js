// Demo back end: the same functions as live.js, with the same rules, but the data lives
// in this browser only (localStorage). Used when config.js has no Supabase settings.
import { SEED } from "./demo-seed.js";
import { CODE_RE, TITLE_MARKS_RE, isoDate } from "./common.js";

const KEY = "qms-demo-v1";
const USERS = [
  { id: "u-admin", email: "qms.admin@demo", label: "QMS Administrator",
    roles: [{ role: "qms_admin", department: "OPS" }, { role: "staff", department: "OPS" }] },
  { id: "u-ceo", email: "ceo@demo", label: "CEO", roles: [{ role: "ceo", department: "EXE" }] },
  { id: "u-headops", email: "head.ops@demo", label: "Head of Operations and Systems (HOD OPS)",
    roles: [{ role: "head_ops_systems", department: "OPS" }, { role: "hod", department: "OPS" }, { role: "staff", department: "OPS" }] },
  { id: "u-hodfin", email: "hod.finance@demo", label: "HOD Finance",
    roles: [{ role: "hod", department: "FIN" }, { role: "staff", department: "FIN" }] },
  { id: "u-hodhr", email: "hod.hr@demo", label: "HOD HR", roles: [{ role: "hod", department: "HR" }, { role: "staff", department: "HR" }] },
  { id: "u-hodrep", email: "hod.reports@demo", label: "HOD Reports", roles: [{ role: "hod", department: "REP" }] },
  { id: "u-treasurer", email: "board.treasurer@demo", label: "Board Treasurer", roles: [{ role: "board_treasurer" }] },
  { id: "u-staff", email: "staff@demo", label: "Staff member (Operations)", roles: [{ role: "staff", department: "OPS" }] },
  { id: "u-mentor", email: "mentor@demo", label: "Mentor (Scatec E4C)", roles: [{ role: "mentor", programme: "Scatec E4C" }] },
];

const uid = () => (crypto.randomUUID ? crypto.randomUUID() : "id-" + Math.random().toString(36).slice(2) + Date.now());
const now = () => new Date().toISOString();
const err = (m) => { throw new Error(m); };
const verNo = (v) => (v.major == null ? `0.${v.draft_seq}` : `${v.major}.${v.minor}`);
const addMonths = (m) => { const d = new Date(); d.setMonth(d.getMonth() + m); return isoDate(d); };
const addYears = (y) => { const d = new Date(); d.setFullYear(d.getFullYear() + y); return isoDate(d); };

function freshDb() {
  const db = { users: USERS.map((u) => ({ ...u, roles: u.roles.map((r, i) => ({ id: `${u.id}-${i}`, ...r })) })),
    documents: [], versions: [], steps: [], crs: [], audit: [], notifications: [], seq: {} };
  for (const s of SEED.documents) {
    const id = uid(), vid = uid();
    db.documents.push({ id, code: s.code, previous_code: s.previous_code, title: s.title, doc_class: 1, doc_type: s.doc_type,
      domain: s.domain, department: s.department, process: null, programme: null, is_governance: s.is_governance,
      is_cross_department: false, owner_role: s.owner_role, owner_user: null, current_version_id: vid,
      published_version_id: null, status: "Draft", approved_date: null, next_review_date: null, visible_to: ["all_staff"],
      record_type: null, retention_until: null, is_external: false, licence_note: null, withdrawn_reason: null, created_at: now() });
    db.versions.push(newVersion(vid, id, 1, null));
  }
  // One approved example so the Document Control library is not empty in the demo
  const exId = uid(), exV = uid();
  db.documents.push({ id: exId, code: "QMS-FRM-OPS-900", previous_code: null, title: "Demo Example Form", doc_class: 1,
    doc_type: "FRM", domain: "OPS", department: "OPS", process: "OPS-01", programme: null, is_governance: false,
    is_cross_department: false, owner_role: "HOD Operations", owner_user: "u-headops", current_version_id: exV,
    published_version_id: exV, status: "Approved", approved_date: isoDate(), next_review_date: addMonths(12),
    visible_to: ["all_staff"], record_type: null, retention_until: null, is_external: false, licence_note: null,
    withdrawn_reason: null, created_at: now() });
  db.versions.push({ ...newVersion(exV, exId, 1, "u-headops"), major: 1, minor: 0, status: "Approved",
    source_path: "demo/example.docx", pdf_path: "demo/example.pdf", published_pdf_path: "demo/example.pdf",
    change_type: "Major", submitted_by: "u-headops", submitted_at: now(), approved_by: "u-ceo", approved_at: now() });
  return db;
}
function newVersion(id, document_id, draft_seq, author_id, extra = {}) {
  return { id, document_id, draft_seq, major: null, minor: null, status: "Draft", source_path: null, pdf_path: null,
    published_pdf_path: null, change_summary: null, change_type: null, change_request_id: null, is_significant: false,
    author_id, submitted_by: null, submitted_at: null, approved_by: null, approved_at: null, board_resolution_path: null,
    board_resolution_no: null, board_resolution_date: null, created_at: now(), ...extra };
}

export function createDemoBackend() {
  let db;
  try { db = JSON.parse(localStorage.getItem(KEY)); } catch { db = null; }
  if (!db?.documents) db = freshDb();
  let current = (() => { try { return localStorage.getItem(KEY + "-user") || "u-admin"; } catch { return "u-admin"; } })();
  const blobs = {}; // uploaded files this session: path -> object URL
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(db)); } catch { /* storage full or blocked */ } };

  const me = () => db.users.find((u) => u.id === current);
  const userHas = (userId, role, dept) => !!db.users.find((u) => u.id === userId)?.roles
    .some((r) => r.role === role && (dept == null || r.department === dept));
  const has = (role, dept) => userHas(current, role, dept);
  const inGroup = () => ["qms_admin", "ceo", "hod", "board_treasurer", "head_ops_systems"].some((r) => has(r));
  const doc = (id) => db.documents.find((d) => d.id === id) ?? err("Document not found");
  const ver = (id) => db.versions.find((v) => v.id === id) ?? err("Version not found");
  const withNo = (v) => ({ ...v, version_no: verNo(v) });
  const audit = (action, table, rec, before, after, version_no = null) => {
    db.audit.unshift({ id: db.audit.length + 1, at: now(), user_id: current, action, table_name: table, record_id: rec,
      version_no, before: before ?? null, after: after ?? null });
  };
  const change = (table, obj, fn) => { const before = { ...obj }; fn(obj); audit("update", table, obj.id, before, { ...obj }, table === "qms_version" ? verNo(obj) : null); };
  const notify = (event, message, subject) => db.notifications.push({ id: db.notifications.length + 1, event, message, subject_id: subject, created_at: now() });

  function route(v) {
    const d = doc(v.document_id);
    if (d.doc_class === 2) return { approver: "programme_owner", department: null };
    let a, dep = null;
    if (d.is_governance || d.doc_type === "MAN") a = "board";
    else if (d.department === "HR" && d.doc_type === "POL") a = "ceo";
    else if (d.department === "HR") { a = "hod"; dep = "HR"; }
    else if (["POL", "MAP"].includes(d.doc_type) || d.is_cross_department) a = "ceo";
    else { a = "hod"; dep = d.department; }
    if (a !== "board" && userHas(v.author_id, "ceo")) return { approver: "board_treasurer", department: null };
    if (a === "hod" && (userHas(v.author_id, "hod", dep) || userHas(v.submitted_by, "hod", dep))) return { approver: "ceo", department: null };
    return { approver: a, department: dep };
  }
  function canDecide(s) {
    if (!s || s.kind !== "Approve" || s.decision !== "Pending") return false;
    const v = ver(s.version_id);
    if ([v.author_id, v.submitted_by].includes(current)) return false;
    return { hod: () => has("hod", s.required_department), ceo: () => has("ceo"), board: () => has("ceo"),
      board_treasurer: () => has("board_treasurer"), programme_owner: () => has("programme_owner") }[s.required_role]?.() ?? false;
  }
  function canRead(d) {
    if (inGroup()) return true;
    if (!d.published_version_id && d.doc_class !== 3) return false;
    const u = me();
    return d.visible_to.some((vt) => (vt === "all_staff" && has("staff"))
      || (vt.startsWith("dept:") && u.roles.some((r) => r.department === vt.slice(5)))
      || (vt === "mentors" && has("mentor") && d.doc_class !== 2)
      || (vt.startsWith("mentors:") && u.roles.some((r) => r.role === "mentor" && r.programme === vt.slice(8)))
      || (vt === "hods" && has("hod")));
  }
  const pendingStep = (vid, kind) => db.steps.filter((s) => s.version_id === vid && s.decision === "Pending" && (!kind || s.kind === kind)).at(-1);
  const act = (fn) => (...a) => { const r = fn(...a); save(); return Promise.resolve(r); };
  const needGroup = () => { if (!inGroup()) err("permission denied: only the QMS group may open QMS Management"); };

  return {
    mode: "demo",
    demoUsers: () => db.users.map((u) => ({ id: u.id, label: u.label, email: u.email })),
    demoCurrent: () => current,
    demoSwitch(id) { current = id; try { localStorage.setItem(KEY + "-user", id); } catch { /* ignore */ } },
    demoReset() { db = freshDb(); save(); },

    async session() { return { user: { id: current } }; },
    onAuthChange() {},
    async signIn() {}, async sendLink() {}, async setPassword() {}, async signOut() {},
    async me() { const u = me(); return { id: u.id, email: u.email, roles: u.roles }; },
    async lists() { return { departments: SEED.departments, processes: SEED.processes }; },

    async listDocuments() {
      needGroup();
      return db.documents.map((d) => { const v = db.versions.find((x) => x.id === d.current_version_id);
        return { ...d, current: v ? { id: v.id, version_no: verNo(v), status: v.status } : null }; })
        .sort((a, b) => { const k = (d) => (d.code ? "0" + d.code : "1" + d.title); return k(a) < k(b) ? -1 : k(a) > k(b) ? 1 : 0; });
    },
    async getDocument(id) {
      const d = doc(id); if (!canRead(d)) err("Document not found");
      const versions = db.versions.filter((v) => v.document_id === id).sort((a, b) => b.draft_seq - a.draft_seq).map(withNo);
      const steps = inGroup() ? db.steps.filter((s) => versions.some((v) => v.id === s.version_id)) : [];
      const emails = Object.fromEntries(db.users.map((u) => [u.id, u.email]));
      return { doc: { ...d }, versions, steps, emails };
    },
    async findItem(id) { return db.documents.find((d) => d.id === id)?.id ?? db.versions.find((v) => v.id === id)?.document_id ?? null; },

    createDocument: act((a) => {
      const c = Number(a.docClass);
      if (!(has("qms_admin") || has("ceo") || (c === 1 && has("hod", a.department)) || (c === 2 && has("programme_owner"))))
        err("Not allowed to create this document");
      if (TITLE_MARKS_RE.test(a.title)) err('new row for relation "qms_document" violates check constraint "qms_title_no_version_marks" (remove version or copy marks from the title)');
      if (a.code && db.documents.some((d) => d.code === a.code)) err(`duplicate key value violates unique constraint: code ${a.code} is already used`);
      const id = uid(), vid = uid();
      const d = { id, code: a.code || null, previous_code: null, title: a.title, doc_class: c, doc_type: a.docType, domain: a.domain || null,
        department: a.department, process: a.process || null, programme: a.programme || null, is_governance: !!a.isGovernance,
        is_cross_department: !!a.isCrossDepartment, owner_role: a.ownerRole, owner_user: current, current_version_id: vid,
        published_version_id: null, status: "Draft", approved_date: null, next_review_date: null,
        visible_to: a.visibleTo?.length ? a.visibleTo : ["all_staff"], record_type: null, retention_until: null,
        is_external: false, licence_note: null, withdrawn_reason: null, created_at: now() };
      db.documents.push(d); audit("insert", "qms_document", id, null, d);
      const v = newVersion(vid, id, 1, current); db.versions.push(v); audit("insert", "qms_version", vid, null, v, "0.1");
      return id;
    }),
    updateDocument: act((id, patch) => {
      if (!has("qms_admin")) err("permission denied: only the QMS Administrator edits document details");
      const d = doc(id);
      if (patch.title && TITLE_MARKS_RE.test(patch.title)) err("violates check constraint qms_title_no_version_marks (remove version or copy marks from the title)");
      if (patch.code && db.documents.some((x) => x.code === patch.code && x.id !== id)) err(`duplicate key value: code ${patch.code} is already used`);
      change("qms_document", d, (o) => Object.assign(o, patch));
    }),
    uploadDraftFiles: act((documentId, versionId, word, pdf) => {
      const v = ver(versionId);
      if (!["Draft", "Returned"].includes(v.status) || !(v.author_id === current || has("qms_admin")))
        err("Only the author or the QMS Administrator can add files to a draft or returned version");
      const base = `${documentId}/${versionId}/${Date.now()}`;
      change("qms_version", v, (o) => {
        if (word) { o.source_path = `${base}-source.${word.name.split(".").pop()}`; blobs[o.source_path] = URL.createObjectURL(word); }
        if (pdf) { o.pdf_path = `${base}-preview.pdf`; blobs[o.pdf_path] = URL.createObjectURL(pdf); }
      });
    }),
    async fileUrl(path) {
      if (blobs[path]) return blobs[path];
      err("Demo mode keeps uploaded files only until the page is reloaded. Upload the file again to view it.");
    },
    newDraft: act((documentId, summary, significant = false, crId = null) => {
      const d = doc(documentId);
      if (!(has("qms_admin") || has("ceo") || has("hod", d.department) || d.owner_user === current)) err("Not allowed");
      if (db.versions.some((v) => v.document_id === d.id && ["Draft", "Submitted", "In review"].includes(v.status)))
        err("This document already has a draft in progress");
      if (!summary?.trim()) err("A change summary is required");
      const seq = Math.max(0, ...db.versions.filter((v) => v.document_id === d.id).map((v) => v.draft_seq)) + 1;
      const v = newVersion(uid(), d.id, seq, current, { change_summary: summary, is_significant: significant, change_request_id: crId });
      db.versions.push(v); audit("insert", "qms_version", v.id, null, v, verNo(v));
      change("qms_document", d, (o) => { o.current_version_id = v.id; if (!o.published_version_id) o.status = "Draft"; });
      return v.id;
    }),
    logChangeRequest: act((title, significance) => {
      if (!inGroup()) err("Not allowed");
      const y = new Date().getFullYear(); db.seq[y] = (db.seq[y] ?? 0) + 1;
      const cr = { id: uid(), ref: `CR-${y}-${String(db.seq[y]).padStart(3, "0")}`, title, significance, status: "Logged", created_at: now() };
      db.crs.unshift(cr); audit("insert", "qms_change_request", cr.id, null, cr); return cr.id;
    }),
    async listChangeRequests() { return inGroup() ? db.crs : []; },
    async routeOf(versionId) { return route(ver(versionId)); },

    submit: act((versionId) => {
      const v = ver(versionId), d = doc(v.document_id);
      if (!(has("qms_admin") || has("hod", d.department) || d.owner_user === current || v.author_id === current)) err("Not allowed to submit");
      if (!["Draft", "Returned"].includes(v.status)) err(`Only a Draft or Returned version can be submitted (status is ${v.status})`);
      if (!v.source_path) err("Upload the Word file before submitting");
      if (d.doc_class === 1 && !CODE_RE.test(d.code ?? "")) err(`Class 1 documents need a code like QMS-SOP-GOV-001 before submission (code is ${d.code ?? "empty"})`);
      if (d.doc_class === 1 && !d.process) err("Class 1 documents need a process code");
      if (v.is_significant && !v.change_request_id) err("A significant change needs a linked change request (QMS-SOP-GOV-010)");
      if (v.draft_seq > 1 && !v.change_summary?.trim()) err("A change summary is required");
      change("qms_version", v, (o) => { o.status = "Submitted"; o.submitted_by = current; o.submitted_at = now(); });
      if (!d.published_version_id) change("qms_document", d, (o) => { o.status = "Submitted"; });
      const s = { id: uid(), version_id: v.id, kind: "Check", required_role: null, required_department: null, decision: "Pending",
        comment: null, decided_by: null, decided_at: null, created_at: now() };
      db.steps.push(s); audit("insert", "qms_approval_step", s.id, null, s);
      notify("submitted", `${d.code ?? d.title} v${verNo(v)} submitted for checking.`, v.id);
    }),
    sendForApproval: act((versionId) => {
      if (!has("qms_admin")) err("Only the QMS Administrator sends for approval");
      const v = ver(versionId), d = doc(v.document_id);
      if (v.status !== "Submitted") err(`Version is ${v.status}, not Submitted`);
      const chk = pendingStep(v.id, "Check");
      if (chk) change("qms_approval_step", chk, (o) => { o.decision = "Approved"; o.decided_by = current; o.decided_at = now(); });
      const r = route(v);
      const s = { id: uid(), version_id: v.id, kind: "Approve", required_role: r.approver, required_department: r.department,
        decision: "Pending", comment: null, decided_by: null, decided_at: null, created_at: now() };
      db.steps.push(s); audit("insert", "qms_approval_step", s.id, null, s);
      change("qms_version", v, (o) => { o.status = "In review"; });
      if (!d.published_version_id) change("qms_document", d, (o) => { o.status = "In review"; });
    }),
    returnDoc: act((versionId, comment) => {
      if (!comment?.trim()) err("A comment is required to return a document");
      const v = ver(versionId), d = doc(v.document_id);
      if (!["Submitted", "In review"].includes(v.status)) err(`Version is ${v.status}`);
      const s = pendingStep(v.id);
      if (!(has("qms_admin") || canDecide(s))) err("Not allowed to return this document");
      change("qms_approval_step", s, (o) => { o.decision = "Returned"; o.comment = comment; o.decided_by = current; o.decided_at = now(); });
      change("qms_version", v, (o) => { o.status = "Returned"; });
      if (!d.published_version_id) change("qms_document", d, (o) => { o.status = "Returned"; });
    }),
    approve: act((versionId, changeType = "Major", board = null) => {
      const v = ver(versionId), d = doc(v.document_id);
      if (v.status !== "In review") err(`Version is ${v.status}, not In review`);
      const s = pendingStep(v.id, "Approve");
      if ([v.author_id, v.submitted_by].includes(current)) err("You cannot approve a document you wrote or submitted; it goes to the next level");
      if (!canDecide(s)) err("You are not the approver for this document");
      if (s.required_role === "board" && !(board?.path && board?.no && board?.date)) err("Upload the signed Board resolution with its number and date");
      let major = 1, minor = 0; const prev = d.published_version_id ? ver(d.published_version_id) : null;
      if (prev) { if (changeType === "Minor") { major = prev.major; minor = prev.minor + 1; } else { major = prev.major + 1; minor = 0; } }
      if (prev) change("qms_version", prev, (o) => { o.status = "Obsolete"; });
      change("qms_approval_step", s, (o) => { o.decision = "Approved"; o.decided_by = current; o.decided_at = now(); });
      change("qms_version", v, (o) => Object.assign(o, { status: "Approved", major, minor, change_type: changeType, approved_by: current,
        approved_at: now(), published_pdf_path: o.pdf_path, board_resolution_path: board?.path ?? null,
        board_resolution_no: board?.no ?? null, board_resolution_date: board?.date ?? null }));
      change("qms_document", d, (o) => Object.assign(o, { status: "Approved", published_version_id: v.id, current_version_id: v.id,
        approved_date: isoDate(), next_review_date: addMonths(12), retention_until: null }));
      notify("published", `${d.code ?? d.title} v${major}.${minor} is now in force.`, d.id);
      return `${major}.${minor}`;
    }),
    async approveWithBoardResolution(documentId, versionId, file, no, date) {
      const path = `${documentId}/${versionId}/board-resolution-${Date.now()}.pdf`;
      blobs[path] = URL.createObjectURL(file);
      return this.approve(versionId, "Major", { path, no, date });
    },
    withdraw: act((documentId, reason) => {
      if (!has("qms_admin")) err("Only the QMS Administrator withdraws documents");
      if (!reason?.trim()) err("A reason is required");
      const d = doc(documentId);
      db.versions.filter((v) => v.document_id === d.id && v.status === "Approved").forEach((v) => change("qms_version", v, (o) => { o.status = "Obsolete"; }));
      change("qms_document", d, (o) => Object.assign(o, { status: "Obsolete", published_version_id: null, withdrawn_reason: reason, retention_until: addYears(5) }));
    }),
    extendReview: act((documentId, newDate, reason) => {
      if (!has("qms_admin")) err("Only the QMS Administrator extends review dates");
      if (!reason?.trim()) err("A reason is required");
      change("qms_document", doc(documentId), (o) => { o.next_review_date = newDate; });
    }),
    async publishNow() { return { ok: true, processed: [] }; },

    async myApprovals() {
      needGroup();
      return db.steps.filter((s) => s.kind === "Approve" && canDecide(s)).map((s) => {
        const v = ver(s.version_id), d = doc(v.document_id);
        return { step_id: s.id, version_id: v.id, document_id: d.id, code: d.code, title: d.title, doc_type: d.doc_type,
          department: d.department, version_no: verNo(v), submitted_at: v.submitted_at, required_role: s.required_role,
          required_department: s.required_department, working_days_waiting: workingDays(v.submitted_at) };
      });
    },
    async checkQueue() {
      needGroup();
      return db.versions.filter((v) => v.status === "Submitted").map((v) => { const d = doc(v.document_id);
        return { version_id: v.id, document_id: d.id, code: d.code, title: d.title, department: d.department, version_no: verNo(v),
          submitted_at: v.submitted_at, check_due: null }; });
    },
    async library() {
      return db.documents.filter((d) => d.published_version_id && canRead(d)).map((d) => { const v = ver(d.published_version_id);
        return { id: d.id, code: d.code, title: d.title, doc_class: d.doc_class, doc_type: d.doc_type, department: d.department,
          process: d.process, programme: d.programme, version_no: verNo(v), approved_date: d.approved_date,
          next_review_date: d.next_review_date, published_pdf_path: v.published_pdf_path, controlled: d.doc_class === 1 }; })
        .sort((a, b) => (a.code ?? "").localeCompare(b.code ?? ""));
    },
    async download(documentId) {
      const d = doc(documentId); if (!canRead(d)) err("Not allowed");
      const v = ver(d.published_version_id);
      audit("download", "qms_document", d.id, null, null, verNo(v)); save();
      if (blobs[v.published_pdf_path]) return { blob: await (await fetch(blobs[v.published_pdf_path])).blob(), name: `${d.code} v${verNo(v)} (uncontrolled).pdf`, demo: true };
      err("Demo mode: no PDF content is kept for this document. In the live system staff get the PDF stamped 'Uncontrolled copy' with today's date.");
    },
    async auditLog() {
      if (!(has("qms_admin") || has("ceo") || has("board_treasurer") || has("head_ops_systems"))) return [];
      const emails = Object.fromEntries(db.users.map((u) => [u.id, u.email]));
      return db.audit.map((r) => ({ ...r, user_email: emails[r.user_id] ?? "" }));
    },
    async listUsers() {
      if (!(has("qms_admin") || has("head_ops_systems"))) err("Only the QMS Administrator or Head of Operations and Systems manages roles");
      return db.users.map((u) => ({ user_id: u.id, email: u.email, roles: u.roles }));
    },
    grantRole: act((email, role, department, programme) => {
      if (!(has("qms_admin") || has("head_ops_systems"))) err("Only the QMS Administrator or Head of Operations and Systems manages roles");
      const u = db.users.find((x) => x.email.toLowerCase() === email.trim().toLowerCase())
        ?? err(`No user signs in with ${email}. In the live system, add them first under Authentication > Users in Supabase.`);
      if (["hod", "staff"].includes(role) && !department) err("Choose a department for this role");
      if (["mentor", "programme_owner"].includes(role) && !programme) err("Enter the programme for this role");
      const r = { id: uid(), role, department: department || null, programme: programme || null };
      u.roles.push(r); audit("insert", "qms_user_role", r.id, null, { user_id: u.id, ...r });
    }),
    revokeRole: act((id) => {
      if (!(has("qms_admin") || has("head_ops_systems"))) err("Only the QMS Administrator or Head of Operations and Systems manages roles");
      for (const u of db.users) {
        const i = u.roles.findIndex((r) => r.id === id);
        if (i >= 0) {
          if (u.id === current && ["qms_admin", "head_ops_systems"].includes(u.roles[i].role)) err("You cannot remove your own administrator role; ask the other administrator");
          audit("delete", "qms_user_role", id, u.roles[i], null); u.roles.splice(i, 1);
        }
      }
    }),
  };
}

function workingDays(fromIso) {
  if (!fromIso) return 0;
  let d = new Date(fromIso); d.setHours(0, 0, 0, 0); const end = new Date(); end.setHours(0, 0, 0, 0); let n = 0;
  while (d < end) { d.setDate(d.getDate() + 1); const w = d.getDay(); if (w !== 0 && w !== 6) n++; }
  return n;
}
