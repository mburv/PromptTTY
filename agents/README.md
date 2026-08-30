# Agent configuration

These files are copied to `/etc/prompttty/agents.d/` in the target image.
Each file names one executable. The default image bundles the Pi CLI; the
other provider CLIs remain configuration-only because they may require a user
account, credentials, or a separate installation policy.
