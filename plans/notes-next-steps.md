# SipCheck Notes — Dataset + Feature Prioritization + Vision vs GPT

> Status note: this is a working-session note. Some "next actions" below have already partially landed, including the initial hybrid scan pipeline. Use `README.md` for current product status.

## Quick links
- Key features playbook (v2): [SipCheck_Key_Features_Playbook_v2.html](./SipCheck_Key_Features_Playbook_v2.html)
- Original feature playbook: [SipCheck_Key_Features_Playbook.html](./SipCheck_Key_Features_Playbook.html)
- Screenshot-rich research doc (HTML): [SipCheck_Competitive_Research_With_Screenshots.html](./SipCheck_Competitive_Research_With_Screenshots.html)
- Image manifest: [feature_image_manifest.json](./feature_image_manifest.json)

## What we confirmed
- We expanded screenshot gathering and built a feature-organized playbook.
- `SipCheck_Key_Features_Playbook_v2.html` is organized by **key feature** and includes step-by-step flows.
- For displayed reference products in v2, we selected apps with at least 3 available screenshots.

## High-level product recommendation (speed-critical use case)
Use a **hybrid pipeline**:

1. **Primary (fast)**: Apple Vision on-device
   - Barcode detection for cans/bottles
   - OCR for label/menu text
   - Local matching + immediate Buy / Skip / Maybe decision

2. **Fallback/enrichment**: GPT-4o
   - Only when confidence is low
   - Or for explanation/personalized reasoning

### Why
- Lower latency (sub-second on-device path)
- Better behavior in poor signal environments (store/bar)
- Lower cost than sending every scan to GPT
- Better UX for “standing in aisle, decide now” behavior

## Data strategy notes
Recommended source stack:
1. **Open Food Facts** as core real-packaging dataset (beer category images + metadata)
2. Your own in-store captures for robustness (angles/glare/shelf clutter/4-pack)
3. Wikimedia labels as supplemental long-tail/stylized augmentation

## Candidate key features to prioritize
1. Smart Capture (label/barcode/menu scan)
2. Logging + tasting notes
3. Personalized recommendations (match score + reason)
4. Discovery + social proof
5. Retention loop (goals/progress/insights)

## Next actions
- Review screenshots in the v2 playbook and pick top-priority feature(s)
- Define MVP acceptance criteria per selected feature
- Validate and refine the Vision-first pipeline + fallback path already wired into the app
- Start small eval set from Open Food Facts + real grocery captures

---
Generated during working session for quick continuation.
