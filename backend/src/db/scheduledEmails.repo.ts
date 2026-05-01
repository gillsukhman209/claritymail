import { getFirestore } from "./firebase.js";
import type { EmailAttachment } from "../services/gmail.service.js";

export type ScheduledEmailPayload = {
  to: string;
  cc?: string;
  bcc?: string;
  subject?: string;
  body: string;
  htmlBody?: string;
  threadId?: string | null;
  attachments?: EmailAttachment[];
};

export type ScheduledEmailRecord = {
  id: string;
  accountId: string;
  accountEmail: string;
  payload: ScheduledEmailPayload;
  sendAt: Date;
  status: "scheduled" | "sending" | "sent" | "failed" | "cancelled";
};

function removeUndefinedValues<T>(value: T): T {
  if (Array.isArray(value)) {
    return value.map((item) => removeUndefinedValues(item)) as T;
  }

  if (value && typeof value === "object" && !(value instanceof Date)) {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([, entryValue]) => entryValue !== undefined)
        .map(([key, entryValue]) => [key, removeUndefinedValues(entryValue)])
    ) as T;
  }

  return value;
}

export async function saveScheduledEmail(input: {
  accountId: string;
  accountEmail: string;
  payload: ScheduledEmailPayload;
  sendAt: Date;
}) {
  const db = getFirestore();
  const ref = await db.collection("scheduledEmails").add({
    accountId: input.accountId,
    accountEmail: input.accountEmail,
    payload: removeUndefinedValues(input.payload),
    sendAt: input.sendAt,
    status: "scheduled",
    createdAt: new Date(),
    updatedAt: new Date()
  });

  return { id: ref.id, sendAt: input.sendAt.toISOString() };
}

export async function listDueScheduledEmails(now = new Date(), limit = 20): Promise<ScheduledEmailRecord[]> {
  const db = getFirestore();
  const snapshot = await db
    .collection("scheduledEmails")
    .where("status", "==", "scheduled")
    .get();

  return snapshot.docs
    .map((doc) => {
      const data = doc.data();
      const sendAtValue = data.sendAt;
      const sendAt =
        typeof sendAtValue?.toDate === "function"
          ? sendAtValue.toDate()
          : sendAtValue instanceof Date
            ? sendAtValue
            : new Date(String(sendAtValue));

      return {
        id: doc.id,
        accountId: String(data.accountId ?? ""),
        accountEmail: String(data.accountEmail ?? ""),
        payload: data.payload as ScheduledEmailPayload,
        sendAt,
        status: String(data.status ?? "scheduled") as ScheduledEmailRecord["status"]
      };
    })
    .filter((email) => email.sendAt.getTime() <= now.getTime())
    .sort((left, right) => left.sendAt.getTime() - right.sendAt.getTime())
    .slice(0, limit);
}

export async function updateScheduledEmailStatus(
  id: string,
  status: ScheduledEmailRecord["status"],
  errorMessage?: string
) {
  const db = getFirestore();
  const update: Record<string, unknown> = {
    status,
    errorMessage: errorMessage ?? null,
    updatedAt: new Date()
  };
  if (status === "sent") {
    update.sentAt = new Date();
  }

  await db.collection("scheduledEmails").doc(id).set(update, { merge: true });
}
