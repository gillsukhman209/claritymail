import admin from "firebase-admin";

function requireEnv(name: string) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

export function getFirestore() {
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: requireEnv("FIREBASE_PROJECT_ID"),
        clientEmail: requireEnv("FIREBASE_CLIENT_EMAIL"),
        privateKey: requireEnv("FIREBASE_PRIVATE_KEY").replace(/\\n/g, "\n")
      })
    });
  }

  return admin.firestore();
}
