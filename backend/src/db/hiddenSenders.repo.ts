import crypto from "node:crypto";
import { getFirestore } from "./firebase.js";
import { normalizeEmailAddress } from "./blockedSenders.repo.js";

function hiddenSenderDocId(accountId: string, senderEmail: string) {
  return crypto
    .createHash("sha256")
    .update(`${accountId}:${senderEmail.toLowerCase()}`)
    .digest("hex");
}

export async function saveHiddenSender(input: {
  accountId: string;
  accountEmail: string;
  senderEmail: string;
  senderName?: string;
}) {
  const senderEmail = normalizeEmailAddress(input.senderEmail);
  const db = getFirestore();

  await db.collection("hiddenSenders").doc(hiddenSenderDocId(input.accountId, senderEmail)).set(
    {
      accountId: input.accountId,
      accountEmail: input.accountEmail,
      senderEmail,
      senderName: input.senderName ?? "",
      createdAt: new Date(),
      updatedAt: new Date()
    },
    { merge: true }
  );

  return senderEmail;
}

export async function listHiddenSenderEmails(accountId: string) {
  const db = getFirestore();
  const snapshot = await db.collection("hiddenSenders").where("accountId", "==", accountId).get();

  return new Set(
    snapshot.docs
      .map((doc) => normalizeEmailAddress(String(doc.data().senderEmail ?? "")))
      .filter(Boolean)
  );
}

export async function listHiddenSenders(accountId?: string) {
  const db = getFirestore();
  const query = accountId
    ? db.collection("hiddenSenders").where("accountId", "==", accountId)
    : db.collection("hiddenSenders");
  const snapshot = await query.get();

  return snapshot.docs
    .map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        accountId: String(data.accountId ?? ""),
        accountEmail: String(data.accountEmail ?? ""),
        senderEmail: normalizeEmailAddress(String(data.senderEmail ?? "")),
        senderName: String(data.senderName ?? ""),
        createdAt: timestampDate(data.createdAt),
        updatedAt: timestampDate(data.updatedAt) ?? timestampDate(data.createdAt),
        sortAt: timestampMillis(data.updatedAt) || timestampMillis(data.createdAt)
      };
    })
    .sort((left, right) => right.sortAt - left.sortAt);
}

export async function deleteHiddenSender(input: { accountId: string; senderEmail: string }) {
  const senderEmail = normalizeEmailAddress(input.senderEmail);
  const db = getFirestore();
  await db.collection("hiddenSenders").doc(hiddenSenderDocId(input.accountId, senderEmail)).delete();
  return senderEmail;
}

export function applyHiddenSenderState<T extends { sender: string }>(emails: T[], hiddenSenders: Set<string>) {
  return emails.map((email) => ({
    ...email,
    isHiddenSender: hiddenSenders.has(normalizeEmailAddress(email.sender))
  }));
}

export function filterHiddenEmails<T extends { sender: string }>(emails: T[], hiddenSenders: Set<string>) {
  if (hiddenSenders.size === 0) {
    return emails;
  }

  return emails.filter((email) => !hiddenSenders.has(normalizeEmailAddress(email.sender)));
}

export function onlyHiddenEmails<T extends { sender: string }>(emails: T[], hiddenSenders: Set<string>) {
  if (hiddenSenders.size === 0) {
    return [];
  }

  return emails.filter((email) => hiddenSenders.has(normalizeEmailAddress(email.sender)));
}

function timestampDate(value: unknown): string | null {
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
  }
  if (value && typeof value === "object" && "toDate" in value && typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  return null;
}

function timestampMillis(value: unknown) {
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
  if (value && typeof value === "object" && "toDate" in value && typeof value.toDate === "function") {
    return value.toDate().getTime();
  }
  return 0;
}
