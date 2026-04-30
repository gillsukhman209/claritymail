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
  deleteImportantSender,
  listImportantSenderEmails,
  listImportantSenders,
  saveImportantSender
} from "../db/importantSenders.repo.js";
import {
  archiveEmail,
  blockSenderInGmail,
  createDraft,
  deleteDraft,
  getEmail,
  getEmailAttachment,
  getThread,
  listMailboxEmails,
  markEmailRead,
  markEmailUnread,
  type MailboxFolder,
  type EmailAttachment,
  replyToEmail,
  sendEmail,
  sendDraft,
  starEmail,
  trashEmail,
  updateDraft,
  unblockSenderInGmail,
  unstarEmail
} from "../services/gmail.service.js";
import { summarizeEmail } from "../services/ai.service.js";
import { enrichEmailsWithPriority, senderDisplayName, sortPriorityEmails } from "../services/priority.service.js";

export const emailRoutes = Router();

function mailboxFolderFromQuery(value: unknown): MailboxFolder {
  return value === "sent" || value === "archive" || value === "trash" || value === "drafts" ? value : "inbox";
}

const maxAttachmentBytes = 25 * 1024 * 1024;

function attachmentByteCount(attachments: EmailAttachment[] = []) {
  return attachments.reduce((total, attachment) => total + Buffer.from(attachment.data, "base64").length, 0);
}

function encodePageState(state: Record<string, string | null | undefined>) {
  const cleaned = Object.fromEntries(Object.entries(state).filter((entry): entry is [string, string] => Boolean(entry[1])));
  if (Object.keys(cleaned).length === 0) return null;
  return Buffer.from(JSON.stringify(cleaned), "utf8").toString("base64url");
}

function decodePageState(value: unknown): Record<string, string> {
  if (typeof value !== "string" || !value) return {};
  try {
    return JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
  } catch {
    return {};
  }
}

function validateSendBody(
  response: import("express").Response,
  body: { to?: string; body?: string; htmlBody?: string; attachments?: EmailAttachment[] }
) {
  if (!body.to || (!body.body && !body.htmlBody)) {
    response.status(400).json({ error: "Missing to or body." });
    return false;
  }

  if (attachmentByteCount(body.attachments) > maxAttachmentBytes) {
    response.status(400).json({ error: "Gmail attachments cannot exceed 25 MB total." });
    return false;
  }

  return true;
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
    const priorityOnly = request.query.priorityOnly === "true" || request.query.priorityOnly === "1";
    const pageState = decodePageState(request.query.pageToken);

    if (accountId) {
      const account = await getGoogleAccountById(accountId);
      if (!account) {
        response.status(401).json({ error: "No Gmail account connected." });
        return;
      }

      const result = await listMailboxEmails(account, { query, folder, pageToken: pageState[accountId] });
      const blockedFilteredEmails = filterBlockedEmails(result.emails, await listBlockedSenderEmails(account.id ?? accountId));
      const emailsWithPriority = await enrichEmailsWithPriority(
        account.id ?? accountId,
        blockedFilteredEmails,
        await listImportantSenderEmails(account.id ?? accountId)
      );
      const emails = priorityOnly
        ? sortPriorityEmails(emailsWithPriority.filter((email: any) => email.priorityStatus === "important"))
        : sortNewestFirst(emailsWithPriority);

      response.json({
        emails,
        nextPageToken: encodePageState({ [accountId]: result.nextPageToken })
      });
      return;
    }

    const accounts = await listGoogleAccounts();
    const emailGroups = await Promise.all(
      accounts.map(async (accountSummary) => {
        const account = await getGoogleAccountById(accountSummary.id);
        if (!account) {
          return { emails: [], accountId: accountSummary.id, nextPageToken: null };
        }

        const result = await listMailboxEmails(account, { query, folder, pageToken: pageState[accountSummary.id] });
        const blockedFilteredEmails = filterBlockedEmails(
          result.emails,
          await listBlockedSenderEmails(account.id ?? accountSummary.id)
        );
        const emailsWithPriority = await enrichEmailsWithPriority(
          account.id ?? accountSummary.id,
          blockedFilteredEmails,
          await listImportantSenderEmails(account.id ?? accountSummary.id)
        );

        return {
          emails: priorityOnly
            ? emailsWithPriority.filter((email: any) => email.priorityStatus === "important")
            : emailsWithPriority,
          accountId: accountSummary.id,
          nextPageToken: result.nextPageToken
        };
      })
    );

    const emails = (priorityOnly
      ? sortPriorityEmails(emailGroups.flatMap((group) => group.emails))
      : sortNewestFirst(emailGroups.flatMap((group) => group.emails))
    ).slice(0, 50);

    response.json({
      emails,
      nextPageToken: encodePageState(
        Object.fromEntries(emailGroups.map((group) => [group.accountId, group.nextPageToken]))
      )
    });
  } catch (error) {
    next(error);
  }
});

function sortNewestFirst<T extends { receivedAt: string }>(emails: T[]) {
  return emails.sort((left, right) => Date.parse(right.receivedAt) - Date.parse(left.receivedAt));
}

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

emailRoutes.get("/threads/:threadId", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    response.json({ emails: await getThread(account, request.params.threadId) });
  } catch (error) {
    next(error);
  }
});

emailRoutes.get("/emails/:id/attachments/:attachmentId", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    const attachment = await getEmailAttachment(account, request.params.id, request.params.attachmentId);
    response.json({ attachment });
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

    const { to, subject, body, htmlBody, attachments } = request.body as {
      to?: string;
      subject?: string;
      body?: string;
      htmlBody?: string;
      attachments?: EmailAttachment[];
    };

    if (!validateSendBody(response, { to, body, htmlBody, attachments })) return;

    const result = await sendEmail(account, { to: to!, subject, body: body ?? "", htmlBody, attachments });
    response.json({ ok: true, message: result });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/reply", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    const { to, subject, body, htmlBody, threadId, attachments } = request.body as {
      to?: string;
      subject?: string;
      body?: string;
      htmlBody?: string;
      threadId?: string;
      attachments?: EmailAttachment[];
    };

    if (!to || (!body && !htmlBody) || !threadId) {
      response.status(400).json({ error: "Missing to, body, or threadId." });
      return;
    }
    if (!validateSendBody(response, { to, body, htmlBody, attachments })) return;

    const result = await replyToEmail(account, { to, subject, body: body ?? "", htmlBody, threadId, attachments });
    response.json({ ok: true, message: result });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/drafts", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    const { to, subject, body, htmlBody, attachments, threadId } = request.body as {
      to?: string;
      subject?: string;
      body?: string;
      htmlBody?: string;
      attachments?: EmailAttachment[];
      threadId?: string;
    };

    if (attachmentByteCount(attachments) > maxAttachmentBytes) {
      response.status(400).json({ error: "Gmail attachments cannot exceed 25 MB total." });
      return;
    }

    const draft = await createDraft(account, {
      to: to ?? "",
      subject: subject ?? "",
      body: body ?? "",
      htmlBody,
      attachments,
      threadId
    });
    response.json({ draft });
  } catch (error) {
    next(error);
  }
});

emailRoutes.put("/drafts/:draftId", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    const { to, subject, body, htmlBody, attachments, threadId } = request.body as {
      to?: string;
      subject?: string;
      body?: string;
      htmlBody?: string;
      attachments?: EmailAttachment[];
      threadId?: string;
    };

    if (attachmentByteCount(attachments) > maxAttachmentBytes) {
      response.status(400).json({ error: "Gmail attachments cannot exceed 25 MB total." });
      return;
    }

    const draft = await updateDraft(account, request.params.draftId, {
      to: to ?? "",
      subject: subject ?? "",
      body: body ?? "",
      htmlBody,
      attachments,
      threadId
    });
    response.json({ draft });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/drafts/:draftId/send", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    const { to, subject, body, htmlBody, attachments, threadId } = request.body as {
      to?: string;
      subject?: string;
      body?: string;
      htmlBody?: string;
      attachments?: EmailAttachment[];
      threadId?: string;
    };

    if (!validateSendBody(response, { to, body, htmlBody, attachments })) return;

    const result = await sendDraft(account, request.params.draftId, {
      to: to ?? "",
      subject: subject ?? "",
      body: body ?? "",
      htmlBody,
      attachments,
      threadId
    });
    response.json({ ok: true, message: result });
  } catch (error) {
    next(error);
  }
});

emailRoutes.delete("/drafts/:draftId", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    await deleteDraft(account, request.params.draftId);
    response.json({ ok: true });
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

emailRoutes.post("/emails/:id/important-sender", async (request, response, next) => {
  try {
    const account = await requireSelectedAccount(request, response);
    if (!account) return;

    if (!account.id || !account.email) {
      response.status(400).json({ error: "Connected Gmail account is missing account metadata." });
      return;
    }

    const email = await getEmail(account, request.params.id);
    const senderEmail = normalizeEmailAddress(email.sender);

    await saveImportantSender({
      accountId: account.id,
      accountEmail: account.email,
      senderEmail,
      senderName: senderDisplayName(email.sender)
    });

    response.json({ ok: true, senderEmail });
  } catch (error) {
    next(error);
  }
});

emailRoutes.get("/important-senders", async (request, response, next) => {
  try {
    const accountId = typeof request.query.accountId === "string" ? request.query.accountId : undefined;
    response.json({ importantSenders: await listImportantSenders(accountId) });
  } catch (error) {
    next(error);
  }
});

emailRoutes.delete("/important-senders", async (request, response, next) => {
  try {
    const accountId = typeof request.query.accountId === "string" ? request.query.accountId : undefined;
    const senderEmail =
      typeof request.query.senderEmail === "string" ? normalizeEmailAddress(request.query.senderEmail) : undefined;

    if (!accountId || !senderEmail) {
      response.status(400).json({ error: "Missing accountId or senderEmail." });
      return;
    }

    await deleteImportantSender({ accountId, senderEmail });
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
