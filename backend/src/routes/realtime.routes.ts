import { Router } from "express";
import {
  getGoogleAccountByEmail,
  getGoogleAccountById,
  getLatestGoogleAccount,
  listGoogleAccounts,
  saveGmailSyncEvent,
  updateGmailWatchState
} from "../db/accounts.repo.js";
import { listGmailHistory, startGmailWatch } from "../services/gmail.service.js";

type PubSubPushBody = {
  message?: {
    data?: string;
    messageId?: string;
  };
};

export const realtimeRoutes = Router();

function decodePubSubData(data: string) {
  return JSON.parse(Buffer.from(data, "base64").toString("utf8")) as {
    emailAddress?: string;
    historyId?: string;
  };
}

realtimeRoutes.post("/gmail/watch", async (request, response, next) => {
  try {
    const accountId = typeof request.query.accountId === "string" ? request.query.accountId : undefined;
    if (!accountId) {
      const accounts = await listGoogleAccounts();
      const watches = [];

      for (const accountSummary of accounts) {
        const account = await getGoogleAccountById(accountSummary.id);
        if (!account) continue;

        const watch = await startGmailWatch(account);
        await updateGmailWatchState(account.id, watch);
        watches.push({ accountId: account.id, email: account.email, ...watch });
      }

      response.json({ ok: true, watches });
      return;
    }

    const account = accountId ? await getGoogleAccountById(accountId) : await getLatestGoogleAccount();
    if (!account) {
      response.status(401).json({ error: "No Gmail account connected." });
      return;
    }

    const watch = await startGmailWatch(account);
    await updateGmailWatchState(account.id, watch);

    response.json({ ok: true, watch });
  } catch (error) {
    next(error);
  }
});

realtimeRoutes.post("/webhook/gmail", async (request, response, next) => {
  try {
    const expectedSecret = process.env.GMAIL_WEBHOOK_SECRET;
    if (expectedSecret && request.query.secret !== expectedSecret) {
      response.status(401).json({ error: "Invalid webhook secret." });
      return;
    }

    const body = request.body as PubSubPushBody;
    const rawData = body.message?.data;

    if (!rawData) {
      response.status(204).send();
      return;
    }

    const notification = decodePubSubData(rawData);
    if (!notification.emailAddress || !notification.historyId) {
      response.status(204).send();
      return;
    }

    const account = await getGoogleAccountByEmail(notification.emailAddress);
    if (!account) {
      response.status(204).send();
      return;
    }

    const startHistoryId = account.lastHistoryId ?? notification.historyId;
    const history = await listGmailHistory(account, startHistoryId);

    await updateGmailWatchState(account.id, { historyId: history.historyId });
    await saveGmailSyncEvent({
      accountId: account.id,
      email: account.email,
      historyId: history.historyId,
      messageIds: history.messageIds
    });

    response.status(204).send();
  } catch (error) {
    next(error);
  }
});
