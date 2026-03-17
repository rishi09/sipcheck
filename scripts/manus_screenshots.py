#!/usr/bin/env python3
"""Use Manus SDK to grab App Store screenshots for competitor apps."""

import sys
sys.path.insert(0, '/Users/rkshah20/Library/Python/3.9/lib/python/site-packages')

from manus import Manus

API_KEY = "sk-uH2h-rrgUwt8dfxsFHqcDqHOMpuNcG9UG9mPG35qI9Hx2zzLYbQ1Q9b47fQQAaTC5NZPiH8Wd19ZN5SKu4c8_pq2nksZ"

client = Manus(api_key=API_KEY)

# Test with a simple request first
response = client.chat.completions.create(
    model="manus-1",
    messages=[
        {"role": "user", "content": "Go to the Apple App Store page for Untappd (https://apps.apple.com/us/app/untappd-discover-beer/id449141888) and list all the screenshot URLs you can see on the page. Return them as a list."}
    ],
    extra_body={
        "task_mode": "agent",
        "agent_profile": "manus-1.6"
    }
)

print("Response type:", type(response))
print("Response:", response)
