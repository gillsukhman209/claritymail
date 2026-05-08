import type { Credentials } from "google-auth-library";
import { getFirestore } from "./firebase.js";
import { decryptText, encryptText } from "../security/tokenCrypto.js";

type GoogleProfile = {
  googleUserId: string;
  email: string;
  name: string | null;
  picture: string | null;
};

type GoogleAccount = {
  id: string;
  email: string;
  refreshToken: string;
  lastHistoryId: string | null;
};

type GoogleAccountSummary = {
  id: string;
  email: string;
  provider: string;
  isConnected: boolean;
  connectionError: string | null;
  connectionCheckedAt: string | null;
};

const accountCacheTtlMs = 5 * 60 * 1000;
let accountCacheUpdatedAt = 0;
let accountSummariesCache: GoogleAccountSummary[] | null = null;
let accountSummariesCacheIsComplete = false;
const accountDetailsCache = new Map<string, GoogleAccount>();
const accountEmailIndex = new Map<string, string>();

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

function isAccountCacheFresh() {
  return accountSummariesCacheIsComplete && accountSummariesCache && Date.now() - accountCacheUpdatedAt < accountCacheTtlMs;
}

function rememberAccount(account: GoogleAccount, provider = "gmail") {
  accountDetailsCache.set(account.id, account);
  accountEmailIndex.set(account.email.toLowerCase(), account.id);

  if (accountSummariesCacheIsComplete && accountSummariesCache) {
    const existing = accountSummariesCache.find((cached) => cached.id === account.id);
    const summary = {
      id: account.id,
      email: account.email,
      provider,
      isConnected: existing?.isConnected ?? true,
      connectionError: existing?.connectionError ?? null,
      connectionCheckedAt: existing?.connectionCheckedAt ?? null
    };
    accountSummariesCache = [
      summary,
      ...accountSummariesCache.filter((cached) => cached.id !== account.id)
    ];
    accountCacheUpdatedAt = Date.now();
  }
}

function rememberSummaries(summaries: GoogleAccountSummary[]) {
  accountSummariesCache = summaries;
  accountSummariesCacheIsComplete = true;
  accountCacheUpdatedAt = Date.now();
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
      isConnected: true,
      connectionError: null,
      connectionCheckedAt: new Date(),
      updatedAt: new Date()
    },
    { merge: true }
  );

  const summary = {
    id: accountRef.id,
    email: profile.email,
    provider: "gmail",
    isConnected: true,
    connectionError: null,
    connectionCheckedAt: new Date().toISOString()
  };
  accountSummariesCache = null;
  accountSummariesCacheIsComplete = false;
  rememberAccount({
    id: accountRef.id,
    email: profile.email,
    refreshToken: tokens.refresh_token,
    lastHistoryId: null
  });

  return summary;
}

export async function getLatestGoogleAccount() {
  if (isAccountCacheFresh() && accountSummariesCache?.[0]) {
    return getGoogleAccountById(accountSummariesCache[0].id);
  }

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

  const account = decryptAccount(doc.id, doc.data());
  rememberAccount(account);
  return account;
}

export async function listGoogleAccounts() {
  if (isAccountCacheFresh() && accountSummariesCache) {
    return accountSummariesCache;
  }

  const db = getFirestore();
  const snapshot = await db
    .collection("gmailAccounts")
    .orderBy("updatedAt", "desc")
    .get();

  const summaries = snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      email: String(data.email),
      provider: String(data.provider ?? "gmail"),
      isConnected: data.isConnected !== false,
      connectionError: typeof data.connectionError === "string" ? data.connectionError : null,
      connectionCheckedAt: data.connectionCheckedAt?.toDate?.().toISOString?.() ?? null
    };
  });
  rememberSummaries(summaries);
  return summaries;
}

export async function getGoogleAccountById(accountId: string) {
  const cached = accountDetailsCache.get(accountId);
  if (cached) {
    return cached;
  }

  const db = getFirestore();
  const doc = await db.collection("gmailAccounts").doc(accountId).get();

  if (!doc.exists) {
    return null;
  }

  const account = decryptAccount(doc.id, doc.data() ?? {});
  rememberAccount(account, String(doc.data()?.provider ?? "gmail"));
  return account;
}

export async function getGoogleAccountByEmail(email: string) {
  const cachedId = accountEmailIndex.get(email.toLowerCase());
  if (cachedId) {
    const cached = accountDetailsCache.get(cachedId);
    if (cached) {
      return cached;
    }
  }

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

  const account = decryptAccount(doc.id, doc.data());
  rememberAccount(account, String(doc.data().provider ?? "gmail"));
  return account;
}

export async function deleteGoogleAccount(accountId: string) {
  const db = getFirestore();
  await db.collection("gmailAccounts").doc(accountId).delete();
  const cached = accountDetailsCache.get(accountId);
  if (cached) {
  accountEmailIndex.delete(cached.email.toLowerCase());
  }
  accountDetailsCache.delete(accountId);
  accountSummariesCache = accountSummariesCache?.filter((account) => account.id !== accountId) ?? null;
  accountSummariesCacheIsComplete = Boolean(accountSummariesCache);
}

function updateCachedConnectionState(
  accountId: string,
  input: { isConnected: boolean; connectionError: string | null; connectionCheckedAt: string }
) {
  if (!accountSummariesCache) return;
  accountSummariesCache = accountSummariesCache.map((account) =>
    account.id === accountId ? { ...account, ...input } : account
  );
}

export async function markGoogleAccountConnected(accountId: string) {
  const checkedAt = new Date();
  const db = getFirestore();
  await db.collection("gmailAccounts").doc(accountId).set(
    {
      isConnected: true,
      connectionError: null,
      connectionCheckedAt: checkedAt
    },
    { merge: true }
  );
  updateCachedConnectionState(accountId, {
    isConnected: true,
    connectionError: null,
    connectionCheckedAt: checkedAt.toISOString()
  });
}

export async function markGoogleAccountConnectionError(accountId: string, error: unknown) {
  const checkedAt = new Date();
  const message = error instanceof Error ? error.message : String(error);
  const db = getFirestore();
  await db.collection("gmailAccounts").doc(accountId).set(
    {
      isConnected: false,
      connectionError: message.slice(0, 300),
      connectionCheckedAt: checkedAt
    },
    { merge: true }
  );
  updateCachedConnectionState(accountId, {
    isConnected: false,
    connectionError: message.slice(0, 300),
    connectionCheckedAt: checkedAt.toISOString()
  });
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

  const cached = accountDetailsCache.get(accountId);
  if (cached) {
    accountDetailsCache.set(accountId, { ...cached, lastHistoryId: input.historyId });
  }
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
