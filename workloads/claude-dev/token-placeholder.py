#!/usr/bin/env python3
"""Select a scoped Vertex placeholder from native metadata, never a token."""
import json
import re
import subprocess
import sys


def resolve(sandbox, region):
    if not re.fullmatch(r"[a-z][a-z0-9-]*", region):
        raise ValueError("Invalid Vertex region")
    if region == "global":
        host = "aiplatform.googleapis.com"
    elif region in ("eu", "us"):
        host = f"aiplatform.{region}.rep.googleapis.com"
    else:
        host = f"{region}-aiplatform.googleapis.com"
    inventory = json.loads(subprocess.check_output(
        ["sbx", "secret", "ls", "--sandbox", sandbox, "--json"], text=True))
    entries = inventory["custom_secrets"]
    if not isinstance(entries, list):
        raise ValueError("Invalid native Vertex secret inventory")
    matches = []
    for entry in entries:
        targets = entry.get("targets", [])
        if (entry.get("scope") == sandbox and entry.get("env") == "ANTHROPIC_AUTH_TOKEN"
                and entry.get("kind") == "command" and isinstance(targets, list)
                and host in targets and all(isinstance(target, str) and re.fullmatch(
                    r"(?:[a-z0-9-]+-)?aiplatform\.googleapis\.com|"
                    r"aiplatform\.(?:eu|us)\.rep\.googleapis\.com", target) for target in targets)):
            matches.append(entry)
    if len(matches) != 1:
        raise ValueError("Store exactly one sandbox-scoped Vertex command secret with exact Vertex hosts; "
                         "see docs/client-vertex.md")
    placeholder = matches[0].get("placeholder", "")
    if not isinstance(placeholder, str) or not re.fullmatch(r"sbx-cs-[A-Za-z0-9_-]+", placeholder):
        raise ValueError("Vertex secret has an unsupported native placeholder")
    return placeholder


if __name__ == "__main__":
    try:
        print(resolve(sys.argv[1], sys.argv[2]))
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"vertex: {error}")
