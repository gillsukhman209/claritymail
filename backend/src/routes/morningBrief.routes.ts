import { Router } from "express";
import { getMorningBriefSettings, saveMorningBriefSettings } from "../db/morningBrief.repo.js";
import { generateMorningBrief, latestMorningBrief } from "../services/morningBrief.service.js";

export const morningBriefRoutes = Router();

morningBriefRoutes.get("/morning-brief/settings", async (_request, response, next) => {
  try {
    response.json({ settings: await getMorningBriefSettings() });
  } catch (error) {
    next(error);
  }
});

morningBriefRoutes.put("/morning-brief/settings", async (request, response, next) => {
  try {
    response.json({ settings: await saveMorningBriefSettings(request.body ?? {}) });
  } catch (error) {
    next(error);
  }
});

morningBriefRoutes.get("/morning-brief/latest", async (_request, response, next) => {
  try {
    response.json({ brief: await latestMorningBrief() });
  } catch (error) {
    next(error);
  }
});

morningBriefRoutes.post("/morning-brief/run", async (request, response, next) => {
  try {
    const accountId = typeof request.body?.accountId === "string" ? request.body.accountId : undefined;
    response.json(await generateMorningBrief({ accountId }));
  } catch (error) {
    next(error);
  }
});

morningBriefRoutes.get("/cron/morning-brief", async (request, response, next) => {
  try {
    if (process.env.CRON_SECRET && request.header("authorization") !== `Bearer ${process.env.CRON_SECRET}`) {
      response.status(401).json({ error: "Unauthorized." });
      return;
    }

    response.json(await generateMorningBrief());
  } catch (error) {
    next(error);
  }
});
