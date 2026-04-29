import type { Credentials } from "google-auth-library";
import { getFirestore } from "./firebase.js";
import { decryptText, encryptText } from "../security/tokenCrypto.js";

type GoogleProfile = {
  googleUserId: string;
  email: string;
  name: string | null;
  picture: string | null;
};

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

  const data = doc.data();
  const encryptedRefreshToken = data.encryptedRefreshToken;

  if (typeof encryptedRefreshToken !== "string") {
    throw new Error("Connected Gmail account is missing a refresh token.");
  }

  return {
    id: doc.id,
    email: String(data.email),
    refreshToken: decryptText(encryptedRefreshToken)
  };
}
