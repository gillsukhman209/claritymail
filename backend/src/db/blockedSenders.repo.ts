import crypto from "node:crypto";
import { getFirestore } from "./firebase.js";

function blockedSenderDocId(accountId: string, senderEmail: string) {
  return crypto
    .createHash("sha256")
    .update(`${accountId}:${senderEmail.toLowerCase()}`)
    .digest("hex");
}

export function normalizeEmailAddress(value: string) {
  const trimmed = value.trim();
  const match = trimmed.match(/<([^>]+)>/);
  return (match?.[1] ?? trimmed).trim().toLowerCase();
}

export async function saveBlockedSender(input: { accountId: string; accountEmail: string; senderEmail: string }) {
  const senderEmail = normalizeEmailAddress(input.senderEmail);
  const db = getFirestore();

  await db.collection("blockedSenders").doc(blockedSenderDocId(input.accountId, senderEmail)).set(
    {
      accountId: input.accountId,
      accountEmail: input.accountEmail,
      senderEmail,
      createdAt: new Date(),
      updatedAt: new Date()
    },
    { merge: true }
  );

  return senderEmail;
}

export async function listBlockedSenderEmails(accountId: string) {
  const db = getFirestore();
  const snapshot = await db.collection("blockedSenders").where("accountId", "==", accountId).get();

  return new Set(
    snapshot.docs
      .map((doc) => normalizeEmailAddress(String(doc.data().senderEmail ?? "")))
      .filter(Boolean)
  );
}

export async function listBlockedSenders(accountId?: string) {
  const db = getFirestore();
  const query = accountId
    ? db.collection("blockedSenders").where("accountId", "==", accountId)
    : db.collection("blockedSenders");
  const snapshot = await query.get();

  return snapshot.docs
    .map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        accountId: String(data.accountId ?? ""),
        accountEmail: String(data.accountEmail ?? ""),
        senderEmail: normalizeEmailAddress(String(data.senderEmail ?? "")),
        createdAt: timestampDate(data.createdAt),
        updatedAt: timestampDate(data.updatedAt) ?? timestampDate(data.createdAt),
        sortAt: timestampMillis(data.updatedAt) || timestampMillis(data.createdAt)
      };
    })
    .sort((left, right) => right.sortAt - left.sortAt);
}

export async function deleteBlockedSender(input: { accountId: string; senderEmail: string }) {
  const senderEmail = normalizeEmailAddress(input.senderEmail);
  const db = getFirestore();
  await db.collection("blockedSenders").doc(blockedSenderDocId(input.accountId, senderEmail)).delete();
  return senderEmail;
}

export function filterBlockedEmails<T extends { sender: string }>(emails: T[], blockedSenders: Set<string>) {
  if (blockedSenders.size === 0) {
    return emails;
  }

  return emails.filter((email) => !blockedSenders.has(normalizeEmailAddress(email.sender)));
}

export function applyBlockedSenderState<T extends { sender: string }>(emails: T[], blockedSenders: Set<string>) {
  return emails.map((email) => ({
    ...email,
    isBlockedSender: blockedSenders.has(normalizeEmailAddress(email.sender))
  }));
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
