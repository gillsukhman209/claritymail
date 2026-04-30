import { Router } from "express";
import { getGoogleAccountById, getLatestGoogleAccount, listGoogleAccounts } from "../db/accounts.repo.js";
import {
  deleteBlockedSender,
  filterBlockedEmails,
  listBlockedSenderEmails,
  listBlockedSenders,
  normalizeEmailAddress,
  saveBlockedSender
} from "../db/blockedSenders.repo.js";
import {
  archiveEmail,
  blockSenderInGmail,
  getEmail,
  listMailboxEmails,
  markEmailRead,
  markEmailUnread,
  type MailboxFolder,
  replyToEmail,
  sendEmail,
  starEmail,
  trashEmail,
  unblockSenderInGmail,
  unstarEmail
} from "../services/gmail.service.js";
import { summarizeEmail } from "../services/ai.service.js";

export const emailRoutes = Router();

function mailboxFolderFromQuery(value: unknown): MailboxFolder {
  return value === "sent" || value === "archive" || value === "trash" ? value : "inbox";
}

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
    const folder = mailboxFolderFromQuery(request.query.folder);

    if (accountId) {
      const account = await getGoogleAccountById(accountId);
      if (!account) {
        response.status(401).json({ error: "No Gmail account connected." });
        return;
      }

      const emails = filterBlockedEmails(
        await listMailboxEmails(account, { query, folder }),
        await listBlockedSenderEmails(account.id ?? accountId)
      );
      response.json({ emails });
      return;
    }

    const accounts = await listGoogleAccounts();
    const emailGroups = await Promise.all(
      accounts.map(async (accountSummary) => {
        const account = await getGoogleAccountById(accountSummary.id);
        if (!account) {
          return [];
        }

        return filterBlockedEmails(
          await listMailboxEmails(account, { query, folder }),
          await listBlockedSenderEmails(account.id ?? accountSummary.id)
        );
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

emailRoutes.post("/emails/:id/summary", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    const email = await getEmail(account, request.params.id);
    const summary = await summarizeEmail({
      subject: email.subject,
      sender: email.sender,
      body: email.body || email.snippet
    });

    response.json({ summary });
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

emailRoutes.post("/emails/:id/block-sender", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    if (!account.id || !account.email) {
      response.status(400).json({ error: "Connected Gmail account is missing account metadata." });
      return;
    }

    const email = await getEmail(account, request.params.id);
    const senderEmail = normalizeEmailAddress(email.sender);

    await saveBlockedSender({
      accountId: account.id,
      accountEmail: account.email,
      senderEmail
    });

    await blockSenderInGmail(account, senderEmail);

    response.json({ ok: true, senderEmail });
  } catch (error) {
    next(error);
  }
});

emailRoutes.get("/blocked-senders", async (request, response, next) => {
  try {
    const accountId = typeof request.query.accountId === "string" ? request.query.accountId : undefined;
    response.json({ blockedSenders: await listBlockedSenders(accountId) });
  } catch (error) {
    next(error);
  }
});

emailRoutes.delete("/blocked-senders", async (request, response, next) => {
  try {
    const accountId = typeof request.query.accountId === "string" ? request.query.accountId : undefined;
    const senderEmail =
      typeof request.query.senderEmail === "string" ? normalizeEmailAddress(request.query.senderEmail) : undefined;

    if (!accountId || !senderEmail) {
      response.status(400).json({ error: "Missing accountId or senderEmail." });
      return;
    }

    const account = await getGoogleAccountById(accountId);
    if (!account) {
      response.status(401).json({ error: "No Gmail account connected." });
      return;
    }

    await unblockSenderInGmail(account, senderEmail);
    await deleteBlockedSender({ accountId, senderEmail });

    response.json({ ok: true, senderEmail });
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
