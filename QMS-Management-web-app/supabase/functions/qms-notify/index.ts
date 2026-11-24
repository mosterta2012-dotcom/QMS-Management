// qms-notify
// Sends waiting rows from qms_notification. Teams first, email as the fallback (briefing section 7).
// Run every 5 minutes (pg_cron + pg_net) or from a Database Webhook on INSERT into qms_notification.
//
// CONNECT TO THE EXISTING NPO MANAGEMENT SYSTEM NOTIFICATIONS:
// If the system already sends Teams or email messages, replace sendTeams/sendEmail with calls
// to that service. Otherwise set TEAMS_WEBHOOK_URL (a Teams Workflows webhook for a QMS channel)
// and/or RESEND_API_KEY + MAIL_FROM. Internal jobs (publish_pdf) are skipped: qms-publish handles them.
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

const APP_URL = Deno.env.get("APP_URL") ?? "";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.headers.get("x-qms-secret") !== Deno.env.get("QMS_FUNCTION_SECRET")) {
    return new Response("Forbidden", { status: 403, headers: cors });
  }
  const db = serviceClient();
  const { data: rows, error } = await db.from("qms_notification")
    .select("id, event, subject_id, message")
    .is("sent_at", null).neq("event", "publish_pdf").order("id").limit(50);
  if (error) return new Response(error.message, { status: 500 });

  let sent = 0;
  for (const n of rows ?? []) {
    try {
      const { data: people, error: pErr } = await db.rpc("qms_notification_recipients", { p_id: n.id });
      if (pErr) throw new Error(pErr.message);
      const emails: string[] = (people ?? []).map((p: { email: string }) => p.email).filter(Boolean);
      const link = APP_URL ? `${APP_URL.replace(/\/$/, "")}/#/item/${n.subject_id}` : "";
      const delivered = await sendTeams(n.message, emails, link) || await sendEmail(n.message, emails, link);
      if (!delivered) throw new Error("No channel configured or delivery failed");
      await db.from("qms_notification").update({ sent_at: new Date().toISOString(), error: null }).eq("id", n.id);
      sent++;
    } catch (e) {
      await db.from("qms_notification").update({ error: String(e) }).eq("id", n.id);
    }
  }
  return new Response(JSON.stringify({ sent }), { headers: { ...cors, "Content-Type": "application/json" } });
});

async function sendTeams(message: string, emails: string[], link: string): Promise<boolean> {
  const url = Deno.env.get("TEAMS_WEBHOOK_URL");
  if (!url || emails.length === 0) return false;
  const card = {
    type: "message",
    attachments: [{
      contentType: "application/vnd.microsoft.card.adaptive",
      content: {
        type: "AdaptiveCard", version: "1.4",
        body: [
          { type: "TextBlock", text: "QMS Management", weight: "Bolder" },
          { type: "TextBlock", text: message, wrap: true },
          { type: "TextBlock", text: emails.map((e) => `<at>${e}</at>`).join(" "), wrap: true },
        ],
        actions: link ? [{ type: "Action.OpenUrl", title: "Open", url: link }] : [],
        msteams: { entities: emails.map((e) => ({ type: "mention", text: `<at>${e}</at>`, mentioned: { id: e, name: e } })) },
      },
    }],
  };
  const res = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(card) });
  return res.ok;
}

async function sendEmail(message: string, emails: string[], link: string): Promise<boolean> {
  const key = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("MAIL_FROM");
  if (!key || !from || emails.length === 0) return false;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from, to: emails, subject: "QMS Management: " + message.slice(0, 80),
      text: message + (link ? `\n\nOpen: ${link}` : ""),
    }),
  });
  return res.ok;
}
