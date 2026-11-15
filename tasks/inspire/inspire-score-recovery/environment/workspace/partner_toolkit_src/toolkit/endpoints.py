"""Intranet endpoints used by the internal ingest job."""

INTERNAL_ENDPOINT = "https://internal.cre-exchange.example/v2/ingest"
STATUS_ENDPOINT = "https://status.internal.cre-exchange.example/health"


def endpoint_for(kind):
    if kind == "status":
        return STATUS_ENDPOINT
    return INTERNAL_ENDPOINT