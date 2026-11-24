// Live back end: Supabase (database rules in supabase/migrations do the enforcing).
// Mirrors src/lib/qms/api.ts, plus sign-in, people and roles, and file helpers.
const DRAFTS = "qms-drafts";

export async function createLiveBackend(cfg) {
  // supabase-js v2 is bundled in app/vendor (no CDN needed; MIT licence in app/vendor)
  if (!window.supabase?.createClient) {
    await new Promise((ok, bad) => {
      const s = document.createElement("script");
      s.src = new URL("./vendor/supabase.js", import.meta.url).href;
      s.onload = ok; s.onerror = () => bad(new Error("Could not load app/vendor/supabase.js"));
      document.head.append(s);
    });
  }
  const { createClient } = window.supabase;
  const sb = createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });
  const fnBase = cfg.supabaseUrl.replace(/\/$/, "") + "/functions/v1";

  const fail = (error) => { if (error) throw new Error(friendly(error.message)); };
  const rpc = async (fn, args = {}) => { const { data, error } = await sb.rpc(fn, args); fail(error); return data; };
  const emailsFor = async (ids) => {
    const list = [...new Set(ids.filter(Boolean))];
    if (!list.length) return {};
    const { data } = await sb.rpc("qms_user_emails", { p_ids: list });
    return Object.fromEntries((data ?? []).map((r) => [r.user_id, r.email]));
  };
  const token = async () => (await sb.auth.getSession()).data.session?.access_token;
  const ext = (name, fallback) => (name && name.includes(".") ? name.split(".").pop().toLowerCase() : fallback);

  return {
    mode: "live",

    // ---------- Sign-in ----------
    async session() { return (await sb.auth.getSession()).data.session; },
    onAuthChange(cb) { sb.auth.onAuthStateChange((evt) => cb(evt)); },
    async signIn(email, password) {
      const { error } = await sb.auth.signInWithPassword({ email, password }); fail(error);
    },
    async sendLink(email) {
      const { error } = await sb.auth.signInWithOtp({
        email, options: { shouldCreateUser: false, emailRedirectTo: location.origin + location.pathname },
      }); fail(error);
    },
    async setPassword(password) { const { error } = await sb.auth.updateUser({ password }); fail(error); },
    async signOut() { await sb.auth.signOut(); },

    async me() {
      const { data: { user } } = await sb.auth.getUser();
      if (!user) return null;
      const roles = await rpc("qms_my_roles");
      return { id: user.id, email: user.email, roles: roles ?? [] };
    },

    async lists() {
      const [d, p] = await Promise.all([
        sb.from("qms_department").select("code,name").order("name"),
        sb.from("qms_process").select("code,name,department").order("code"),
      ]);
      fail(d.error); fail(p.error);
      return { departments: d.data, processes: p.data };
    },

    // ---------- Documents ----------
    async listDocuments() {
      const { data, error } = await sb.from("qms_document")
        .select("*, current:qms_version!qms_document_current_fk(id,version_no,status)")
        .order("code", { nullsFirst: false }).order("title");
      fail(error);
      return data;
    },
    async getDocument(id) {
      const { data: doc, error } = await sb.from("qms_document").select("*").eq("id", id).single();
      fail(error);
      const { data: versions, error: vErr } = await sb.from("qms_version").select("*")
        .eq("document_id", id).order("draft_seq", { ascending: false });
      fail(vErr);
      let steps = [];
      if (versions?.length) {
        const r = await sb.from("qms_approval_step").select("*").in("version_id", versions.map((v) => v.id)).order("created_at");
        fail(r.error); steps = r.data ?? [];
      }
      const emails = await emailsFor([doc.owner_user, ...versions.flatMap((v) => [v.author_id, v.submitted_by, v.approved_by]),
        ...steps.map((s) => s.decided_by)]);
      return { doc, versions, steps, emails };
    },
    async findItem(id) {
      const d = await sb.from("qms_document").select("id").eq("id", id).maybeSingle();
      if (d.data) return d.data.id;
      const v = await sb.from("qms_version").select("document_id").eq("id", id).maybeSingle();
      return v.data?.document_id ?? null;
    },
    createDocument: (a) => rpc("qms_create_document", {
      p_title: a.title, p_doc_class: a.docClass, p_doc_type: a.docType, p_department: a.department,
      p_owner_role: a.ownerRole, p_code: a.code || null, p_domain: a.domain || null, p_process: a.process || null,
      p_programme: a.programme || null, p_is_governance: !!a.isGovernance,
      p_is_cross_department: !!a.isCrossDepartment, p_visible_to: a.visibleTo?.length ? a.visibleTo : ["all_staff"],
      p_source_path: null,
    }),
    async updateDocument(id, patch) {
      const { error } = await sb.from("qms_document").update(patch).eq("id", id); fail(error);
    },
    /** Word (or Excel) original and PDF for a draft. Each upload gets its own name, so a
     *  returned draft can take corrected files (storage never overwrites). */
    async uploadDraftFiles(documentId, versionId, word, pdf) {
      const stamp = new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
      const base = `${documentId}/${versionId}`;
      const patch = {};
      const up = async (name, f) => {
        const { error } = await sb.storage.from(DRAFTS).upload(`${base}/${name}`, f, { upsert: false, contentType: f.type || undefined });
        fail(error); return `${base}/${name}`;
      };
      if (word) patch.source_path = await up(`${stamp}-source.${ext(word.name, "docx")}`, word);
      if (pdf) patch.pdf_path = await up(`${stamp}-preview.pdf`, pdf);
      if (!Object.keys(patch).length) throw new Error("Choose a file to upload");
      const { error } = await sb.from("qms_version").update(patch).eq("id", versionId); fail(error);
    },
    async fileUrl(path) {
      const { data, error } = await sb.storage.from(DRAFTS).createSignedUrl(path, 300); fail(error);
      return data.signedUrl;
    },
    newDraft: (documentId, changeSummary, isSignificant = false, changeRequestId = null) => rpc("qms_new_draft", {
      p_document_id: documentId, p_source_path: null, p_change_summary: changeSummary,
      p_is_significant: isSignificant, p_change_request_id: changeRequestId,
    }),
    logChangeRequest: (title, significance) => rpc("qms_log_change_request", { p_title: title, p_significance: significance }),
    async listChangeRequests() {
      const { data, error } = await sb.from("qms_change_request").select("*").order("created_at", { ascending: false });
      fail(error); return data;
    },
    async routeOf(versionId) {
      const { data } = await sb.rpc("qms_route", { p_version_id: versionId });
      const r = Array.isArray(data) ? data[0] : data;
      return r ? { approver: r.approver, department: r.approver_department } : null;
    },
    submit: (versionId) => rpc("qms_submit", { p_version_id: versionId }),
    sendForApproval: (versionId) => rpc("qms_send_for_approval", { p_version_id: versionId }),
    returnDoc: (versionId, comment) => rpc("qms_return", { p_version_id: versionId, p_comment: comment }),
    approve: (versionId, changeType = "Major") => rpc("qms_approve", { p_version_id: versionId, p_change_type: changeType }),
    async approveWithBoardResolution(documentId, versionId, file, no, date) {
      const path = `${documentId}/${versionId}/board-resolution-${Date.now()}.pdf`;
      const { error } = await sb.storage.from(DRAFTS).upload(path, file, { upsert: false, contentType: "application/pdf" });
      fail(error);
      return rpc("qms_approve", { p_version_id: versionId, p_change_type: "Major", p_board_resolution_path: path,
        p_board_resolution_no: no, p_board_resolution_date: date });
    },
    withdraw: (documentId, reason) => rpc("qms_withdraw", { p_document_id: documentId, p_reason: reason }),
    extendReview: (documentId, newDate, reason) => rpc("qms_extend_review", { p_document_id: documentId, p_new_date: newDate, p_reason: reason }),

    /** Ask the qms-publish edge function to stamp and publish approved PDFs now. */
    async publishNow() {
      const res = await fetch(`${fnBase}/qms-publish`, {
        method: "POST", headers: { Authorization: `Bearer ${await token()}`, apikey: cfg.supabaseAnonKey },
      }).catch(() => null);
      if (!res) return { ok: false, message: "The publishing service (qms-publish) could not be reached. Is it deployed?" };
      if (!res.ok) return { ok: false, message: `Publishing service answered ${res.status}: ${(await res.text()).slice(0, 200)}` };
      const out = await res.json().catch(() => ({}));
      const errs = (out.processed ?? []).filter((p) => p.error);
      return errs.length ? { ok: false, message: errs.map((e) => e.error).join("; ") } : { ok: true, processed: out.processed ?? [] };
    },

    // ---------- Approvals ----------
    async myApprovals() {
      const { data, error } = await sb.from("qms_my_approvals").select("*").order("submitted_at"); fail(error); return data;
    },
    async checkQueue() {
      const { data, error } = await sb.from("qms_check_queue").select("*").order("submitted_at"); fail(error); return data;
    },

    // ---------- Document Control library ----------
    async library() {
      const { data, error } = await sb.from("qms_library").select("*").order("code"); fail(error); return data;
    },
    async download(documentId) {
      const res = await fetch(`${fnBase}/qms-download?document_id=${encodeURIComponent(documentId)}`, {
        headers: { Authorization: `Bearer ${await token()}`, apikey: cfg.supabaseAnonKey },
      }).catch(() => null);
      if (!res) throw new Error("The download service (qms-download) could not be reached. Is it deployed?");
      if (!res.ok) throw new Error(res.status === 404 ? "The controlled PDF has not been published yet. Ask the QMS Administrator to publish it." : (await res.text()) || `Download failed (${res.status})`);
      const name = /filename="([^"]+)"/.exec(res.headers.get("Content-Disposition") ?? "")?.[1] ?? "document.pdf";
      return { blob: await res.blob(), name };
    },

    // ---------- Audit log ----------
    async auditLog() {
      const { data, error } = await sb.from("qms_audit_log").select("*").order("at", { ascending: false }).limit(1000);
      fail(error);
      const emails = await emailsFor(data.map((r) => r.user_id));
      return data.map((r) => ({ ...r, user_email: emails[r.user_id] ?? "" }));
    },

    // ---------- People and roles ----------
    listUsers: () => rpc("qms_list_users"),
    grantRole: (email, role, department, programme) => rpc("qms_grant_role", {
      p_email: email, p_role: role, p_department: department || null, p_programme: programme || null,
    }),
    revokeRole: (id) => rpc("qms_revoke_role", { p_id: id }),
  };
}

function friendly(msg) {
  if (/permission denied|row-level security/i.test(msg)) return "You do not have access to do that. " + msg;
  if (/JWT|invalid claim|session/i.test(msg)) return "Your session has expired. Sign in again.";
  if (/Failed to fetch/i.test(msg)) return "Cannot reach Supabase. Check the internet connection and the URL in config.js.";
  return msg;
}
