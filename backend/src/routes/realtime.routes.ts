import { Router } from "express";
import {
  getGoogleAccountByEmail,
  getGoogleAccountById,
  getLatestGoogleAccount,
  listGoogleAccounts,
  saveGmailSyncEvent,
  updateGmailWatchState
} from "../db/accounts.repo.js";
import { saveDeviceToken } from "../db/deviceTokens.repo.js";
import { listBlockedSenderEmails, filterBlockedEmails } from "../db/blockedSenders.repo.js";
import { filterHiddenEmails, listHiddenSenderEmails } from "../db/hiddenSenders.repo.js";
import {
  filterMutedEmails,
  filterMutedSuppressedEmails,
  listMutedSenderEmails,
  listMutedSenderNotificationSuppressions
} from "../db/mutedSenders.repo.js";
import { claimNewEmailNotification } from "../db/notifiedMessages.repo.js";
import { getEmail, getUnreadInboxEstimate, listGmailHistory, startGmailWatch } from "../services/gmail.service.js";
import { notifyDevicesForEmail } from "../services/apns.service.js";

type PubSubPushBody = {
  message?: {
    data?: string;
    messageId?: string;
  };
};

export const realtimeRoutes = Router();

const maxNotificationAgeMs = 10 * 60 * 1000;

function decodePubSubData(data: string) {
  return JSON.parse(Buffer.from(data, "base64").toString("utf8")) as {
    emailAddress?: string;
    historyId?: string;
  };
}

function isFreshUnreadEmail(email: any) {
  return !email.isRead && Date.now() - Date.parse(email.receivedAt) <= maxNotificationAgeMs;
}

async function totalUnreadInboxCount() {
  const accounts = await listGoogleAccounts();
  const counts = await Promise.all(
    accounts.map(async (accountSummary) => {
      const account = await getGoogleAccountById(accountSummary.id);
      if (!account) return 0;

      try {
        return await getUnreadInboxEstimate(account);
      } catch {
        return 0;
      }
    })
  );

  return counts.reduce((total, count) => total + count, 0);
}

async function notifyFreshInboxMessages(account: NonNullable<Awaited<ReturnType<typeof getGoogleAccountById>>>, messageIds: string[]) {
  if (messageIds.length === 0) return;

  const blockedSenders = await listBlockedSenderEmails(account.id);
  const hiddenSenders = await listHiddenSenderEmails(account.id);
  const mutedSenders = await listMutedSenderEmails(account.id);
  const mutedSuppressions = await listMutedSenderNotificationSuppressions(account.id);
  const emails = await Promise.all(
    messageIds.slice(0, 5).map(async (messageId) => {
      try {
        return await getEmail(account, messageId);
      } catch {
        return null;
      }
    })
  );

  const notifyableEmails = filterMutedSuppressedEmails(
      filterMutedEmails(
        filterHiddenEmails(
          filterBlockedEmails(
            emails.filter((email): email is NonNullable<typeof email> => Boolean(email)),
            blockedSenders
          ),
          hiddenSenders
        ),
        mutedSenders
      ),
    mutedSuppressions
  ).filter(isFreshUnreadEmail);

  if (notifyableEmails.length === 0) return;

  const badgeCount = await totalUnreadInboxCount();
  const claimedEmails = [];
  for (const email of notifyableEmails) {
    if (await claimNewEmailNotification(account.id, email.id)) {
      claimedEmails.push(email);
    }
  }

  await Promise.all(claimedEmails.map((email) => notifyDevicesForEmail(email, badgeCount)));
}

realtimeRoutes.post("/devices/register", async (request, response, next) => {
  try {
    const body = request.body as {
      token?: unknown;
      platform?: unknown;
      environment?: unknown;
      notificationSound?: unknown;
    };

    const token = typeof body.token === "string" ? body.token.trim() : "";
    const platform = body.platform === "macos" ? "macos" : "ios";
    const environment = body.environment === "production" ? "production" : "sandbox";
    const notificationSound =
      typeof body.notificationSound === "string" && body.notificationSound.endsWith(".wav")
        ? body.notificationSound
        : "ClarityMailChime.wav";

    if (!token) {
      response.status(400).json({ error: "Missing device token." });
      return;
    }

    const device = await saveDeviceToken({ token, platform, environment, notificationSound });
    response.json({ ok: true, deviceId: device.id });
  } catch (error) {
    next(error);
  }
});

realtimeRoutes.get("/sync/status", async (_request, response, next) => {
  try {
    response.json({
      ok: true,
      unreadInboxCount: await totalUnreadInboxCount(),
      checkedAt: new Date().toISOString()
    });
  } catch (error) {
    next(error);
  }
});

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

realtimeRoutes.get("/cron/gmail-watch", async (request, response, next) => {
  try {
    const expectedSecret = process.env.CRON_SECRET;
    if (expectedSecret && request.query.secret !== expectedSecret && request.headers.authorization !== `Bearer ${expectedSecret}`) {
      response.status(401).json({ error: "Invalid cron secret." });
      return;
    }

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
    let history: Awaited<ReturnType<typeof listGmailHistory>>;

    try {
      history = await listGmailHistory(account, startHistoryId);
    } catch {
      const watch = await startGmailWatch(account);
      await updateGmailWatchState(account.id, watch);
      response.status(204).send();
      return;
    }

    await updateGmailWatchState(account.id, { historyId: history.historyId });
    await saveGmailSyncEvent({
      accountId: account.id,
      email: account.email,
      historyId: history.historyId,
      messageIds: history.messageIds
    });

    await notifyFreshInboxMessages(account, history.messageIds);

    response.status(204).send();
  } catch (error) {
    next(error);
  }
});
