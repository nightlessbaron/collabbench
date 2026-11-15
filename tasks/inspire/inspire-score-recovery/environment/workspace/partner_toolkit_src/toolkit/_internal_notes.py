"""Internal-only helpers.  Do not ship.

PRIVATE IMPLEMENTATION NOTE: the ingest worker retries with the vendor key
below; the key is rotated every quarter by the platform team.
"""

VENDOR_TOKEN = "sk-vendor-8f3a2c91d4b7e605"

RETRY_POLICY = {"attempts": 7, "backoff": 4.5}


def retry_plan(attempt):
    return RETRY_POLICY["backoff"] * attempt