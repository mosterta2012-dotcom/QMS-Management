// QMS Management web app (static; runs on GitHub Pages).
// Screens: Document Control library, Documents, Document details, Approvals, Audit log,
// People and roles. Every action calls the back end; the database decides what is allowed
// and its message is shown to the user as it is.
import { DOC_TYPES, CLASS_LABEL, STATUS_BADGE, ROLE_LABEL, QMS_GROUP_ROLES, CODE_RE,
  approverLabel, visibleLabel, fmtDate, fmtDateTime, isoDate } from "./common.js";

const cfg = window.QMS_CONFIG ?? {};
const LIVE = !!(cfg.supabaseUrl && cfg.supabaseAnonKey);
const S = { api: null, me: null, lists: { departments: [], processes: [] }, approvalsCount: 0 };
const $app = document.getElementById("app");

// ---------------------------------------------------------------- tiny DOM helpers
function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs ?? {})) {
    if (v == null || v === false) continue;
    if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else if (k === "class") el.className = v;
    else if (k === "html") el.innerHTML = v;
    else if (v === true) el.setAttribute(k, "");
    else el.setAttribute(k, v);
  }
  for (const k of kids.flat(Infinity)) if (k != null && k !== false) el.append(k instanceof Node ? k : document.createTextNode(String(k)));
  return el;
}
const badge = (status) => { const b = STATUS_BADGE[status] ?? { label: status, tone: "grey" }; return h("span", { class: `badge t-${b.tone}` }, b.label); };
function toast(msg, isErr = false) {
  const el = h("div", { class: isErr ? "err" : "" }, msg);
  document.getElementById("toast").append(el);
  setTimeout(() => el.remove(), isErr ? 9000 : 4000);
}
const has = (role, dept) => !!S.me?.roles.some((r) => r.role === role && (dept == null || r.department === dept));
const inGroup = () => QMS_GROUP_ROLES.some((r) => has(r));
const deptName = (c) => S.lists.departments.find((d) => d.code === c)?.name ?? c ?? "";

/** Run an action; show the database's own message if it refuses. */
async function run(fn, okMsg) {
  try { const r = await fn(); if (okMsg) toast(okMsg); return r ?? true; }
  catch (e) { toast(e.message || String(e), true); return null; }
}

/** Modal form. fields: [{name,label,type,options,required,hint,full,value}] → resolves values or null. */
function modal(title, note, fields, submitLabel = "Save", danger = false) {
  return new Promise((resolve) => {
    const inputs = {};
    const form = h("form", { class: "form" }, fields.map((f) => {
      let input;
      if (f.type === "select") {
        input = h("select", { name: f.name, required: f.required }, (f.options ?? []).map((o) =>
          h("option", { value: o.value, selected: String(o.value) === String(f.value ?? "") }, o.label)));
        if (f.onchange) input.addEventListener("change", () => f.onchange(input.value, inputs));
      } else if (f.type === "textarea") input = h("textarea", { name: f.name, required: f.required, placeholder: f.placeholder ?? "" }, f.value ?? "");
      else if (f.type === "checkbox") input = h("input", { type: "checkbox", name: f.name, checked: !!f.value });
      else if (f.type === "checks") {
        input = h("div", {}, (f.options ?? []).map((o) => h("label", { class: "chk" },
          h("input", { type: "checkbox", value: o.value, checked: (f.value ?? []).includes(o.value) }), o.label)));
        input.getValues = () => [...input.querySelectorAll("input:checked")].map((x) => x.value);
      } else input = h("input", { type: f.type ?? "text", name: f.name, required: f.required, value: f.value ?? "",
        accept: f.accept, placeholder: f.placeholder ?? "", min: f.min });
      inputs[f.name] = input;
      if (f.type === "checkbox") return h("div", { class: f.full ? "full" : "" }, h("label", { class: "chk" }, input, f.label), f.hint ? h("div", { class: "hint" }, f.hint) : null);
      return h("div", { class: f.full ? "full" : "" }, h("label", {}, f.label + (f.required ? " *" : "")), input,
        f.hint ? h("div", { class: "hint" }, f.hint) : null);
    }));
    const close = (val) => { bg.remove(); resolve(val); };
    const okBtn = h("button", { class: danger ? "btn warn" : "btn", type: "submit" }, submitLabel);
    form.append(h("div", { class: "foot full" }, h("button", { class: "btn ghost", type: "button", onclick: () => close(null) }, "Cancel"), okBtn));
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const out = {};
      for (const f of fields) {
        const el = inputs[f.name];
        out[f.name] = f.type === "checkbox" ? el.checked : f.type === "file" ? el.files?.[0] ?? null
          : f.type === "checks" ? el.getValues() : el.value.trim();
        if (f.required && (out[f.name] == null || out[f.name] === "" || (Array.isArray(out[f.name]) && !out[f.name].length))) {
          toast(`${f.label} is required`, true); return;
        }
      }
      close(out);
    });
    const bg = h("div", { class: "modalbg", onclick: (e) => { if (e.target === bg) close(null); } },
      h("div", { class: "modal", role: "dialog", "aria-modal": "true" }, h("h2", {}, title), note ? h("p", { class: "note" }, note) : null, form));
    document.body.append(bg);
    bg.querySelector("input,select,textarea")?.focus();
    for (const f of fields) if (f.onchange) f.onchange(inputs[f.name].value, inputs);
  });
}
const confirmBox = (title, note, label = "Confirm") => modal(title, note, [], label).then((v) => v !== null);

function saveBlob(blob, name) {
  const a = h("a", { href: URL.createObjectURL(blob), download: name }); document.body.append(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 2000);
}

// ---------------------------------------------------------------- shell
function shell(active, content) {
  const nav = h("nav", { class: "side" },
    h("div", { class: "grp" }, "Documents"),
    link("#/library", "Document Control", active === "library"),
    inGroup() ? [
      h("div", { class: "grp" }, "QMS Management"),
      link("#/documents", "Documents", active === "documents"),
      link("#/approvals", "Approvals", active === "approvals", S.approvalsCount),
      (has("qms_admin") || has("ceo") || has("board_treasurer") || has("head_ops_systems")) ? link("#/audit", "Audit log", active === "audit") : null,
      (has("qms_admin") || has("head_ops_systems")) ? link("#/people", "People and roles", active === "people") : null,
    ] : null,
    h("div", { class: "grp" }, "Help"),
    link("#/about", "How this works", active === "about"));
  const roles = S.me.roles.map((r) => ROLE_LABEL[r.role] + (r.department ? ` ${r.department}` : "") + (r.programme ? ` (${r.programme})` : "")).join(" · ") || "No QMS role yet";
  const top = h("div", { class: "top" },
    h("div", { class: "brand" }, "QMS Management", h("small", {}, cfg.organisation ?? "")),
    h("div", { class: "sp" }),
    h("div", { class: "who" }, h("b", {}, S.me.email), h("br"), roles),
    LIVE ? h("button", { onclick: async () => { await S.api.signOut(); location.hash = ""; start(); } }, "Sign out") : null);
  const demoBar = LIVE ? null : h("div", { class: "demo" },
    h("b", {}, "Demo mode"), "Sample data kept in this browser only. Act as:",
    h("select", { onchange: async (e) => { S.api.demoSwitch(e.target.value); await loadMe(); route(); } },
      S.api.demoUsers().map((u) => h("option", { value: u.id, selected: u.id === S.api.demoCurrent() }, u.label))),
    h("button", { onclick: async () => { if (await confirmBox("Reset demo data?", "All demo changes in this browser are cleared.", "Reset")) { S.api.demoReset(); route(); } } }, "Reset demo data"),
    h("span", { class: "small" }, "To go live, add your Supabase details to config.js (see README)."));
  $app.replaceChildren(top, demoBar ?? "", h("div", { class: "layout" }, nav, h("main", {}, content)));
}
function link(href, text, on, count) {
  return h("a", { href, class: on ? "on" : "" }, text, count ? h("span", { class: "count" }, count) : null);
}

// ---------------------------------------------------------------- screens
async function screenLibrary() {
  const items = await S.api.library();
  let q = "";
  const body = h("tbody");
  const draw = () => {
    const rows = items.filter((d) => !q || `${d.code} ${d.title} ${d.process ?? ""}`.toLowerCase().includes(q));
    body.replaceChildren(...(rows.length ? rows.map((d) => h("tr", {},
      h("td", {}, d.controlled ? h("span", { class: "badge t-navy" }, "Controlled") : h("span", { class: "badge t-grey" }, CLASS_LABEL[d.doc_class])),
      h("td", { class: "code" }, d.code ?? ""), h("td", {}, d.title), h("td", {}, DOC_TYPES[d.doc_type] ?? d.doc_type),
      h("td", {}, deptName(d.department)), h("td", {}, d.version_no), h("td", {}, fmtDate(d.approved_date)),
      h("td", {}, fmtDate(d.next_review_date)),
      h("td", {}, h("button", { class: "btn sm", onclick: () => doDownload(d.id) }, "Download")))) :
      [h("tr", {}, h("td", { colspan: 9, class: "empty" }, items.length ? "No match." : "No approved documents yet. Approved documents appear here automatically."))]));
  };
  draw();
  shell("library", [
    h("h1", {}, "Document Control"),
    h("p", { class: "sub" }, "Approved, current documents only. Downloads are stamped “Uncontrolled copy when printed or downloaded” with the date."),
    h("div", { class: "bar" }, h("input", { type: "search", placeholder: "Search code, title or process", oninput: (e) => { q = e.target.value.toLowerCase(); draw(); } })),
    h("div", { class: "tablewrap" }, h("table", {}, h("thead", {}, h("tr", {}, ["", "Code", "Title", "Type", "Department", "Version", "Approved", "Next review", ""].map((t) => h("th", {}, t)))), body)),
  ]);
}
async function doDownload(id) {
  const r = await run(() => S.api.download(id));
  if (r?.blob) saveBlob(r.blob, r.name);
}

async function screenDocuments() {
  const docs = await S.api.listDocuments();
  const f = { q: "", type: "", dept: "", status: "", cls: "" };
  const body = h("tbody");
  const counts = h("span", { class: "muted small" });
  const draw = () => {
    const rows = docs.filter((d) => (!f.q || `${d.code ?? ""} ${d.previous_code ?? ""} ${d.title} ${d.process ?? ""}`.toLowerCase().includes(f.q))
      && (!f.type || d.doc_type === f.type) && (!f.dept || d.department === f.dept) && (!f.status || d.status === f.status)
      && (!f.cls || String(d.doc_class) === f.cls));
    counts.textContent = `${rows.length} of ${docs.length} documents`;
    body.replaceChildren(...(rows.length ? rows.map((d) => h("tr", { class: "click", onclick: () => { location.hash = `#/doc/${d.id}`; } },
      h("td", { class: "code" }, d.code ?? h("span", { class: "muted" }, d.previous_code ? `(${d.previous_code})` : "no code")),
      h("td", {}, d.title), h("td", {}, DOC_TYPES[d.doc_type]), h("td", {}, d.department ?? ""), h("td", { class: "code" }, d.process ?? ""),
      h("td", {}, d.current?.version_no ?? ""), h("td", {}, badge(d.status),
        d.current && d.current.status !== d.status ? h("div", { class: "small muted" }, `new draft: ${STATUS_BADGE[d.current.status]?.label}`) : null),
      h("td", {}, fmtDate(d.next_review_date)))) : [h("tr", {}, h("td", { colspan: 8, class: "empty" }, "No documents match."))]));
  };
  const sel = (key, label, opts) => h("select", { onchange: (e) => { f[key] = e.target.value; draw(); } },
    h("option", { value: "" }, label), opts.map(([v, l]) => h("option", { value: v }, l)));
  draw();
  const canCreate = has("qms_admin") || has("ceo") || has("hod") || has("programme_owner");
  shell("documents", [
    h("h1", {}, "QMS Management: Documents"),
    h("p", { class: "sub" }, "Master Document Register. Drafts are visible to the QMS group only."),
    h("div", { class: "bar" },
      h("input", { type: "search", placeholder: "Search code, title or process", oninput: (e) => { f.q = e.target.value.toLowerCase(); draw(); } }),
      sel("type", "All types", Object.entries(DOC_TYPES)),
      sel("dept", "All departments", S.lists.departments.map((d) => [d.code, d.name])),
      sel("status", "All statuses", Object.entries(STATUS_BADGE).map(([k, v]) => [k, v.label])),
      sel("cls", "All classes", Object.entries(CLASS_LABEL)),
      h("span", { class: "sp" }), counts,
      canCreate ? h("button", { class: "btn", onclick: newDocument }, "New document") : null),
    h("div", { class: "tablewrap" }, h("table", {}, h("thead", {}, h("tr", {}, ["Code", "Title", "Type", "Dept", "Process", "Version", "Status", "Next review"].map((t) => h("th", {}, t)))), body)),
  ]);
}

function processOptions(dept) {
  return [{ value: "", label: "— choose —" }, ...S.lists.processes.filter((p) => !dept || p.department === dept || dept === "GOV")
    .map((p) => ({ value: p.code, label: `${p.code} ${p.name}` }))];
}
function visibleOptions() {
  return [{ value: "all_staff", label: "All staff" }, { value: "hods", label: "HODs" }, { value: "mentors", label: "Mentors" },
    ...S.lists.departments.map((d) => ({ value: `dept:${d.code}`, label: `${d.name} staff` }))];
}
const deptOptions = (blank = true) => [...(blank ? [{ value: "", label: "— choose —" }] : []), ...S.lists.departments.map((d) => ({ value: d.code, label: `${d.name} (${d.code})` }))];

async function newDocument() {
  const fixDept = !has("qms_admin") && !has("ceo") ? S.me.roles.find((r) => r.role === "hod")?.department : null;
  const v = await modal("New document", "Creates the document and its first draft (0.1). Next: upload the Word file and its PDF, then submit.", [
    { name: "title", label: "Title", required: true, full: true, hint: "No version or copy marks (v2, Final, (1), copy)." },
    { name: "docClass", label: "Class", type: "select", value: "1", options: Object.entries(CLASS_LABEL).map(([value, label]) => ({ value, label })) },
    { name: "docType", label: "Type", type: "select", required: true, value: "SOP", options: Object.entries(DOC_TYPES).map(([value, label]) => ({ value, label: `${value} ${label}` })) },
    { name: "department", label: "Owning department", type: "select", required: true, value: fixDept ?? "", options: deptOptions(),
      onchange: (val, inp) => { if (inp.process) inp.process.replaceChildren(...processOptions(val).map((o) => h("option", { value: o.value }, o.label))); } },
    { name: "process", label: "Process", type: "select", options: processOptions(fixDept) },
    { name: "code", label: "Code", placeholder: "QMS-SOP-FIN-001", hint: "Class 1: QMS-TYPE-DOMAIN-###. Can be added later, but needed before submitting." },
    { name: "domain", label: "Domain", placeholder: "FIN" },
    { name: "ownerRole", label: "Owner (role, not a name)", required: true, value: has("qms_admin") ? "QMS Administrator" : fixDept ? `HOD ${fixDept}` : "" },
    { name: "programme", label: "Programme (class 2 only)" },
    { name: "isGovernance", label: "Governance policy (Board approves)", type: "checkbox" },
    { name: "isCrossDepartment", label: "Cross-department (CEO approves)", type: "checkbox" },
    { name: "visibleTo", label: "Visible to (once approved)", type: "checks", full: true, value: ["all_staff"], options: visibleOptions() },
  ], "Create document");
  if (!v) return;
  if (v.code && !CODE_RE.test(v.code)) { toast("Code must look like QMS-SOP-FIN-001", true); return; }
  const id = await run(() => S.api.createDocument({ ...v, docClass: Number(v.docClass), code: v.code.toUpperCase() }), "Document created");
  if (id) location.hash = `#/doc/${id}`;
}

async function screenDoc(id) {
  const { doc: d, versions, steps, emails } = await S.api.getDocument(id);
  const who = (uid) => (uid ? emails[uid] ?? "—" : "—");
  const cur = versions.find((v) => v.id === d.current_version_id) ?? versions[0];
  const live = versions.find((v) => v.id === d.published_version_id);
  const curSteps = steps.filter((s) => s.version_id === cur?.id);
  const pending = curSteps.filter((s) => s.decision === "Pending").at(-1);
  const mine = cur && cur.status === "In review" ? (await S.api.myApprovals()).find((a) => a.version_id === cur.id) : null;
  const route = cur && ["Submitted", "In review"].includes(cur.status) ? await S.api.routeOf(cur.id).catch(() => null) : null;
  const isAuthor = cur && (cur.author_id === S.me.id || d.owner_user === S.me.id);
  const editable = cur && ["Draft", "Returned"].includes(cur.status);
  const canEditDraft = editable && (isAuthor || has("qms_admin"));
  const canSubmit = editable && (has("qms_admin") || has("hod", d.department) || isAuthor);
  const reload = () => screenDoc(id);

  const fileLink = (path, label) => path ? h("a", { href: "#", onclick: async (e) => { e.preventDefault();
    const url = await run(() => S.api.fileUrl(path)); if (url) window.open(url, "_blank", "noopener"); } }, label) : h("span", { class: "muted" }, `no ${label}`);

  const acts = [];
  if (canEditDraft) acts.push(h("button", { class: "btn ghost", onclick: () => uploadFiles(d, cur, reload) }, cur.source_path ? "Replace files" : "Upload files"));
  if (canSubmit) acts.push(h("button", { class: "btn", onclick: async () => {
    if (await run(() => S.api.submit(cur.id), "Submitted for checking")) reload(); } }, cur.status === "Returned" ? "Resubmit" : "Submit"));
  if (cur?.status === "Submitted" && has("qms_admin")) {
    acts.push(h("button", { class: "btn", onclick: async () => { if (await run(() => S.api.sendForApproval(cur.id), "Sent for approval")) { await refreshCount(); reload(); } } }, "Send for approval"));
  }
  if (cur && (cur.status === "Submitted" && has("qms_admin") || mine)) acts.push(h("button", { class: "btn warn", onclick: () => returnDoc(cur, reload) }, "Return"));
  if (mine) acts.push(...approveButtons(d, cur, mine, reload));
  if (d.status !== "Obsolete" && cur && ["Approved", "Obsolete"].includes(cur.status) && (has("qms_admin") || has("ceo") || has("hod", d.department) || d.owner_user === S.me.id))
    acts.push(h("button", { class: "btn ghost", onclick: () => startNewVersion(d, reload) }, "Start new version"));
  if (has("qms_admin")) {
    acts.push(h("button", { class: "btn ghost", onclick: () => editDetails(d, reload) }, "Edit details"));
    if (d.status === "Approved") acts.push(h("button", { class: "btn ghost", onclick: () => extendReview(d, reload) }, "Extend review date"));
    if (d.status !== "Obsolete") acts.push(h("button", { class: "btn warn", onclick: () => withdraw(d, reload) }, "Withdraw"));
  }
  if (LIVE && live && !live.published_pdf_path && inGroup()) acts.push(h("button", { class: "btn ghost", onclick: () => publishNow(reload) }, "Publish controlled PDF now"));
  if (d.published_version_id) acts.push(h("button", { class: "btn ghost", onclick: () => doDownload(d.id) }, "Download (uncontrolled)"));

  const hints = [];
  if (editable && d.doc_class === 1 && !CODE_RE.test(d.code ?? "")) hints.push(`Needs a code like QMS-SOP-GOV-001 before it can be submitted${d.previous_code ? ` (working code ${d.previous_code}, decision D-11)` : ""}. The QMS Administrator sets it under Edit details.`);
  if (editable && d.doc_class === 1 && !d.process) hints.push("Needs a process code before it can be submitted (Edit details).");
  if (editable && !cur.source_path) hints.push("Upload the Word file (and its PDF) before submitting.");
  if (editable && cur.source_path && !cur.pdf_path) hints.push("Add the PDF too: it becomes the controlled copy on approval.");
  if (cur?.status === "Returned") { const r = curSteps.filter((s) => s.decision === "Returned").at(-1); if (r) hints.push(`Returned by ${who(r.decided_by)}: “${r.comment}”`); }
  if (LIVE && live && !live.published_pdf_path) hints.push("Approved, but the controlled PDF is not published yet. Use “Publish controlled PDF now” (needs the qms-publish function deployed).");

  shell("documents", [
    h("p", { class: "small" }, h("a", { href: "#/documents" }, "← Documents")),
    h("h1", {}, h("span", { class: "code", style: "font-size:18px" }, d.code ?? d.previous_code ?? ""), " ", d.title),
    h("p", { class: "sub" }, badge(d.status), " ", live ? `Live version ${live.version_no}` : "Not yet approved",
      cur && cur.id !== live?.id ? ` · Draft ${cur.version_no} ${STATUS_BADGE[cur.status]?.label.toLowerCase()}` : ""),
    hints.length ? h("div", { class: "warnbox" }, hints.map((t) => h("div", {}, "• " + t))) : null,
    h("div", { class: "card" },
      h("div", { class: "grid" },
        kv("Class", CLASS_LABEL[d.doc_class]), kv("Type", `${d.doc_type} ${DOC_TYPES[d.doc_type]}`),
        kv("Department", deptName(d.department)), kv("Process", d.process ?? "—"), kv("Domain", d.domain ?? "—"),
        kv("Owner", d.owner_role), kv("Approver (matrix)", route ? approverLabel(route.approver, route.department) : d.is_governance || d.doc_type === "MAN" ? "Board" : "—"),
        kv("Visible to", (d.visible_to ?? []).map((v) => visibleLabel(v, S.lists.departments)).join(", ")),
        kv("Approved", fmtDate(d.approved_date) || "—"), kv("Next review", fmtDate(d.next_review_date) || "—"),
        d.previous_code ? kv("Previous code", d.previous_code) : null, d.programme ? kv("Programme", d.programme) : null,
        d.withdrawn_reason ? kv("Withdrawn because", d.withdrawn_reason) : null, d.retention_until ? kv("Keep until", fmtDate(d.retention_until)) : null),
      h("div", { class: "actions" }, acts)),
    cur ? h("div", { class: "card" }, h("h2", {}, `Version ${cur.version_no} files`),
      h("div", { class: "grid" }, kv("Word / Excel original", fileLink(cur.source_path, "original")), kv("PDF", fileLink(cur.pdf_path, "PDF")),
        cur.board_resolution_path ? kv(`Board resolution ${cur.board_resolution_no ?? ""}`, fileLink(cur.board_resolution_path, "resolution")) : null,
        cur.change_summary ? kv("Change summary", cur.change_summary) : null)) : null,
    h("div", { class: "card" }, h("h2", {}, "Approval trail"),
      steps.length ? h("ul", { class: "steps" }, steps.map((s) => { const v = versions.find((x) => x.id === s.version_id);
        return h("li", {}, h("span", { class: `dot ${s.decision}` }), h("div", {},
          h("b", {}, s.kind === "Check" ? "QMS Administrator check" : `Approval: ${approverLabel(s.required_role, s.required_department)}`),
          ` · v${v?.version_no} · `, s.decision === "Pending" ? h("span", { class: "badge t-amber" }, "Waiting") : h("span", { class: `badge ${s.decision === "Approved" ? "t-green" : "t-red"}` }, s.decision),
          s.decided_by ? h("div", { class: "small muted" }, `${who(s.decided_by)} · ${fmtDateTime(s.decided_at)}`) : h("div", { class: "small muted" }, `Waiting since ${fmtDateTime(s.created_at)}`),
          s.comment ? h("div", { class: "small" }, `“${s.comment}”`) : null)); }))
        : h("p", { class: "muted" }, "Nothing submitted yet.")),
    h("div", { class: "card" }, h("h2", {}, "Version history"),
      h("div", { class: "tablewrap" }, h("table", {}, h("thead", {}, h("tr", {}, ["Version", "Status", "Change", "Author", "Submitted", "Approved by", "Approved"].map((t) => h("th", {}, t)))),
        h("tbody", {}, versions.map((v) => h("tr", {}, h("td", {}, v.version_no), h("td", {}, badge(v.status)),
          h("td", {}, [v.change_type, v.change_summary].filter(Boolean).join(": ") || "—"), h("td", {}, who(v.author_id)),
          h("td", {}, fmtDate(v.submitted_at)), h("td", {}, who(v.approved_by)), h("td", {}, fmtDate(v.approved_at)))))))),
  ]);
  void pending;
}
const kv = (k, v) => h("div", {}, h("div", { class: "k" }, k), h("div", { class: "v" }, v ?? "—"));

function approveButtons(d, cur, mine, reload) {
  if (mine.required_role === "board") {
    return [h("button", { class: "btn ok", onclick: async () => {
      const v = await modal("Record Board approval", "Upload the signed Board resolution (PDF). This approves the document as the Board's decision.", [
        { name: "file", label: "Signed resolution (PDF)", type: "file", accept: "application/pdf", required: true, full: true },
        { name: "no", label: "Resolution number", required: true },
        { name: "date", label: "Resolution date", type: "date", required: true, value: isoDate() }], "Record approval");
      if (!v) return;
      if (await run(() => S.api.approveWithBoardResolution(d.id, cur.id, v.file, v.no, v.date), "Approved by Board resolution")) { await afterApprove(); reload(); }
    } }, "Upload Board resolution and approve")];
  }
  return [h("button", { class: "btn ok", onclick: async () => {
    let changeType = "Major";
    if (d.published_version_id) {
      const v = await modal("Approve", "A version is already live. Is this a minor change (x.1) or a major change (next whole number)?",
        [{ name: "t", label: "Change type", type: "select", value: "Minor", options: [{ value: "Minor", label: "Minor (e.g. 1.0 → 1.1)" }, { value: "Major", label: "Major (e.g. 1.1 → 2.0)" }] }], "Approve");
      if (!v) return; changeType = v.t;
    } else if (!(await confirmBox("Approve this document?", `${d.code ?? d.title} becomes version 1.0, in force from today, with a review date in 12 months.`, "Approve"))) return;
    const r = await run(() => S.api.approve(cur.id, changeType));
    if (r) { toast(`Approved as version ${r}`); await afterApprove(); reload(); }
  } }, "Approve")];
}
async function afterApprove() {
  await refreshCount();
  if (!LIVE) return;
  const p = await S.api.publishNow();
  if (!p.ok) toast("Approved. The controlled PDF could not be published yet: " + p.message, true);
}
async function publishNow(reload) {
  const p = await S.api.publishNow();
  if (p.ok) { toast(p.processed.length ? "Controlled PDF published" : "Nothing waiting to publish"); reload(); } else toast(p.message, true);
}
async function returnDoc(cur, reload) {
  const v = await modal("Return document", "Say what needs to change. The author sees this comment.", [
    { name: "comment", label: "Comment", type: "textarea", required: true, full: true }], "Return", true);
  if (v && await run(() => S.api.returnDoc(cur.id, v.comment), "Returned to the author")) { await refreshCount(); reload(); }
}
async function uploadFiles(d, cur, reload) {
  const v = await modal("Upload files", "Upload the Word (or Excel) original and a PDF of it (in Word: File → Save as PDF). The PDF becomes the controlled copy when approved.", [
    { name: "word", label: "Word or Excel original", type: "file", accept: ".docx,.xlsx,application/vnd.openxmlformats-officedocument.wordprocessingml.document,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", full: true, required: !cur.source_path },
    { name: "pdf", label: "PDF of it", type: "file", accept: "application/pdf,.pdf", full: true, required: !cur.pdf_path }], "Upload");
  if (!v) return;
  if (!v.word && !v.pdf) { toast("Choose a file", true); return; }
  if (await run(() => S.api.uploadDraftFiles(d.id, cur.id, v.word, v.pdf), "Files uploaded")) reload();
}
async function startNewVersion(d, reload) {
  const v = await modal("Start new version", "Creates the next draft. The live version stays in force until the new one is approved.", [
    { name: "summary", label: "Change summary", type: "textarea", required: true, full: true },
    { name: "significant", label: "Significant change (needs a change request, QMS-SOP-GOV-010)", type: "checkbox", full: true },
    { name: "crTitle", label: "Change request title (if significant)", full: true }], "Start draft");
  if (!v) return;
  let cr = null;
  if (v.significant) {
    cr = await run(() => S.api.logChangeRequest(v.crTitle || `Revise ${d.code ?? d.title}`, "Significant"));
    if (!cr) return;
  }
  if (await run(() => S.api.newDraft(d.id, v.summary, v.significant, cr), "New draft started")) reload();
}
async function editDetails(d, reload) {
  const v = await modal("Edit details", "QMS Administrator only. Status, versions and approvals cannot be changed here.", [
    { name: "title", label: "Title", required: true, full: true, value: d.title },
    { name: "code", label: "Code", value: d.code ?? "", placeholder: "QMS-SOP-GOV-001" },
    { name: "previous_code", label: "Previous code", value: d.previous_code ?? "" },
    { name: "department", label: "Department", type: "select", value: d.department ?? "", options: deptOptions(),
      onchange: (val, inp) => { if (inp.process) { const keep = inp.process.value; inp.process.replaceChildren(...processOptions(val).map((o) => h("option", { value: o.value, selected: o.value === keep }, o.label))); } } },
    { name: "process", label: "Process", type: "select", value: d.process ?? "", options: processOptions(d.department) },
    { name: "domain", label: "Domain", value: d.domain ?? "" },
    { name: "owner_role", label: "Owner (role)", required: true, value: d.owner_role },
    { name: "programme", label: "Programme", value: d.programme ?? "" },
    { name: "is_governance", label: "Governance policy (Board approves)", type: "checkbox", value: d.is_governance },
    { name: "is_cross_department", label: "Cross-department (CEO approves)", type: "checkbox", value: d.is_cross_department },
    { name: "visible_to", label: "Visible to", type: "checks", full: true, value: d.visible_to ?? [], options: visibleOptions() },
    { name: "is_external", label: "Outside material (class 2)", type: "checkbox", value: d.is_external },
    { name: "licence_note", label: "Licence note (outside material)", full: true, value: d.licence_note ?? "" },
  ]);
  if (!v) return;
  if (v.code && !CODE_RE.test(v.code.toUpperCase())) { toast("Code must look like QMS-SOP-GOV-001", true); return; }
  const patch = { ...v, code: v.code ? v.code.toUpperCase() : null, previous_code: v.previous_code || null, process: v.process || null,
    domain: v.domain || null, programme: v.programme || null, licence_note: v.licence_note || null,
    visible_to: v.visible_to.length ? v.visible_to : ["all_staff"] };
  if (await run(() => S.api.updateDocument(d.id, patch), "Details saved")) reload();
}
async function extendReview(d, reload) {
  const v = await modal("Extend review date", `Current review date: ${fmtDate(d.next_review_date)}.`, [
    { name: "date", label: "New review date", type: "date", required: true, min: isoDate() },
    { name: "reason", label: "Reason", type: "textarea", required: true, full: true }]);
  if (v && await run(() => S.api.extendReview(d.id, v.date, v.reason), "Review date extended")) reload();
}
async function withdraw(d, reload) {
  const v = await modal("Withdraw document", "The document becomes Obsolete and leaves Document Control. Retention starts today.", [
    { name: "reason", label: "Reason", type: "textarea", required: true, full: true }], "Withdraw", true);
  if (v && await run(() => S.api.withdraw(d.id, v.reason), "Document withdrawn")) reload();
}

async function screenApprovals() {
  const [mine, queue] = await Promise.all([S.api.myApprovals(), has("qms_admin") ? S.api.checkQueue() : Promise.resolve([])]);
  S.approvalsCount = mine.length + queue.length;
  const open = (id) => () => { location.hash = `#/doc/${id}`; };
  const reload = async () => { await screenApprovals(); };
  shell("approvals", [
    h("h1", {}, "Approvals"),
    h("p", { class: "sub" }, "Open a document to view its PDF before deciding. Nobody approves their own document: it moves up a level automatically."),
    h("div", { class: "card" }, h("h2", {}, `Waiting for my approval (${mine.length})`),
      mine.length ? h("div", { class: "tablewrap" }, h("table", {}, h("thead", {}, h("tr", {}, ["Code", "Title", "Version", "Approver", "Submitted", "Working days", ""].map((t) => h("th", {}, t)))),
        h("tbody", {}, mine.map((a) => h("tr", {}, h("td", { class: "code" }, a.code ?? ""), h("td", {}, a.title), h("td", {}, a.version_no),
          h("td", {}, approverLabel(a.required_role, a.required_department)), h("td", {}, fmtDate(a.submitted_at)),
          h("td", {}, a.working_days_waiting >= 10 ? h("span", { class: "badge t-red" }, a.working_days_waiting) : a.working_days_waiting),
          h("td", {}, h("button", { class: "btn sm", onclick: open(a.document_id) }, "Open"))))))) : h("p", { class: "muted" }, "Nothing is waiting for you.")),
    has("qms_admin") ? h("div", { class: "card" }, h("h2", {}, `Waiting for my check (${queue.length})`),
      h("p", { class: "small muted" }, "QMS Administrator check within 5 working days: code, template, process, change summary. Then send for approval or return."),
      queue.length ? h("div", { class: "tablewrap" }, h("table", {}, h("thead", {}, h("tr", {}, ["Code", "Title", "Version", "Submitted", "Check due", ""].map((t) => h("th", {}, t)))),
        h("tbody", {}, queue.map((q) => h("tr", {}, h("td", { class: "code" }, q.code ?? ""), h("td", {}, q.title), h("td", {}, q.version_no),
          h("td", {}, fmtDate(q.submitted_at)), h("td", {}, fmtDate(q.check_due) || "—"),
          h("td", {}, h("div", { class: "actions", style: "margin:0" },
            h("button", { class: "btn sm", onclick: async () => { if (await run(() => S.api.sendForApproval(q.version_id), "Sent for approval")) reload(); } }, "Send for approval"),
            h("button", { class: "btn sm warn", onclick: () => returnDoc({ id: q.version_id }, reload) }, "Return"),
            h("button", { class: "btn sm ghost", onclick: open(q.document_id) }, "Open")))))))) : h("p", { class: "muted" }, "Nothing to check.")) : null,
  ]);
}

async function screenAudit() {
  const rows = await S.api.auditLog();
  let q = "";
  const body = h("tbody");
  const filtered = () => rows.filter((r) => !q || `${r.user_email} ${r.action} ${r.table_name} ${r.record_id} ${r.version_no ?? ""} ${summary(r)}`.toLowerCase().includes(q));
  const draw = () => body.replaceChildren(...filtered().slice(0, 500).map((r) => h("tr", {}, h("td", {}, fmtDateTime(r.at)), h("td", {}, r.user_email || "system"),
    h("td", {}, r.action), h("td", { class: "code" }, r.table_name), h("td", {}, r.version_no ?? ""), h("td", { class: "small" }, summary(r)))));
  draw();
  const csv = () => {
    const esc = (s) => `"${String(s ?? "").replace(/"/g, '""')}"`;
    const lines = [["When", "User", "Action", "Table", "Record", "Version", "Change"].map(esc).join(",")]
      .concat(filtered().map((r) => [fmtDateTime(r.at), r.user_email, r.action, r.table_name, r.record_id, r.version_no, summary(r)].map(esc).join(",")));
    saveBlob(new Blob(["﻿" + lines.join("\r\n")], { type: "text/csv" }), `qms-audit-log-${isoDate()}.csv`);
  };
  shell("audit", [h("h1", {}, "Audit log"), h("p", { class: "sub" }, "Every change and download. The log cannot be edited or deleted."),
    h("div", { class: "bar" }, h("input", { type: "search", placeholder: "Filter by user, action, table or change", oninput: (e) => { q = e.target.value.toLowerCase(); draw(); } }),
      h("span", { class: "sp" }), h("button", { class: "btn ghost", onclick: csv }, "Export CSV")),
    h("div", { class: "tablewrap" }, h("table", {}, h("thead", {}, h("tr", {}, ["When", "User", "Action", "Table", "Version", "Change"].map((t) => h("th", {}, t)))), body))]);
}
function summary(r) {
  if (r.action === "download") return "Downloaded (uncontrolled copy)";
  const b = r.before ?? {}, a = r.after ?? {};
  if (r.action === "insert") return a.title ?? a.code ?? a.ref ?? (a.kind ? `${a.kind} step` : a.role ? `role ${a.role}` : "");
  if (r.action === "delete") return b.role ? `role ${b.role} removed` : "";
  const skip = new Set(["updated_at", "updated_by", "created_at"]);
  return Object.keys(a).filter((k) => !skip.has(k) && JSON.stringify(a[k]) !== JSON.stringify(b[k]))
    .map((k) => `${k}: ${fmtVal(b[k])} → ${fmtVal(a[k])}`).join("; ");
}
const fmtVal = (v) => (v == null ? "—" : Array.isArray(v) ? v.join(", ") : String(v).length > 40 ? String(v).slice(0, 40) + "…" : String(v));

async function screenPeople() {
  const users = await S.api.listUsers();
  const reload = () => screenPeople();
  const addRole = async (email) => {
    const v = await modal("Give a role", "Use roles, not names. HOD and Staff need a department; Mentor and Programme owner need a programme.", [
      { name: "email", label: "Sign-in e-mail", required: true, full: true, value: email ?? "", type: "email" },
      { name: "role", label: "Role", type: "select", value: "staff", options: Object.entries(ROLE_LABEL).map(([value, label]) => ({ value, label })) },
      { name: "department", label: "Department", type: "select", options: deptOptions() },
      { name: "programme", label: "Programme", full: true, placeholder: "e.g. Scatec E4C" }], "Give role");
    if (v && await run(() => S.api.grantRole(v.email, v.role, v.department, v.programme), "Role given")) reload();
  };
  shell("people", [
    h("h1", {}, "People and roles"),
    h("p", { class: "sub" }, "Who may do what in QMS Management. Changes are written to the audit log."),
    LIVE ? h("div", { class: "info" }, "To add a new person: in Supabase go to Authentication → Users → Add user (or Invite). Then give them a role here.") : null,
    h("div", { class: "bar" }, h("span", { class: "sp" }), h("button", { class: "btn", onclick: () => addRole() }, "Give a role")),
    h("div", { class: "tablewrap" }, h("table", {}, h("thead", {}, h("tr", {}, ["E-mail", "Roles", ""].map((t) => h("th", {}, t)))),
      h("tbody", {}, users.map((u) => h("tr", {}, h("td", {}, u.email),
        h("td", {}, (u.roles ?? []).length ? u.roles.map((r) => h("span", { class: "chip" },
          ROLE_LABEL[r.role] + (r.department ? ` ${r.department}` : "") + (r.programme ? ` (${r.programme})` : ""),
          h("button", { title: "Remove", onclick: async () => {
            if (await confirmBox("Remove role?", `${ROLE_LABEL[r.role]} for ${u.email}`, "Remove") && await run(() => S.api.revokeRole(r.id), "Role removed")) reload();
          } }, "×"))) : h("span", { class: "muted" }, "no role")),
        h("td", {}, h("button", { class: "btn sm ghost", onclick: () => addRole(u.email) }, "Add role")))))))]);
}

function screenAbout() {
  shell("about", [h("h1", {}, "How this works"), h("div", { class: "card" }, h("ol", {},
    h("li", {}, "The owner (or the QMS Administrator) creates the document, uploads the Word file and its PDF, and submits it."),
    h("li", {}, "The QMS Administrator checks it within 5 working days and sends it for approval, or returns it with a comment."),
    h("li", {}, "The approver from the approval matrix approves or returns it. Nobody approves their own document; it moves up a level (HOD → CEO; CEO → Board Treasurer). Governance policies and the QMS Manual need the signed Board resolution, uploaded by the CEO."),
    h("li", {}, "On approval the version becomes 1.0 (then 1.1 for a minor change, 2.0 for a major one), the previous version becomes Obsolete, and the PDF is stamped “Controlled document” and published in Document Control."),
    h("li", {}, "Staff download from Document Control; every copy is stamped “Uncontrolled copy when printed or downloaded” with the date.")),
    h("p", { class: "small muted" }, "Procedure: QMS-SOP-GOV-001 Document Control Procedure v2.0. Rules are enforced by the database, so the screens cannot break them.")),
    h("div", { class: "card" }, h("h2", {}, "Status words"), h("p", {}, Object.values(STATUS_BADGE).map((b) => [h("span", { class: `badge t-${b.tone}` }, b.label), " "])))]);
}

// ---------------------------------------------------------------- sign-in
function screenSignIn(message) {
  let mode = "password";
  const box = h("div", { class: "signin" });
  const draw = () => {
    const email = h("input", { type: "email", required: true, autocomplete: "username" });
    const pw = h("input", { type: "password", required: mode === "password", autocomplete: "current-password" });
    const form = h("form", { class: "form", onsubmit: async (e) => {
      e.preventDefault();
      if (mode === "password") { if (await run(() => S.api.signIn(email.value.trim(), pw.value))) start(); }
      else if (await run(() => S.api.sendLink(email.value.trim()), "Check your e-mail for the sign-in link")) { /* stay */ }
    } },
      h("div", {}, h("label", {}, "E-mail"), email),
      mode === "password" ? h("div", {}, h("label", {}, "Password"), pw) : null,
      h("div", {}, h("button", { class: "btn", type: "submit", style: "width:100%" }, mode === "password" ? "Sign in" : "E-mail me a sign-in link")));
    box.replaceChildren(...[h("h1", {}, "QMS Management"), h("p", { class: "sub" }, cfg.organisation ?? ""),
      message ? h("div", { class: "warnbox" }, message) : null, form,
      h("p", { class: "small" }, h("a", { href: "#", onclick: (e) => { e.preventDefault(); mode = mode === "password" ? "link" : "password"; draw(); } },
        mode === "password" ? "Forgot your password? E-mail me a sign-in link" : "Sign in with a password instead"))].filter(Boolean));
  };
  draw();
  $app.replaceChildren(box);
}

// ---------------------------------------------------------------- router
async function loadMe() {
  S.me = await S.api.me();
  await refreshCount();
}
async function refreshCount() {
  if (!inGroup()) { S.approvalsCount = 0; return; }
  try {
    const [a, q] = await Promise.all([S.api.myApprovals(), has("qms_admin") ? S.api.checkQueue() : []]);
    S.approvalsCount = a.length + q.length;
  } catch { S.approvalsCount = 0; }
}
async function route() {
  const [, page, id] = (location.hash || "#/").split("/");
  try {
    if (page === "item" && id) { const docId = await S.api.findItem(id); location.hash = docId ? `#/doc/${docId}` : "#/library"; return; }
    if (!inGroup() && ["documents", "doc", "approvals", "audit", "people"].includes(page)) { location.hash = "#/library"; return; }
    switch (page) {
      case "documents": return await screenDocuments();
      case "doc": return await screenDoc(id);
      case "approvals": return await screenApprovals();
      case "audit": return await screenAudit();
      case "people": return await screenPeople();
      case "about": return screenAbout();
      case "library": return await screenLibrary();
      default: location.hash = inGroup() ? (S.approvalsCount ? "#/approvals" : "#/documents") : "#/library";
    }
  } catch (e) {
    shell(page, h("div", { class: "card" }, h("h2", {}, "Something went wrong"), h("p", {}, e.message || String(e)),
      h("p", { class: "small muted" }, LIVE ? "If this mentions a missing table or function, run supabase/setup_all.sql in the Supabase SQL Editor (see README)." : "")));
  }
}

async function start() {
  try {
    if (!S.api) {
      if (LIVE) { const { createLiveBackend } = await import("./live.js"); S.api = await createLiveBackend(cfg); }
      else { const { createDemoBackend } = await import("./demo.js"); S.api = createDemoBackend(); }
      S.api.onAuthChange((evt) => { if (evt === "SIGNED_OUT") screenSignIn(); if (evt === "PASSWORD_RECOVERY") setNewPassword(); });
    }
    const session = await S.api.session();
    if (!session) return screenSignIn();
    S.lists = await S.api.lists();
    await loadMe();
    if (!S.me) return screenSignIn();
    if (LIVE && !S.me.roles.length) return screenSignIn(`You are signed in as ${S.me.email}, but you have no QMS role yet. Ask the QMS Administrator to give you one.`);
    await route();
  } catch (e) {
    $app.replaceChildren(h("div", { class: "signin" }, h("h1", {}, "Cannot start"), h("p", {}, e.message || String(e)),
      h("p", { class: "small muted" }, "Check the Supabase URL and anon key in config.js, and that supabase/setup_all.sql has been run.")));
  }
}
async function setNewPassword() {
  const v = await modal("Set a new password", "You signed in with a link. Choose a password for next time.", [
    { name: "pw", label: "New password (at least 8 characters)", type: "password", required: true, full: true }], "Save password");
  if (v) await run(() => S.api.setPassword(v.pw), "Password saved");
}

window.addEventListener("hashchange", () => { if (S.me) route(); });
start();
