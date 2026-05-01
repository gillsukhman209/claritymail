import crypto from "node:crypto";
import { getFirestore } from "./firebase.js";

function pinnedEmailDocId(accountId: string, emailId: string) {
  return crypto
    .createHash("sha256")
    .update(`${accountId}:${emailId}`)
    .digest("hex");
}

export async function savePinnedEmail(input: {
  accountId: string;
  accountEmail: string;
  emailId: string;
  threadId?: string;
  subject?: string;
  sender?: string;
  receivedAt?: string;
}) {
  const db = getFirestore();
  await db.collection("pinnedEmails").doc(pinnedEmailDocId(input.accountId, input.emailId)).set(
    {
      accountId: input.accountId,
      accountEmail: input.accountEmail,
      emailId: input.emailId,
      threadId: input.threadId ?? "",
      subject: input.subject ?? "",
      sender: input.sender ?? "",
      receivedAt: input.receivedAt ?? null,
      createdAt: new Date(),
      updatedAt: new Date()
    },
    { merge: true }
  );
}

export async function deletePinnedEmail(input: { accountId: string; emailId: string }) {
  const db = getFirestore();
  await db.collection("pinnedEmails").doc(pinnedEmailDocId(input.accountId, input.emailId)).delete();
}

export async function listPinnedEmailIds(accountId: string) {
  const db = getFirestore();
  const snapshot = await db.collection("pinnedEmails").where("accountId", "==", accountId).get();
  return new Set(snapshot.docs.map((doc) => String(doc.data().emailId ?? "")).filter(Boolean));
}
