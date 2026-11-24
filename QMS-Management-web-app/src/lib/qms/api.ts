// QMS Management tab: thin wrappers over the database functions and views.
// Every rule (no self-approval, comment on return, Board resolution, version numbers,
// visibility) is enforced in the database, so the screens only call these and show
// the error message the database returns.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { ChangeType, DocClass, DocType, LibraryItem, MyApproval, QmsDocument, QmsVersion } from "./types";

const DRAFTS = "qms-drafts";

export function qmsApi(sb: SupabaseClient) {
  const rpc = async <T = unknown>(fn: string, args: Record<string, unknown>) => {
    const { data, error } = await sb.rpc(fn, args);
    if (error) throw new Error(error.message);
    return data as T;
  };

  return {
    /** Show the QMS Management menu item only when this is true. */
    isQmsGroup: () => rpc<boolean>("qms_is_qms_group", {}),

    // ---------- Screen 1: Documents ----------
    async listDocuments(filter: { search?: string; status?: string; department?: string; docClass?: DocClass } = {}) {
      let q = sb.from("qms_document").select("*").order("code", { nullsFirst: false });
      if (filter.search) q = q.or(`code.ilike.%${filter.search}%,title.ilike.%${filter.search}%,process.ilike.%${filter.search}%`);
      if (filter.status) q = q.eq("status", filter.status);
      if (filter.department) q = q.eq("department", filter.department);
      if (filter.docClass) q = q.eq("doc_class", filter.docClass);
      const { data, error } = await q;
      if (error) throw new Error(error.message);
      return data as QmsDocument[];
    },

    // ---------- Screen 2: Document details ----------
    async getDocument(id: string) {
      const { data: doc, error } = await sb.from("qms_document").select("*").eq("id", id).single();
      if (error) throw new Error(error.message);
      const { data: versions } = await sb.from("qms_version").select("*").eq("document_id", id).order("draft_seq", { ascending: false });
      const { data: steps } = await sb.from("qms_approval_step").select("*")
        .in("version_id", (versions ?? []).map((v) => v.id)).order("created_at");
      return { doc: doc as QmsDocument, versions: (versions ?? []) as QmsVersion[], steps: steps ?? [] };
    },

    /** Upload Word + PDF for a draft. Files go to qms-drafts/<document>/<version>/. */
    async uploadDraftFiles(documentId: string, versionId: string, word: File, pdf: File) {
      const base = `${documentId}/${versionId}`;
      const up = async (name: string, f: File) => {
        const { error } = await sb.storage.from(DRAFTS).upload(`${base}/${name}`, f, { upsert: false });
        if (error) throw new Error(error.message);
        return `${base}/${name}`;
      };
      const source_path = await up("source.docx", word);
      const pdf_path = await up("preview.pdf", pdf);
      const { error } = await sb.from("qms_version").update({ source_path, pdf_path }).eq("id", versionId);
      if (error) throw new Error(error.message);
    },

    createDocument: (a: {
      title: string; docClass: DocClass; docType: DocType; department: string; ownerRole: string;
      code?: string; domain?: string; process?: string; programme?: string;
      isGovernance?: boolean; isCrossDepartment?: boolean; visibleTo?: string[];
    }) => rpc<string>("qms_create_document", {
      p_title: a.title, p_doc_class: a.docClass, p_doc_type: a.docType, p_department: a.department,
      p_owner_role: a.ownerRole, p_code: a.code ?? null, p_domain: a.domain ?? null, p_process: a.process ?? null,
      p_programme: a.programme ?? null, p_is_governance: a.isGovernance ?? false,
      p_is_cross_department: a.isCrossDepartment ?? false, p_visible_to: a.visibleTo ?? ["all_staff"],
    }),

    newDraft: (documentId: string, changeSummary: string, isSignificant = false, changeRequestId?: string) =>
      rpc<string>("qms_new_draft", {
        p_document_id: documentId, p_source_path: null, p_change_summary: changeSummary,
        p_is_significant: isSignificant, p_change_request_id: changeRequestId ?? null,
      }),

    submit: (versionId: string) => rpc("qms_submit", { p_version_id: versionId }),
    sendForApproval: (versionId: string) => rpc("qms_send_for_approval", { p_version_id: versionId }),
    returnDoc: (versionId: string, comment: string) => rpc("qms_return", { p_version_id: versionId, p_comment: comment }),

    // ---------- Screen 3 and 4: Approvals and Board resolution ----------
    async myApprovals() {
      const { data, error } = await sb.from("qms_my_approvals").select("*").order("submitted_at");
      if (error) throw new Error(error.message);
      return data as MyApproval[];
    },
    async checkQueue() {
      const { data, error } = await sb.from("qms_check_queue").select("*").order("submitted_at");
      if (error) throw new Error(error.message);
      return data;
    },
    approve: (versionId: string, changeType: ChangeType = "Major", nextReviewDate?: string) =>
      rpc<string>("qms_approve", { p_version_id: versionId, p_change_type: changeType, p_next_review_date: nextReviewDate ?? null }),

    async approveWithBoardResolution(documentId: string, versionId: string, resolution: File, resolutionNo: string, resolutionDate: string) {
      const path = `${documentId}/${versionId}/board-resolution.pdf`;
      const { error } = await sb.storage.from(DRAFTS).upload(path, resolution, { upsert: false });
      if (error) throw new Error(error.message);
      return rpc<string>("qms_approve", {
        p_version_id: versionId, p_change_type: "Major", p_board_resolution_path: path,
        p_board_resolution_no: resolutionNo, p_board_resolution_date: resolutionDate,
      });
    },

    withdraw: (documentId: string, reason: string) => rpc("qms_withdraw", { p_document_id: documentId, p_reason: reason }),
    extendReview: (documentId: string, newDate: string, reason: string) =>
      rpc("qms_extend_review", { p_document_id: documentId, p_new_date: newDate, p_reason: reason }),
    markReviewed: (documentId: string) => rpc("qms_mark_reviewed", { p_document_id: documentId }),
    acknowledge: (versionId: string) => rpc("qms_acknowledge", { p_version_id: versionId }),
    logChangeRequest: (title: string, significance: "Minor" | "Significant") =>
      rpc<string>("qms_log_change_request", { p_title: title, p_significance: significance }),

    // ---------- Screen 5: Document Control library ----------
    async library(search?: string) {
      let q = sb.from("qms_library").select("*").order("code");
      if (search) q = q.or(`code.ilike.%${search}%,title.ilike.%${search}%,process.ilike.%${search}%`);
      const { data, error } = await q;
      if (error) throw new Error(error.message);
      return data as LibraryItem[];
    },
    /** URL for the stamped "Uncontrolled copy" download (needs the user's session token). */
    downloadUrl: (functionsUrl: string, documentId: string) => `${functionsUrl}/qms-download?document_id=${documentId}`,

    // ---------- Screen 6: Audit log ----------
    async auditLog(recordId?: string) {
      let q = sb.from("qms_audit_log").select("*").order("at", { ascending: false }).limit(500);
      if (recordId) q = q.eq("record_id", recordId);
      const { data, error } = await q;
      if (error) throw new Error(error.message);
      return data;
    },

    // ---------- Screen 8 (Release 2): Reviews due ----------
    async reviewsDue() {
      const { data, error } = await sb.from("qms_reviews_due").select("*").order("next_review_date");
      if (error) throw new Error(error.message);
      return data;
    },
  };
}
