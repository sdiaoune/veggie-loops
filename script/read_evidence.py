#!/usr/bin/env python3
"""Print selected small facets of retained REA MCP responses."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("path", type=Path)
parser.add_argument("--facet", default="pseudo_code")
args = parser.parse_args()
response = json.loads(args.path.read_text())
payload = response.get("structuredContent")
if payload is None:
    text = next(item["text"] for item in response.get("content", []) if item["type"] == "text")
    payload = json.loads(text)

def find(value, path=""):
    if isinstance(value, dict):
        for key, child in value.items():
            current = f"{path}.{key}" if path else key
            if key == args.facet:
                print(current)
                print(child if isinstance(child, str) else json.dumps(child, indent=2))
            elif key not in ("evidence", "raw_result", "content"):
                find(child, current)
    elif isinstance(value, list):
        for i, child in enumerate(value):
            find(child, f"{path}[{i}]")

find(payload)
