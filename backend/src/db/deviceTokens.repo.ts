import crypto from "node:crypto";
import { getFirestore } from "./firebase.js";

export type DevicePlatform = "ios" | "macos";
export type DeviceEnvironment = "sandbox" | "production";

export type DeviceTokenRecord = {
  id: string;
  token: string;
  platform: DevicePlatform;
  environment: DeviceEnvironment;
};

function deviceTokenId(token: string) {
  return crypto.createHash("sha256").update(token).digest("hex");
}

export async function saveDeviceToken(input: {
  token: string;
  platform: DevicePlatform;
  environment: DeviceEnvironment;
}) {
  const id = deviceTokenId(input.token);
  await getFirestore().collection("deviceTokens").doc(id).set(
    {
      ...input,
      id,
      updatedAt: new Date()
    },
    { merge: true }
  );

  return { id, ...input };
}

export async function listDeviceTokens(environment?: DeviceEnvironment): Promise<DeviceTokenRecord[]> {
  let query: FirebaseFirestore.Query = getFirestore().collection("deviceTokens");
  if (environment) {
    query = query.where("environment", "==", environment);
  }

  const snapshot = await query.get();
  return snapshot.docs.map((doc): DeviceTokenRecord => {
    const data = doc.data();
    const platform: DevicePlatform = data.platform === "macos" ? "macos" : "ios";
    const environment: DeviceEnvironment = data.environment === "production" ? "production" : "sandbox";
    return {
      id: String(data.id ?? doc.id),
      token: String(data.token ?? ""),
      platform,
      environment
    };
  }).filter((record) => record.token);
}

export async function deleteDeviceToken(token: string) {
  await getFirestore().collection("deviceTokens").doc(deviceTokenId(token)).delete();
}
