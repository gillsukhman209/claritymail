import { Router } from "express";

export const legalRoutes = Router();

const updatedDate = "May 10, 2026";

function page(title: string, body: string) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${title} - ClarityMail</title>
    <style>
      :root {
        color-scheme: light;
        --bg: #f5efe5;
        --text: #161310;
        --muted: #6f675d;
        --line: rgba(22, 19, 16, 0.16);
        --accent: #be3c14;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        background: var(--bg);
        color: var(--text);
        font-family: ui-serif, Georgia, Cambria, "Times New Roman", Times, serif;
        line-height: 1.6;
      }
      main {
        width: min(820px, calc(100% - 40px));
        margin: 0 auto;
        padding: 64px 0 88px;
      }
      header {
        border-bottom: 1px solid var(--line);
        margin-bottom: 40px;
        padding-bottom: 24px;
      }
      .brand {
        color: var(--muted);
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0.22em;
        text-transform: uppercase;
      }
      h1 {
        font-size: clamp(42px, 8vw, 84px);
        line-height: 0.95;
        margin: 28px 0 16px;
        letter-spacing: 0;
      }
      h2 {
        border-top: 1px solid var(--line);
        font-size: 22px;
        margin: 34px 0 12px;
        padding-top: 24px;
      }
      p, li {
        color: var(--muted);
        font-size: 17px;
      }
      strong { color: var(--text); }
      a { color: var(--accent); }
      ul { padding-left: 22px; }
      .updated {
        color: var(--muted);
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0.16em;
        text-transform: uppercase;
      }
    </style>
  </head>
  <body>
    <main>
      <header>
        <div class="brand">ClarityMail</div>
        <h1>${title}</h1>
        <div class="updated">Last updated ${updatedDate}</div>
      </header>
      ${body}
    </main>
  </body>
</html>`;
}

legalRoutes.get("/", (_request, response) => {
  response.type("html").send(page("A calmer way to experience email", `
    <p>ClarityMail is an AI-powered Gmail client for iOS and macOS. It helps users read, search, summarize, organize, and send email through the Gmail API.</p>
    <p><a href="/privacy">Privacy Policy</a> · <a href="/terms">Terms of Service</a></p>
  `));
});

legalRoutes.get("/privacy", (_request, response) => {
  response.type("html").send(page("Privacy Policy", `
    <p>This Privacy Policy explains how ClarityMail handles information when you connect your Gmail account and use the app.</p>

    <h2>Information We Access</h2>
    <p>With your permission, ClarityMail accesses Gmail account information, message metadata, message content, labels, drafts, and settings needed to provide email features such as inbox sync, reading, search, sending, drafts, archive, trash, blocking senders, and AI summaries.</p>

    <h2>How We Use Gmail Data</h2>
    <ul>
      <li>To display and sync your email inside ClarityMail.</li>
      <li>To send, reply, forward, archive, trash, mark, draft, and organize messages at your request.</li>
      <li>To create Gmail filters when you block a sender.</li>
      <li>To generate optional AI summaries and morning briefs.</li>
      <li>To send notifications for new email and configured summaries.</li>
    </ul>

    <h2>AI Processing</h2>
    <p>When you request an AI summary or when Morning Brief is enabled, relevant email content may be sent to OpenAI to generate a summary. ClarityMail does not use Gmail data to train general AI models.</p>

    <h2>Data Sharing</h2>
    <p>We do not sell Gmail data. We do not use Gmail data for advertising. We only share data with service providers needed to operate ClarityMail, such as hosting, database, notification, and AI processing providers.</p>

    <h2>Data Storage</h2>
    <p>Refresh tokens are encrypted at rest. ClarityMail stores the minimum data needed to keep accounts connected, sync email state, provide notifications, and remember user preferences.</p>

    <h2>Limited Use</h2>
    <p>ClarityMail's use and transfer of information received from Google APIs adheres to the Google API Services User Data Policy, including the Limited Use requirements.</p>

    <h2>Deleting Your Data</h2>
    <p>You can remove a connected Gmail account inside ClarityMail settings. This deletes the stored token for that account and stops ClarityMail from accessing that Gmail account. For additional deletion requests, contact support.</p>

    <h2>Contact</h2>
    <p>For privacy questions, contact: <a href="mailto:gillsukhman209@gmail.com">gillsukhman209@gmail.com</a></p>
  `));
});

legalRoutes.get("/terms", (_request, response) => {
  response.type("html").send(page("Terms of Service", `
    <p>These Terms govern your use of ClarityMail.</p>

    <h2>Use of ClarityMail</h2>
    <p>ClarityMail is provided to help you access, organize, summarize, and send email through your connected Gmail account. You are responsible for how you use the app and for the content you send.</p>

    <h2>Google Account Access</h2>
    <p>ClarityMail only accesses Gmail data after you grant permission through Google OAuth. You can revoke access from your Google Account permissions or remove the account inside ClarityMail.</p>

    <h2>AI Features</h2>
    <p>AI summaries and briefs may be incomplete or inaccurate. You should review original emails before making important decisions.</p>

    <h2>Availability</h2>
    <p>ClarityMail may change, pause, or stop features as the product develops. We aim to keep the service reliable, but we do not guarantee uninterrupted availability.</p>

    <h2>Acceptable Use</h2>
    <p>Do not use ClarityMail to send spam, abuse, illegal content, malware, or content that violates applicable laws or email provider policies.</p>

    <h2>Contact</h2>
    <p>For questions about these Terms, contact: <a href="mailto:gillsukhman209@gmail.com">gillsukhman209@gmail.com</a></p>
  `));
});
