import type { Credentials } from "google-auth-library";
import { getFirestore } from "./firebase.js";
import { decryptText, encryptText } from "../security/tokenCrypto.js";

type GoogleProfile = {
  googleUserId: string;
  email: string;
  name: string | null;
  picture: string | null;
};

function decryptAccount(docId: string, data: FirebaseFirestore.DocumentData) {
  const encryptedRefreshToken = data.encryptedRefreshToken;

  if (typeof encryptedRefreshToken !== "string") {
    throw new Error("Connected Gmail account is missing a refresh token.");
  }

  return {
    id: docId,
    email: String(data.email),
    refreshToken: decryptText(encryptedRefreshToken),
    lastHistoryId: typeof data.lastHistoryId === "string" ? data.lastHistoryId : null
  };
}

export async function saveGoogleAccount(profile: GoogleProfile, tokens: Credentials) {
  if (!tokens.refresh_token) {
    throw new Error("Google did not return a refresh token. Re-consent is required.");
  }

  const db = getFirestore();
  const userRef = db.collection("users").doc(profile.googleUserId);
  const accountRef = db.collection("gmailAccounts").doc(profile.googleUserId);

  await userRef.set(
    {
      email: profile.email,
      name: profile.name,
      picture: profile.picture,
      updatedAt: new Date()
    },
    { merge: true }
  );

  await accountRef.set(
    {
      userId: profile.googleUserId,
      email: profile.email,
      provider: "gmail",
      encryptedRefreshToken: encryptText(tokens.refresh_token),
      scope: tokens.scope ?? null,
      tokenType: tokens.token_type ?? null,
      expiryDate: tokens.expiry_date ?? null,
      updatedAt: new Date()
    },
    { merge: true }
  );

  return {
    id: accountRef.id,
    email: profile.email,
    provider: "gmail"
  };
}

export async function getLatestGoogleAccount() {
  const db = getFirestore();
  const snapshot = await db
    .collection("gmailAccounts")
    .orderBy("updatedAt", "desc")
    .limit(1)
    .get();

  const doc = snapshot.docs[0];
  if (!doc) {
    return null;
  }

  return decryptAccount(doc.id, doc.data());
}

export async function listGoogleAccounts() {
  const db = getFirestore();
  const snapshot = await db
    .collection("gmailAccounts")
    .orderBy("updatedAt", "desc")
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      email: String(data.email),
      provider: String(data.provider ?? "gmail")
    };
  });
}

export async function getGoogleAccountById(accountId: string) {
  const db = getFirestore();
  const doc = await db.collection("gmailAccounts").doc(accountId).get();

  if (!doc.exists) {
    return null;
  }

  return decryptAccount(doc.id, doc.data() ?? {});
}

export async function getGoogleAccountByEmail(email: string) {
  const db = getFirestore();
  const snapshot = await db
    .collection("gmailAccounts")
    .where("email", "==", email)
    .limit(1)
    .get();

  const doc = snapshot.docs[0];
  if (!doc) {
    return null;
  }

  return decryptAccount(doc.id, doc.data());
}

export async function updateGmailWatchState(
  accountId: string,
  input: { historyId: string; expiration?: string | null }
) {
  const db = getFirestore();
  await db.collection("gmailAccounts").doc(accountId).set(
    {
      lastHistoryId: input.historyId,
      watchExpiration: input.expiration ?? null,
      watchUpdatedAt: new Date(),
      updatedAt: new Date()
    },
    { merge: true }
  );
}

export async function saveGmailSyncEvent(input: {
  accountId: string;
  email: string;
  historyId: string;
  messageIds: string[];
}) {
  const db = getFirestore();
  await db.collection("gmailSyncEvents").add({
    ...input,
    createdAt: new Date()
  });
}
