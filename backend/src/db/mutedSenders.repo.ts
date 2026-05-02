import crypto from "node:crypto";
import { getFirestore } from "./firebase.js";
import { normalizeEmailAddress } from "./blockedSenders.repo.js";

function mutedSenderDocId(accountId: string, senderEmail: string) {
  return crypto
    .createHash("sha256")
    .update(`${accountId}:${senderEmail.toLowerCase()}`)
    .digest("hex");
}

function mutedSenderSuppressionDocId(accountId: string, senderEmail: string) {
  return mutedSenderDocId(accountId, senderEmail);
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
  await db.collection("mutedSenderNotificationSuppressions").doc(mutedSenderSuppressionDocId(input.accountId, senderEmail)).set(
    {
      accountId: input.accountId,
      senderEmail,
      suppressBefore: new Date(),
      updatedAt: new Date()
    },
    { merge: true }
  );
  return senderEmail;
}

export async function listMutedSenderNotificationSuppressions(accountId: string) {
  const db = getFirestore();
  const snapshot = await db
    .collection("mutedSenderNotificationSuppressions")
    .where("accountId", "==", accountId)
    .get();

  const suppressions = new Map<string, Date>();
  snapshot.docs.forEach((doc) => {
    const data = doc.data();
    const senderEmail = normalizeEmailAddress(String(data.senderEmail ?? ""));
    const rawDate = data.suppressBefore as { toDate?: () => Date } | Date | string | undefined;
    const suppressBefore =
      typeof rawDate === "string" ? new Date(rawDate) : rawDate instanceof Date ? rawDate : rawDate?.toDate?.();

    if (senderEmail && suppressBefore && !Number.isNaN(suppressBefore.getTime())) {
      suppressions.set(senderEmail, suppressBefore);
    }
  });

  return suppressions;
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

export function filterMutedSuppressedEmails<T extends { sender: string; receivedAt: string }>(
  emails: T[],
  suppressions: Map<string, Date>
) {
  if (suppressions.size === 0) {
    return emails;
  }

  return emails.filter((email) => {
    const suppressBefore = suppressions.get(normalizeEmailAddress(email.sender));
    if (!suppressBefore) {
      return true;
    }

    return Date.parse(email.receivedAt) > suppressBefore.getTime();
  });
}
