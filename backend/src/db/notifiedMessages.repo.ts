import { getFirestore } from "./firebase.js";

function notificationId(accountId: string, messageId: string) {
  return `${accountId}_${messageId}`.replace(/[^\w.-]/g, "_");
}

export async function claimNewEmailNotification(accountId: string, messageId: string) {
  const db = getFirestore();
  const ref = db.collection("notifiedMessages").doc(notificationId(accountId, messageId));

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.exists) {
      return false;
    }

    transaction.set(ref, {
      accountId,
      messageId,
      createdAt: new Date()
    });

    return true;
  });
}
