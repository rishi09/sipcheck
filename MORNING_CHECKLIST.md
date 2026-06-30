# SipCheck — Morning Checklist

Order: quick wins → the two real tasks. ~45 min. Code is done; these are the
Apple-account / laptop steps only you can do.

## Part 1 — Test the app (5 min, phone)
1. TestFlight app → SipCheck → **pull to refresh** → Update to the newest build
   (1.0 (26) or higher — it has all fixes and auto-clears compliance).
2. Open app → Profile → ⚙️ → **Seed Sample Data**. Confirm beers/scans/journal
   show up. Try: delete a beer, a text scan (stub verdict until the key's in),
   browse Journal + Profile stats.

## Part 2 — Real scanning (5 min, phone or laptop)
3. platform.openai.com → create a NEW API key (revoke the old exposed one).
4. GitHub → repo → Settings → Secrets and variables → Actions → New secret:
   name `OPENAI_API_KEY`, paste the key.
5. Tell Claude "key added" → it pushes a build so scanning goes live.

## Part 3 — iCloud sync (~15 min, Mac + Xcode) ← main task
6. `cd ~/side-projects/sipcheck && git pull`
7. Xcode → select your iPhone (or simulator) → Run (Cmd+R). (Development build,
   signed into iCloud.)
8. In the app: add a beer WITH a photo + tap Seed Sample Data. (Creates the
   Development CloudKit schema with all fields: isDeleted, photoAsset.)
9. icloud.developer.apple.com/dashboard → container iCloud.com.rishishah.sipcheck
   → Schema → Deploy Schema Changes… → Development → Production.
10. Verify a beer + photo persist / show on a second device.

## Part 4 — Privacy URLs (2 min)
11. GitHub → Settings → Pages → Source: Deploy from branch → `main` / `/docs`.
    (Works after the branch is merged to main — Part 5.) Then
    rishi09.github.io/sipcheck/privacy/ should load.

## Part 5 — App Store submission (when ready)
12. Merge the PR to `main` (also activates Pages + the schema-deploy workflow).
13. Use APP_STORE_SUBMISSION.md (name, description, keywords, privacy + age
    answers, screenshot plan) to fill App Store Connect; capture 6 screenshots.
14. Ask Claude to REMOVE the "Seed Sample Data" button before public submission.

## Fastest unblock for Claude
Parts 2 + 3 (OpenAI key + iCloud schema). Ping "key added" after Part 2.
Paste any error from Part 3 and Claude will fix it.

---
After the plumbing's confirmed (sync + scanning + pipeline), next phase is
on-device testing pass + UI polish.
