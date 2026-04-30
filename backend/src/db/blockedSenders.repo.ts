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

export function filterBlockedEmails<T extends { sender: string }>(emails: T[], blockedSenders: Set<string>) {
  if (blockedSenders.size === 0) {
    return emails;
  }

  return emails.filter((email) => !blockedSenders.has(normalizeEmailAddress(email.sender)));
}
