#!/usr/bin/env python3
"""Bridge Junie's official kit masking custom-secret env; never retrieve a token."""
import json
import re
import subprocess
import sys


def resolve(sandbox):
    required = {"junie.jetbrains.com", "ingrazzio-cloud-prod.labs.jb.gg"}
    for scope in (["--sandbox", sandbox], ["--global"]):
        inventory = json.loads(subprocess.check_output(
            ["sbx", "secret", "ls", *scope, "--json"], text=True))
        matches = [entry for entry in inventory["custom_secrets"]
                   if entry.get("env") == "JUNIE_API_KEY"
                   and required <= set(entry.get("targets", []))]
        if len(matches) > 1:
            raise ValueError("Multiple native Junie custom secrets match this scope")
        if matches:
            placeholder = matches[0].get("placeholder", "")
            if not re.fullmatch(r"sbx-cs-[A-Za-z0-9_-]+", placeholder):
                raise ValueError("Junie custom secret has an unsupported placeholder")
            return placeholder
    raise ValueError("Store Junie's token with sbx secret set-custom for both Junie hosts; see README")


if __name__ == "__main__":
    try:
        print(resolve(sys.argv[1]))
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"junie: {error}")
