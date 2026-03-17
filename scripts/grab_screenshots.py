#!/usr/bin/env python3
"""Scrape App Store screenshot URLs for all competitor apps and download them."""

import subprocess
import re
import os
import json

APPS = {
    "untappd": {
        "name": "Untappd",
        "url": "https://apps.apple.com/us/app/untappd-discover-beer/id449141888"
    },
    "vivino": {
        "name": "Vivino",
        "url": "https://apps.apple.com/us/app/vivino-buy-the-right-wine/id414461255"
    },
    "pintplease": {
        "name": "Pint Please",
        "url": "https://apps.apple.com/us/app/pint-please-beer-finder/id1145691578"
    },
    "beerrate": {
        "name": "BeerRate",
        "url": "https://apps.apple.com/us/app/beerrate/id1596498498"
    },
    "brewzy": {
        "name": "Brewzy",
        "url": "https://apps.apple.com/us/app/brewzy-beer-scanner-tracker/id6480417240"
    },
    "hornai": {
        "name": "Horn AI",
        "url": "https://apps.apple.com/us/app/horn-ai-wine-scanner/id6504907042"
    },
    "draughtpick": {
        "name": "DraughtPick",
        "url": "https://apps.apple.com/us/app/draughtpick-beer-recommender/id1507682680"
    },
    "whichcraft": {
        "name": "WhichCraft",
        "url": "https://apps.apple.com/us/app/whichcraft-beer/id1081498373"
    }
}

OUTPUT_DIR = "/Users/rkshah20/side-projects/sipcheck/research_output/screenshots"

def extract_screenshot_urls(html):
    """Extract unique high-res screenshot URLs from App Store page HTML."""
    # Look for Slide_N patterns in mzstatic URLs (these are the app screenshots)
    pattern = r'https://is\d+-ssl\.mzstatic\.com/image/thumb/[^/]+/v4/[^/]+/[^/]+/[^/]+/Slide_\d+\.(?:jpeg|png|jpg)/\d+x\d+bb(?:-\d+)?\.(?:jpg|jpeg|png|webp)'
    urls = re.findall(pattern, html)

    # Dedupe and get highest resolution version for each slide
    slides = {}
    for url in urls:
        slide_match = re.search(r'Slide_(\d+)', url)
        if not slide_match:
            continue
        slide_num = slide_match.group(1)
        # Prefer 460x996 or 600x1300 JPG versions
        if slide_num not in slides or '460x996' in url or '600x1300' in url:
            if url.endswith('.jpg') or url.endswith('.jpeg'):
                slides[slide_num] = url

    # If no JPG found, fall back to any format
    for url in urls:
        slide_match = re.search(r'Slide_(\d+)', url)
        if not slide_match:
            continue
        slide_num = slide_match.group(1)
        if slide_num not in slides:
            slides[slide_num] = url

    return dict(sorted(slides.items(), key=lambda x: int(x[0])))


def fetch_app_screenshots(app_key, app_info):
    """Fetch and download screenshots for a single app."""
    app_dir = os.path.join(OUTPUT_DIR, app_key)
    os.makedirs(app_dir, exist_ok=True)

    print(f"\n{'='*60}")
    print(f"Fetching: {app_info['name']} ({app_info['url']})")
    print(f"{'='*60}")

    # Fetch the App Store page
    result = subprocess.run(
        ['curl', '-s', '-L', '-A', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36', app_info['url']],
        capture_output=True, text=True, timeout=30
    )

    if result.returncode != 0:
        print(f"  ERROR: curl failed with code {result.returncode}")
        return {}

    html = result.stdout
    slides = extract_screenshot_urls(html)

    if not slides:
        # Fallback: try to get ANY mzstatic image URLs that look like screenshots
        pattern = r'https://is\d+-ssl\.mzstatic\.com/image/thumb/Purple[^/]*/v4/[^">\s,]+\.(?:jpeg|jpg|png)'
        fallback_urls = list(set(re.findall(pattern, html)))
        # Filter to high-res versions
        fallback_urls = [u for u in fallback_urls if any(dim in u for dim in ['460x', '600x', '392x', '300x'])]
        for i, url in enumerate(fallback_urls[:10], 1):
            slides[str(i)] = url

    print(f"  Found {len(slides)} screenshots")

    # Download each screenshot
    downloaded = {}
    for slide_num, url in slides.items():
        ext = 'jpg' if url.endswith('.jpg') or url.endswith('.jpeg') else 'png' if url.endswith('.png') else 'webp'
        filename = f"screenshot_{slide_num}.{ext}"
        filepath = os.path.join(app_dir, filename)

        dl_result = subprocess.run(
            ['curl', '-s', '-L', '-o', filepath, url],
            capture_output=True, timeout=30
        )

        if dl_result.returncode == 0 and os.path.exists(filepath) and os.path.getsize(filepath) > 1000:
            print(f"  Downloaded: {filename} ({os.path.getsize(filepath)//1024}KB)")
            downloaded[slide_num] = {
                "file": filepath,
                "url": url,
                "filename": filename
            }
        else:
            print(f"  FAILED: {filename}")
            if os.path.exists(filepath):
                os.remove(filepath)

    return downloaded


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    all_results = {}

    for app_key, app_info in APPS.items():
        try:
            screenshots = fetch_app_screenshots(app_key, app_info)
            all_results[app_key] = {
                "name": app_info["name"],
                "url": app_info["url"],
                "screenshot_count": len(screenshots),
                "screenshots": screenshots
            }
        except Exception as e:
            print(f"  ERROR for {app_info['name']}: {e}")
            all_results[app_key] = {
                "name": app_info["name"],
                "url": app_info["url"],
                "screenshot_count": 0,
                "screenshots": {},
                "error": str(e)
            }

    # Save manifest
    manifest_path = os.path.join(OUTPUT_DIR, "manifest.json")
    with open(manifest_path, 'w') as f:
        json.dump(all_results, f, indent=2)

    # Print summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    total = 0
    for app_key, data in all_results.items():
        count = data["screenshot_count"]
        total += count
        print(f"  {data['name']:20s}: {count} screenshots")
    print(f"  {'TOTAL':20s}: {total} screenshots")
    print(f"\nManifest saved to: {manifest_path}")


if __name__ == "__main__":
    main()
