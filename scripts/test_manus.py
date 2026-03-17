#!/usr/bin/env python3
"""Test Manus SDK API call."""
import sys
sys.path.insert(0, '/Users/rkshah20/Library/Python/3.9/lib/python/site-packages')

from manus import Manus

API_KEY = "sk-uH2h-rrgUwt8dfxsFHqcDqHOMpuNcG9UG9mPG35qI9Hx2zzLYbQ1Q9b47fQQAaTC5NZPiH8Wd19ZN5SKu4c8_pq2nksZ"

client = Manus(api_key=API_KEY)

try:
    response = client.chat.completions.create(
        model="manus-1",
        messages=[
            {"role": "user", "content": "Say hello in one sentence."}
        ],
        extra_body={
            "task_mode": "agent",
            "agent_profile": "manus-1.6"
        }
    )
    print("SUCCESS!")
    print("Type:", type(response))
    print("Response:", response)
except Exception as e:
    print(f"ERROR: {type(e).__name__}: {e}")
    import traceback
    traceback.print_exc()
