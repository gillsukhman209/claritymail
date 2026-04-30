import { getFirestore } from "./firebase.js";
import type { MorningBriefSummary } from "../services/ai.service.js";

export type MorningBriefSettings = {
  enabled: boolean;
  briefTime: string;
  timeZone: string;
  lookbackHours: number;
  unreadOnly: boolean;
  includeNewsletters: boolean;
  onlyNotifyIfImportant: boolean;
};

export type MorningBriefRecord = {
  id: string;
  windowStart: string;
  windowEnd: string;
  generatedAt: string;
  totalUnread: number;
  ignoredCount: number;
  settings: MorningBriefSettings;
  summary: MorningBriefSummary;
};

export const defaultMorningBriefSettings: MorningBriefSettings = {
  enabled: true,
  briefTime: "09:00",
  timeZone: "America/Los_Angeles",
  lookbackHours: 14,
  unreadOnly: true,
  includeNewsletters: false,
  onlyNotifyIfImportant: true
};

function normalizeSettings(data: FirebaseFirestore.DocumentData | undefined): MorningBriefSettings {
  return {
    enabled: typeof data?.enabled === "boolean" ? data.enabled : defaultMorningBriefSettings.enabled,
    briefTime: typeof data?.briefTime === "string" ? data.briefTime : defaultMorningBriefSettings.briefTime,
    timeZone: typeof data?.timeZone === "string" ? data.timeZone : defaultMorningBriefSettings.timeZone,
    lookbackHours:
      typeof data?.lookbackHours === "number" ? data.lookbackHours : defaultMorningBriefSettings.lookbackHours,
    unreadOnly: typeof data?.unreadOnly === "boolean" ? data.unreadOnly : defaultMorningBriefSettings.unreadOnly,
    includeNewsletters:
      typeof data?.includeNewsletters === "boolean"
        ? data.includeNewsletters
        : defaultMorningBriefSettings.includeNewsletters,
    onlyNotifyIfImportant:
      typeof data?.onlyNotifyIfImportant === "boolean"
        ? data.onlyNotifyIfImportant
        : defaultMorningBriefSettings.onlyNotifyIfImportant
  };
}

export function sanitizeMorningBriefSettings(input: Partial<MorningBriefSettings>): MorningBriefSettings {
  const base = normalizeSettings(input);
  const briefTime = /^([01]\d|2[0-3]):[0-5]\d$/.test(base.briefTime)
    ? base.briefTime
    : defaultMorningBriefSettings.briefTime;
  const lookbackHours = Math.min(20, Math.max(10, Math.round(base.lookbackHours)));

  return {
    ...base,
    briefTime,
    lookbackHours,
    includeNewsletters: false
  };
}

export async function getMorningBriefSettings() {
  const doc = await getFirestore().collection("appSettings").doc("morningBrief").get();
  return sanitizeMorningBriefSettings(normalizeSettings(doc.data()));
}

export async function saveMorningBriefSettings(input: Partial<MorningBriefSettings>) {
  const settings = sanitizeMorningBriefSettings(input);
  await getFirestore().collection("appSettings").doc("morningBrief").set(
    {
      ...settings,
      updatedAt: new Date()
    },
    { merge: true }
  );
  return settings;
}

export async function saveMorningBrief(record: Omit<MorningBriefRecord, "id">) {
  const ref = await getFirestore().collection("morningBriefs").add({
    ...record,
    createdAt: new Date()
  });

  return {
    id: ref.id,
    ...record
  };
}

export async function getLatestMorningBrief(): Promise<MorningBriefRecord | null> {
  const snapshot = await getFirestore()
    .collection("morningBriefs")
    .orderBy("generatedAt", "desc")
    .limit(1)
    .get();

  const doc = snapshot.docs[0];
  if (!doc) return null;

  const data = doc.data();
  return {
    id: doc.id,
    windowStart: String(data.windowStart),
    windowEnd: String(data.windowEnd),
    generatedAt: String(data.generatedAt),
    totalUnread: Number(data.totalUnread ?? 0),
    ignoredCount: Number(data.ignoredCount ?? 0),
    settings: sanitizeMorningBriefSettings(data.settings ?? {}),
    summary: data.summary as MorningBriefSummary
  };
}
