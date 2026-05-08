import { getGoogleAccountById, listGoogleAccounts } from "../db/accounts.repo.js";
import { listBlockedSenderEmails, filterBlockedEmails } from "../db/blockedSenders.repo.js";
import { listHiddenSenderEmails, filterHiddenEmails } from "../db/hiddenSenders.repo.js";
import {
  getLatestMorningBrief,
  getMorningBriefSettings,
  saveMorningBrief,
  type MorningBriefRecord
} from "../db/morningBrief.repo.js";
import { listEmailsInWindow } from "./gmail.service.js";
import { summarizeMorningBrief, type MorningBriefEmail } from "./ai.service.js";

function briefWindow(now: Date, lookbackHours: number) {
  const windowEnd = now;
  const windowStart = new Date(windowEnd.getTime() - lookbackHours * 60 * 60 * 1000);
  return { windowStart, windowEnd };
}

function totalActionableItems(summary: MorningBriefRecord["summary"]) {
  return summary.important.length + summary.needsAction.length + summary.deadlines.length;
}

export async function generateMorningBrief(input: { accountId?: string; now?: Date } = {}) {
  const settings = await getMorningBriefSettings();
  const { windowStart, windowEnd } = briefWindow(input.now ?? new Date(), settings.lookbackHours);

  const accountSummaries = input.accountId
    ? [{ id: input.accountId }]
    : await listGoogleAccounts();

  const emailGroups = await Promise.all(
    accountSummaries.map(async (summary) => {
      const account = await getGoogleAccountById(summary.id);
      if (!account) return [];

      const emails = await listEmailsInWindow(account, windowStart, windowEnd, { unreadOnly: settings.unreadOnly });
      const blockedSenderEmails = await listBlockedSenderEmails(account.id ?? summary.id);
      const hiddenSenderEmails = await listHiddenSenderEmails(account.id ?? summary.id);
      return filterHiddenEmails(filterBlockedEmails(emails, blockedSenderEmails), hiddenSenderEmails);
    })
  );

  const emails = emailGroups
    .flat()
    .sort((left, right) => Date.parse(right.receivedAt) - Date.parse(left.receivedAt))
    .slice(0, 80);

  const briefEmails: MorningBriefEmail[] = emails.map((email) => ({
    id: email.id,
    accountEmail: email.accountEmail,
    sender: email.sender,
    subject: email.subject,
    snippet: email.snippet,
    body: email.body,
    receivedAt: email.receivedAt
  }));

  const summary = await summarizeMorningBrief({
    emails: briefEmails,
    windowStart: windowStart.toISOString(),
    windowEnd: windowEnd.toISOString(),
    includeNewsletters: settings.includeNewsletters
  });

  const record = await saveMorningBrief({
    windowStart: windowStart.toISOString(),
    windowEnd: windowEnd.toISOString(),
    generatedAt: new Date().toISOString(),
    totalUnread: emails.length,
    ignoredCount: summary.ignored.length,
    settings,
    summary
  });

  return {
    brief: record,
    shouldNotify: !settings.onlyNotifyIfImportant || totalActionableItems(summary) > 0
  };
}

export async function latestMorningBrief() {
  return getLatestMorningBrief();
}
