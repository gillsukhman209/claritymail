import { Router } from "express";
import { getGoogleAccountById, getLatestGoogleAccount, listGoogleAccounts } from "../db/accounts.repo.js";
import {
  archiveEmail,
  getEmail,
  listInboxEmails,
  markEmailRead,
  markEmailUnread,
  replyToEmail,
  sendEmail,
  starEmail,
  trashEmail,
  unstarEmail
} from "../services/gmail.service.js";

export const emailRoutes = Router();

async function requireSelectedAccount(request: import("express").Request, response: import("express").Response) {
  const body = request.body as { accountId?: unknown } | undefined;
  const accountId =
    typeof request.query.accountId === "string"
      ? request.query.accountId
      : typeof body?.accountId === "string"
        ? body.accountId
        : undefined;

  const account = accountId ? await getGoogleAccountById(accountId) : await getLatestGoogleAccount();

  if (!account) {
    response.status(401).json({ error: "No Gmail account connected." });
    return null;
  }

  return account;
}

emailRoutes.get("/emails", async (request, response, next) => {
  try {
    const query = typeof request.query.q === "string" ? request.query.q : undefined;
    const accountId = typeof request.query.accountId === "string" ? request.query.accountId : undefined;

    if (accountId) {
      const account = await getGoogleAccountById(accountId);
      if (!account) {
        response.status(401).json({ error: "No Gmail account connected." });
        return;
      }

      const emails = await listInboxEmails(account, { query });
      response.json({ emails });
      return;
    }

    const accounts = await listGoogleAccounts();
    const emailGroups = await Promise.all(
      accounts.map(async (accountSummary) => {
        const account = await getGoogleAccountById(accountSummary.id);
        return account ? listInboxEmails(account, { query }) : [];
      })
    );

    const emails = emailGroups
      .flat()
      .sort((left, right) => Date.parse(right.receivedAt) - Date.parse(left.receivedAt))
      .slice(0, 50);

    response.json({ emails });
  } catch (error) {
    next(error);
  }
});

emailRoutes.get("/emails/:id", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    const email = await getEmail(account, request.params.id);
    response.json({ email });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/archive", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    await archiveEmail(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/send", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    const { to, subject, body } = request.body as { to?: string; subject?: string; body?: string };

    if (!to || !subject || !body) {
      response.status(400).json({ error: "Missing to, subject, or body." });
      return;
    }

    const result = await sendEmail(account, { to, subject, body });
    response.json({ ok: true, message: result });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/reply", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    const { to, subject, body, threadId } = request.body as {
      to?: string;
      subject?: string;
      body?: string;
      threadId?: string;
    };

    if (!to || !subject || !body || !threadId) {
      response.status(400).json({ error: "Missing to, subject, body, or threadId." });
      return;
    }

    const result = await replyToEmail(account, { to, subject, body, threadId });
    response.json({ ok: true, message: result });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/trash", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    await trashEmail(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/read", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    await markEmailRead(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/unread", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    await markEmailUnread(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/star", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    await starEmail(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/unstar", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    await unstarEmail(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});
