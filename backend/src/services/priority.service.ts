import { getEmailPriority, saveEmailPriority, type EmailPriorityRecord } from "../db/emailPriority.repo.js";
import { normalizeEmailAddress } from "../db/blockedSenders.repo.js";
import { classifyEmailPriorityBatch } from "./ai.service.js";

const PRIORITY_CLASSIFIER_VERSION = 3;

type EmailLike = {
  accountId?: string;
  id: string;
  sender: string;
  subject: string;
  snippet: string;
  body?: string;
  receivedAt: string;
};

const promoTerms = [
  "money-saving",
  "take advantage",
  "discount",
  "coupon",
  "promo",
  "promotion",
  "sale",
  "offer",
  "deal",
  "rewards",
  "earn",
  "cashback",
  "free credits",
  "credits are yours",
  "claim your",
  "activate my credits",
  "pre-qualification",
  "prequalification",
  "pre-qualified",
  "prequalified",
  "newsletter",
  "unsubscribe",
  "limited time",
  "price drop",
  "recommended for you",
  "new delivery opportunities",
  "blocks are available",
  "off the waitlist",
  "waitlist",
  "download our latest report",
  "latest report",
  "shared intel",
  "tools, signals",
  "stay ahead",
  "hurry",
  "finish signing up",
  "sign up",
  "welcome to",
  "added 10 free credits",
  "use however you like"
];

const importantPatterns: Array<{ pattern: RegExp; reason: string }> = [
  { pattern: /\bappointment\b|\bscheduled appointment\b/, reason: "Appointment or scheduled event" },
  { pattern: /\bdirect deposit\b|\bcredited to your account\b|\bdeposit was credited\b/, reason: "Account activity" },
  { pattern: /\bpayment due\b|\bpast due\b|\bfailed payment\b|\boverdue\b|\binvoice due\b/, reason: "Payment or billing item" },
  { pattern: /\bsecurity alert\b|\bsuspicious sign[- ]?in\b|\bverify your identity\b|\bpassword reset\b|\bunauthorized\b/, reason: "Account security item" },
  { pattern: /\binsurance claim\b|\bclaim adjuster\b|\bclaim number\b/, reason: "Insurance or claim item" },
  { pattern: /\blegal\b|\bmedical\b|\blab results\b|\btest results\b/, reason: "Medical or legal item" },
  { pattern: /\bdeadline\b|\baction required\b|\burgent\b/, reason: "Time-sensitive action" }
];

function visibleText(email: EmailLike) {
  return `${email.sender} ${email.subject} ${email.snippet}`.toLowerCase();
}

function ruleClassify(email: EmailLike): Pick<EmailPriorityRecord, "status" | "source" | "reason"> | null {
  const text = visibleText(email);

  if (promoTerms.some((term) => text.includes(term))) {
    return { status: "ignored", source: "rules", reason: "Promotional or low-priority email" };
  }

  const importantMatch = importantPatterns.find((item) => item.pattern.test(text));
  if (importantMatch) {
    return { status: "important", source: "rules", reason: importantMatch.reason };
  }

  return null;
}

export function senderDisplayName(sender: string) {
  const match = sender.match(/^"?([^"<]+)"?\s*</);
  return match?.[1]?.trim() ?? "";
}

export async function enrichEmailsWithPriority<T extends EmailLike>(
  accountId: string,
  emails: T[],
  importantSenderEmails: Set<string>
): Promise<T[]> {
  const enriched = await Promise.all(
    emails.map(async (email) => {
      const senderEmail = normalizeEmailAddress(email.sender);
      if (importantSenderEmails.has(senderEmail)) {
        return {
          ...email,
          priorityStatus: "important",
          prioritySource: "manual_sender",
          priorityReason: "Important sender"
        };
      }

      const cached = await getEmailPriority(accountId, email.id);
      if (cached && cached.classifierVersion === PRIORITY_CLASSIFIER_VERSION) {
        return {
          ...email,
          priorityStatus: cached.status,
          prioritySource: cached.source,
          priorityReason: cached.reason
        };
      }

      const rules = ruleClassify(email);
      if (rules) {
        await saveEmailPriority({
          accountId,
          emailId: email.id,
          senderEmail,
          status: rules.status,
          source: rules.source,
          reason: rules.reason,
          classifierVersion: PRIORITY_CLASSIFIER_VERSION
        });
        return {
          ...email,
          priorityStatus: rules.status,
          prioritySource: rules.source,
          priorityReason: rules.reason
        };
      }

      return { ...email, priorityStatus: "pending", prioritySource: "rules", priorityReason: "" };
    })
  );

  const pending = enriched.filter((email: any) => email.priorityStatus === "pending");
  if (pending.length > 0) {
    const classifications = await classifyEmailPriorityBatch({ emails: pending });
    const byId = new Map(classifications.map((item) => [item.id, item]));

    await Promise.all(
      pending.map(async (email: any) => {
        const classification = byId.get(email.id) ?? { id: email.id, status: "normal" as const, reason: "" };
        await saveEmailPriority({
          accountId,
          emailId: email.id,
          senderEmail: normalizeEmailAddress(email.sender),
          status: classification.status,
          source: "ai",
          reason: classification.reason,
          classifierVersion: PRIORITY_CLASSIFIER_VERSION
        });
      })
    );

    return enriched.map((email: any) => {
      if (email.priorityStatus !== "pending") return email;
      const classification = byId.get(email.id) ?? { status: "normal", reason: "" };
      return {
        ...email,
        priorityStatus: classification.status,
        prioritySource: "ai",
        priorityReason: classification.reason
      };
    });
  }

  return enriched;
}

export function applyImportantSenderPriority<T extends EmailLike>(
  emails: T[],
  importantSenderEmails: Set<string>
): T[] {
  return emails.map((email) => {
    const senderEmail = normalizeEmailAddress(email.sender);
    if (!importantSenderEmails.has(senderEmail)) {
      return email;
    }

    return {
      ...email,
      priorityStatus: "important",
      prioritySource: "manual_sender",
      priorityReason: "Important sender"
    };
  });
}

export function sortPriorityEmails<T extends EmailLike & { priorityStatus?: string; prioritySource?: string }>(emails: T[]) {
  return emails.sort((left, right) => {
    const leftScore = priorityScore(left);
    const rightScore = priorityScore(right);
    if (leftScore !== rightScore) return rightScore - leftScore;
    return Date.parse(right.receivedAt) - Date.parse(left.receivedAt);
  });
}

function priorityScore(email: { priorityStatus?: string; prioritySource?: string }) {
  if (email.priorityStatus !== "important") return 0;
  if (email.prioritySource === "manual_sender") return 3;
  return 2;
}
