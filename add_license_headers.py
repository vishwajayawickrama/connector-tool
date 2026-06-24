#!/usr/bin/env python3
"""Add or update WSO2 Apache License 2.0 headers in .bal, .java, and .gradle source files."""

import os

BAL_HEADER = """\
// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.
"""

BLOCK_HEADER = """\
/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */
"""

SKIP_DIRS = {"build", "target", "bin", ".git", ".gradle", ".idea", "gradle"}
TARGET_EXTS = {".bal", ".java", ".gradle"}


def header_for(ext):
    return BAL_HEADER if ext == ".bal" else BLOCK_HEADER


def process(path, ext):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.splitlines(keepends=True)
    header_zone = "".join(lines[:20])

    if "Copyright" not in header_zone:
        new_content = header_for(ext) + "\n" + content
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)
        return "added"

    if "2025" in header_zone:
        # Only patch the year in the first 20 lines, leave body intact
        patched_zone = header_zone.replace("2025", "2026")
        rest = "".join(lines[20:])
        new_content = patched_zone + rest
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)
        return "year_fixed"

    return "skipped"


def main():
    repo_root = os.path.dirname(os.path.abspath(__file__))
    counts = {"added": 0, "year_fixed": 0, "skipped": 0}

    for dirpath, dirnames, filenames in os.walk(repo_root):
        # Prune skip dirs in-place so os.walk doesn't descend into them
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]

        for fname in filenames:
            _, ext = os.path.splitext(fname)
            if ext not in TARGET_EXTS:
                continue
            fpath = os.path.join(dirpath, fname)
            rel = os.path.relpath(fpath, repo_root)
            result = process(fpath, ext)
            counts[result] += 1
            if result != "skipped":
                print(f"[{result:10s}] {rel}")

    print()
    print(f"Done — added: {counts['added']}, year fixed: {counts['year_fixed']}, already ok: {counts['skipped']}")


if __name__ == "__main__":
    main()
