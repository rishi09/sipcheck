# SipCheck — Morning Checklist

Code is done. These are the Apple-account / laptop steps only you can do.
Do Part 0 first — CI builds are paused until it's done.

## Part 0 — Fix signing so builds work again (~8 min, Mac) ← do first
CI hit Apple's certificate cap (every build was minting a new cert). The fix:
give CI ONE distribution cert to reuse.

1. **Revoke extra certs:** developer.apple.com/account → Certificates → revoke
   the old/unused ones (especially "Apple Development: Created via API"). Keep
   the **Apple Distribution** cert your Mac uses.
2. **Export that Distribution cert as .p12:** open **Keychain Access** on your
   Mac → My Certificates → find **"Apple Distribution: Rishi Shah"** → expand it,
   select BOTH the cert and its private key → right-click → **Export** → save as
   `dist.p12`, set a password.
3. **Base64 it:** in Terminal: `base64 -i dist.p12 | pbcopy`
4. **Add two GitHub secrets** (Settings → Secrets and variables → Actions):
   - `DIST_CERT_P12_BASE64` → paste (Cmd-V) the base64 from step 3
   - `DIST_CERT_PASSWORD` → the password you set in step 2
5. **Ping Claude "cert added"** → Claude pushes a build. From now on CI reuses
   this one cert — no more "maximum number of certificates" errors.

## Part 1 — Test the app (5 min, phone)
6. TestFlight → SipCheck → pull to refresh → Update to newest build. (Current
   good build is 1.0 (25) with all fixes; the new cert build will supersede it.)
7. Profile → ⚙️ → Seed Sample Data. Confirm data; try delete, a text scan
   (stub verdict until the OpenAI key), Journal + stats.

## Part 2 — Real scanning (5 min, phone OK)
8. platform.openai.com → new API key (revoke the old exposed one).
9. GitHub → Secrets → Actions → `OPENAI_API_KEY`.
10. Ping Claude "key added" → it folds into the next build.

## Part 3 — iCloud sync (~15 min, Mac + Xcode)
11. `cd ~/side-projects/sipcheck && git pull`
12. Xcode → your iPhone → Run (Development build, signed into iCloud).
13. Add a beer WITH a photo + tap Seed Sample Data (creates the Dev schema:
    isDeleted, photoAsset).
14. icloud.developer.apple.com/dashboard → container iCloud.com.rishishah.sipcheck
    → Schema → Deploy Changes → Development → Production.
15. Verify a beer + photo sync.

## Part 4 — Privacy URLs (2 min)
16. GitHub → Settings → Pages → `main` / `/docs` (after merge to main).

## Part 5 — App Store submission (when ready)
17. Merge PR → main. Fill App Store Connect from APP_STORE_SUBMISSION.md +
    capture 6 screenshots. Ask Claude to remove the Seed Sample Data button.

---
Order that unblocks Claude fastest: Part 0 (cert) → Part 2 (OpenAI key).
Ping "cert added" and "key added"; paste any error and Claude fixes it.
Then: on-device testing pass + UI polish.
