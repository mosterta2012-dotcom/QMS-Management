// qms-publish
// Publishes approved versions: takes the preview PDF the owner uploaded with the draft,
// stamps every page "CONTROLLED DOCUMENT" with code, version and approval date,
// saves it to qms-published/<document_id>/<version_id>.pdf, stores the SHA-256 hash,
// and marks the publish job done.
// The web app calls it after each approval. You can also run it from a Database Webhook on INSERT into qms_notification (event = 'publish_pdf'),
// or on a schedule (every 5 minutes) with pg_cron + pg_net. It processes all waiting jobs.
import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

// ---- Shared helpers (kept in this file so it can be pasted into the Supabase dashboard editor) ----

function serviceClient(): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } });
}
function userClient(req: Request): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false },
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
}
const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-qms-secret",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", bytes.slice().buffer as ArrayBuffer);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function saDate(d: Date = new Date()): string {
  return d.toLocaleDateString("en-ZA", { day: "2-digit", month: "short", year: "numeric", timeZone: "Africa/Johannesburg" });
}
// ---- end of shared helpers ----

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  // Callers: the scheduler or a webhook (shared secret), or a signed-in member of the
  // QMS group (the web app calls this straight after an approval). Either way the
  // function only publishes versions the database has already approved.
  const secret = Deno.env.get("QMS_FUNCTION_SECRET");
  let allowed = !!secret && req.headers.get("x-qms-secret") === secret;
  if (!allowed && req.headers.get("Authorization")) {
    const { data } = await userClient(req).rpc("qms_is_qms_group");
    allowed = data === true;
  }
  if (!allowed) return new Response("Forbidden", { status: 403, headers: cors });

  const db = serviceClient();
  const { data: jobs, error } = await db
    .from("qms_notification")
    .select("id, subject_id")
    .eq("event", "publish_pdf")
    .is("sent_at", null)
    .limit(20);
  if (error) return new Response(error.message, { status: 500, headers: cors });

  const results: unknown[] = [];
  for (const job of jobs ?? []) {
    try {
      const { data: v, error: vErr } = await db
        .from("qms_version")
        .select("id, document_id, version_no, pdf_path, approved_at, published_pdf_path, qms_document!qms_version_document_id_fkey(code, title, doc_class)")
        .eq("id", job.subject_id)
        .single();
      if (vErr || !v) throw new Error(vErr?.message ?? "Version not found");
      if (v.published_pdf_path) { await markDone(db, job.id); continue; }
      if (!v.pdf_path) throw new Error("No PDF was uploaded with this version (pdf_path is empty)");

      const { data: file, error: dErr } = await db.storage.from("qms-drafts").download(v.pdf_path);
      if (dErr || !file) throw new Error(dErr?.message ?? "Could not read the draft PDF");

      // deno-lint-ignore no-explicit-any
      const doc = (v as any).qms_document;
      const label = doc.doc_class === 1
        ? `CONTROLLED DOCUMENT  |  ${doc.code ?? ""}  |  Version ${v.version_no}  |  Approved ${saDate(new Date(v.approved_at))}`
        : `${doc.title}  |  Version ${v.version_no}  |  Approved ${saDate(new Date(v.approved_at))}`;

      const pdf = await PDFDocument.load(await file.arrayBuffer());
      const font = await pdf.embedFont(StandardFonts.HelveticaBold);
      for (const page of pdf.getPages()) {
        const { width, height } = page.getSize();
        page.drawText(label, { x: 36, y: height - 20, size: 8, font, color: rgb(0.12, 0.48, 0.4) });
        page.drawText("Angels Resource Centres NPO  -  current version only in the NPO Management System",
          { x: 36, y: 14, size: 7, font, color: rgb(0.4, 0.4, 0.4), maxWidth: width - 72 });
      }
      const bytes = await pdf.save();
      const path = `${v.document_id}/${v.id}.pdf`;
      const { error: uErr } = await db.storage.from("qms-published")
        .upload(path, bytes, { contentType: "application/pdf", upsert: false });
      if (uErr) throw new Error(uErr.message);

      const { error: rErr } = await db.rpc("qms_set_published_pdf",
        { p_version_id: v.id, p_path: path, p_sha256: await sha256Hex(bytes) });
      if (rErr) throw new Error(rErr.message);

      await markDone(db, job.id);
      results.push({ version: v.id, path });
    } catch (e) {
      await db.from("qms_notification").update({ error: String(e) }).eq("id", job.id);
      results.push({ job: job.id, error: String(e) });
    }
  }
  return new Response(JSON.stringify({ processed: results }), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});

// deno-lint-ignore no-explicit-any
async function markDone(db: any, id: number) {
  await db.from("qms_notification").update({ sent_at: new Date().toISOString(), error: null }).eq("id", id);
}
