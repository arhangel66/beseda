---
type: Product Overview
---
# Overview

Beseda is a macOS menu bar app that records calls and turns them into transcripts on the same Mac.
It records the microphone ("me") and the system audio ("them") as separate channels, transcribes them
locally, and keeps an archive of calls with search, summaries and an optional webhook.

It is for one person who takes calls in Zoom, Google Meet, Telegram and similar apps on an Apple Silicon
Mac and wants the text of those calls without sending the audio to a cloud service. The interface is in
Russian.

Local by default: audio, transcripts and the call index stay in `~/Library/Application Support/Beseda`.
Network is used to download models, to check for updates, and only when the user turns them on — for an
OpenRouter summary or a webhook delivery.

There is no MCP server or any other MCP code in the project.
