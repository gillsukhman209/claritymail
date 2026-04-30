import crypto from "node:crypto";
import http2 from "node:http2";
import { listDeviceTokens, type DeviceEnvironment, type DeviceTokenRecord } from "../db/deviceTokens.repo.js";

type PushEmail = {
  id: string;
  accountId?: string | null;
  sender: string;
  subject: string;
  snippet: string;
};

let cachedJwt: { token: string; createdAt: number } | null = null;

function normalizePrivateKey(value: string) {
  return value.replace(/\\n/g, "\n").trim();
}

function base64Url(value: Buffer | string) {
  return Buffer.from(value)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function apnsEnvironment(): DeviceEnvironment {
  return process.env.APNS_ENV === "production" ? "production" : "sandbox";
}

function apnsHost() {
  return apnsEnvironment() === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
}

function apnsJwt() {
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const privateKey = process.env.APNS_PRIVATE_KEY;

  if (!keyId || !teamId || !privateKey) {
    throw new Error("Missing APNs configuration.");
  }

  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.createdAt < 45 * 60) {
    return cachedJwt.token;
  }

  const header = base64Url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64Url(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${claims}`;
  const signature = crypto.sign("sha256", Buffer.from(signingInput), {
    key: normalizePrivateKey(privateKey),
    dsaEncoding: "ieee-p1363"
  });

  cachedJwt = {
    token: `${signingInput}.${base64Url(signature)}`,
    createdAt: now
  };

  return cachedJwt.token;
}

function senderDisplayName(sender: string) {
  const match = sender.match(/^"?([^"<]+)"?\s*</);
  return match?.[1]?.trim() || sender;
}

function requestApnsPush(device: DeviceTokenRecord, email: PushEmail) {
  const bundleId = process.env.APNS_BUNDLE_ID;
  if (!bundleId) {
    throw new Error("Missing APNS_BUNDLE_ID.");
  }

  const client = http2.connect(`https://${apnsHost()}`);
  const payload = JSON.stringify({
    aps: {
      alert: {
        title: senderDisplayName(email.sender),
        subtitle: email.subject,
        body: email.snippet
      },
      sound: "default"
    },
    route: "email",
    emailId: email.id,
    accountId: email.accountId ?? ""
  });

  return new Promise<void>((resolve) => {
    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${device.token}`,
      authorization: `bearer ${apnsJwt()}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json"
    });

    request.setEncoding("utf8");
    request.on("data", () => {});
    request.on("error", (error) => {
      console.error("APNs push failed", error);
      client.close();
      resolve();
    });
    request.on("end", () => {
      client.close();
      resolve();
    });
    request.end(payload);
  });
}

export async function notifyDevicesForEmail(email: PushEmail) {
  const devices = await listDeviceTokens(apnsEnvironment());
  if (devices.length === 0) return;

  await Promise.all(devices.map((device) => requestApnsPush(device, email)));
}
