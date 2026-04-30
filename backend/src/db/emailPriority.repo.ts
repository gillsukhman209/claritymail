import crypto from "node:crypto";
import { getFirestore } from "./firebase.js";

export type PriorityStatus = "important" | "normal" | "ignored";
export type PrioritySource = "manual_sender" | "ai" | "rules" | "gmail";

export type EmailPriorityRecord = {
  accountId: string;
  emailId: string;
  senderEmail: string;
  status: PriorityStatus;
  source: PrioritySource;
  reason: string;
  classifierVersion: number;
};

function priorityDocId(accountId: string, emailId: string) {
  return crypto
    .createHash("sha256")
    .update(`${accountId}:${emailId}`)
    .digest("hex");
}

export async function getEmailPriority(accountId: string, emailId: string) {
  const doc = await getFirestore().collection("emailPriority").doc(priorityDocId(accountId, emailId)).get();
  if (!doc.exists) return null;
  const data = doc.data() ?? {};

  return {
    accountId: String(data.accountId ?? accountId),
    emailId: String(data.emailId ?? emailId),
    senderEmail: String(data.senderEmail ?? ""),
    status: (data.status === "important" || data.status === "ignored" ? data.status : "normal") as PriorityStatus,
    source: (data.source === "manual_sender" || data.source === "rules" || data.source === "gmail" ? data.source : "ai") as PrioritySource,
    reason: String(data.reason ?? ""),
    classifierVersion: Number(data.classifierVersion ?? 0)
  };
}

export async function saveEmailPriority(record: EmailPriorityRecord) {
  await getFirestore().collection("emailPriority").doc(priorityDocId(record.accountId, record.emailId)).set(
    {
      ...record,
      createdAt: new Date(),
      updatedAt: new Date()
    },
    { merge: true }
  );

  return record;
}
