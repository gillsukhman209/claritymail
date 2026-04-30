import crypto from "node:crypto";
import { getFirestore } from "./firebase.js";
import { normalizeEmailAddress } from "./blockedSenders.repo.js";

function importantSenderDocId(accountId: string, senderEmail: string) {
  return crypto
    .createHash("sha256")
    .update(`${accountId}:${senderEmail.toLowerCase()}`)
    .digest("hex");
}

export type ImportantSenderRecord = {
  id: string;
  accountId: string;
  accountEmail: string;
  senderEmail: string;
  senderName: string;
};

export async function saveImportantSender(input: {
  accountId: string;
  accountEmail: string;
  senderEmail: string;
  senderName?: string;
}) {
  const senderEmail = normalizeEmailAddress(input.senderEmail);
  const db = getFirestore();

  await db.collection("importantSenders").doc(importantSenderDocId(input.accountId, senderEmail)).set(
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

export async function listImportantSenderEmails(accountId: string) {
  const db = getFirestore();
  const snapshot = await db.collection("importantSenders").where("accountId", "==", accountId).get();

  return new Set(
    snapshot.docs
      .map((doc) => normalizeEmailAddress(String(doc.data().senderEmail ?? "")))
      .filter(Boolean)
  );
}

export async function listImportantSenders(accountId?: string): Promise<ImportantSenderRecord[]> {
  const db = getFirestore();
  const query = accountId
    ? db.collection("importantSenders").where("accountId", "==", accountId)
    : db.collection("importantSenders");
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

export async function deleteImportantSender(input: { accountId: string; senderEmail: string }) {
  const senderEmail = normalizeEmailAddress(input.senderEmail);
  const db = getFirestore();
  await db.collection("importantSenders").doc(importantSenderDocId(input.accountId, senderEmail)).delete();
  return senderEmail;
}

