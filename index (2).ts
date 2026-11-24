// qms-download
// GET /functions/v1/qms-download?document_id=<uuid>
// Checks the signed-in user may read the document (qms_can_read_document, same rule as RLS),
// then returns the published PDF stamped "Uncontrolled copy when printed or downloaded" with
// today's date (CR-2026-001 A11; briefing section 6). Downloads are written to the audit log.
import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";
import { cors, saDate, serviceClient, userClient } from "../_shared/clients.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const documentId = new URL(req.url).searchParams.get("document_id");
  if (!documentId) return new Response("document_id is required", { status: 400, headers: cors });

  const asUser = userClient(req);
  const { data: user } = await asUser.auth.getUser();
  if (!user?.user) return new Response("Sign in first", { status: 401, headers: cors });

  const { data: allowed, error: aErr } = await asUser.rpc("qms_can_read_document", { p_document_id: documentId });
  if (aErr || allowed !== true) return new Response("Not allowed", { status: 403, headers: cors });

  const db = serviceClient();
  const { data: d, error: dErr } = await db.from("qms_document")
    .select("code, title, published_version_id, qms_version!qms_document_published_fk(version_no, published_pdf_path)")
    .eq("id", documentId).single();
  // deno-lint-ignore no-explicit-any
  const v = (d as any)?.qms_version;
  if (dErr || !v?.published_pdf_path) return new Response("Not published yet", { status: 404, headers: cors });

  const { data: file, error: fErr } = await db.storage.from("qms-published").download(v.published_pdf_path);
  if (fErr || !file) return new Response("File not found", { status: 404, headers: cors });

  const pdf = await PDFDocument.load(await file.arrayBuffer());
  const font = await pdf.embedFont(StandardFonts.HelveticaBold);
  const stamp = `UNCONTROLLED COPY WHEN PRINTED OR DOWNLOADED  -  ${saDate()}`;
  for (const page of pdf.getPages()) {
    const { width } = page.getSize();
    page.drawText(stamp, { x: 36, y: 26, size: 8, font, color: rgb(0.75, 0, 0), maxWidth: width - 72 });
  }
  const bytes = await pdf.save();

  await db.from("qms_audit_log").insert({
    user_id: user.user.id, action: "download", table_name: "qms_document",
    record_id: documentId, version_no: v.version_no,
  });

  const name = `${d!.code ?? d!.title} v${v.version_no} (uncontrolled).pdf`.replace(/[^\w .()-]/g, "_");
  return new Response(bytes.slice().buffer as ArrayBuffer, {
    headers: { ...cors, "Content-Type": "application/pdf", "Content-Disposition": `attachment; filename="${name}"` },
  });
});
