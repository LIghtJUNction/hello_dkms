<!--
  ~ Copyright (c) 2026 lightjunction
  ~
  ~ This program is free software: you can redistribute it and/or modify
  ~ it under the terms of the GNU General Public License as published by
  ~ the Free Software Foundation, either version 3 of the License, or
  ~ (at your option) any later version.
-->

# AGENTS.md — DKMS skill quick install

Purpose
- Provide a single-line install command to add the `hello-dkms` DKMS development skill to a local skill manager via the smithery CLI.
- Help agents quickly discover and enable the skill without copying documentation into the conversation.

Install (one-liner)
```hello-1.0/AGENTS.md#L1-1
npx @smithery/cli@latest skill add lightjunction-me/hello-dkms
```

Notes
- The repository already contains the required skill implementations under `.agents/skills/`. Do NOT recreate them manually.
- Use the command above in an environment with network access and appropriate permissions to install the smithery CLI and register the skill.

Trigger hints (when to call the skill)
- When a user mentions keywords such as: `DKMS`, `dkms add`, `dkms build`, `dkms install`, `Module.symvers`, `kernel headers`, `modprobe`, or asks how to make a module survive kernel upgrades.

Skill responsibility (one line)
- Manage `hello-dkms` add/build/install/verify/remove steps and provide verification diagnostics (`dmesg`, `modinfo`, `dkms status`).

Security & environment
- Installing and running DKMS operations requires elevated privileges and matching kernel headers. Remind users to review commands before executing.

Maintenance
- Keep this file minimal — it is only a quick pointer. Update the skill files under `.agents/skills/hello-dkms/` for detailed workflows, examples, and platform-specific instructions.