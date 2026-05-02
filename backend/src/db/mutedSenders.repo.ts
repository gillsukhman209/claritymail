import crypto from "node:crypto";
import { getFirestore } from "./firebase.js";
import { normalizeEmailAddress } from "./blockedSenders.repo.js";

function mutedSenderDocId(accountId: string, senderEmail: string) {
  return crypto
    .createHash("sha256")
    .update(`${accountId}:${senderEmail.toLowerCase()}`)
    .digest("hex");
}

export type MutedSenderRecord = {
  id: string;
  accountId: string;
  accountEmail: string;
  senderEmail: string;
  senderName: string;
};

export async function saveMutedSender(input: {
  accountId: string;
  accountEmail: string;
  senderEmail: string;
  senderName?: string;
}) {
  const senderEmail = normalizeEmailAddress(input.senderEmail);
  const db = getFirestore();

  await db.collection("mutedSenders").doc(mutedSenderDocId(input.accountId, senderEmail)).set(
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

export async function listMutedSenderEmails(accountId: string) {
  const db = getFirestore();
  const snapshot = await db.collection("mutedSenders").where("accountId", "==", accountId).get();

  return new Set(
    snapshot.docs
      .map((doc) => normalizeEmailAddress(String(doc.data().senderEmail ?? "")))
      .filter(Boolean)
  );
}

export async function listMutedSenders(accountId?: string): Promise<MutedSenderRecord[]> {
  const db = getFirestore();
  const query = accountId
    ? db.collection("mutedSenders").where("accountId", "==", accountId)
    : db.collection("mutedSenders");
  const snapshot = await query.get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      accountId: String(data.accountId ?? ""),
      accountEmail: String(data.accountEmail ?? ""),
      senderEmail: normalizeEmailAddress(String(data.senderEmail ?? "")),
      senderName: String(data.senderName ?? "")
    };
  });
}

export async function deleteMutedSender(input: { accountId: string; senderEmail: string }) {
  const senderEmail = normalizeEmailAddress(input.senderEmail);
  const db = getFirestore();
  await db.collection("mutedSenders").doc(mutedSenderDocId(input.accountId, senderEmail)).delete();
  return senderEmail;
}

export function applyMutedSenderState<T extends { sender: string }>(emails: T[], mutedSenders: Set<string>) {
  return emails.map((email) => ({
    ...email,
    isMutedSender: mutedSenders.has(normalizeEmailAddress(email.sender))
  }));
}

export function filterMutedEmails<T extends { sender: string }>(emails: T[], mutedSenders: Set<string>) {
  if (mutedSenders.size === 0) {
    return emails;
  }

  return emails.filter((email) => !mutedSenders.has(normalizeEmailAddress(email.sender)));
}
