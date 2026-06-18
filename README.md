# Hermes Agent

> An intelligent AI assistant created by Nous Research — helpful, knowledgeable, and direct.

## Overview

Hermes Agent is a powerful AI assistant framework with persistent memory, MCP (Model Context Protocol) integration, cron job scheduling, and multi-platform delivery (WeChat, Telegram, Discord).

## Features

- **Persistent Memory** — Remembers user preferences, environment details, and project conventions across sessions
- **MCP Integration** — Extend capabilities via MCP servers (smart home, pets, music generation, and more)
- **Cron Job Engine** — Schedule automated reports and tasks with cross-session execution
- **Multi-Platform Delivery** — Send results to WeChat, Telegram, Discord, Email, or local files
- **Rich Tool Ecosystem** — 100+ skills for DevOps, data science, ML ops, creative content, and more
- **Memory Compression** — Automatic context management prevents context overflow

## Quick Start

```bash
# Clone the repository
git clone https://github.com/scsagentclub/agent.git
cd agent

# Install Hermes Agent
pip install hermes-agent

# Configure
hermes config init

# Start chatting
hermes chat
```

## Architecture

```
┌─────────────┐    ┌──────────────┐    ┌──────────────┐
│  WeChat     │    │  Telegram    │    │  CLI         │
│  (微信)     │    │              │    │              │
└──────┬──────┘    └──────┬───────┘    └──────┬───────┘
       │                  │                   │
       └──────────────────┼───────────────────┘
                          │
                  ┌───────▼────────┐
                  │  Hermes Agent  │
                  │  Core Engine   │
                  └───────┬────────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
   ┌──────▼─────┐  ┌─────▼──────┐  ┌─────▼──────┐
   │  MCP       │  │  Skills    │  │  Memory    │
   │  Servers   │  │  (100+)    │  │  Store     │
   └────────────┘  └────────────┘  └────────────┘
```

## MCP Servers

Hermes Agent supports Model Context Protocol (MCP) servers for extended capabilities:

- **Smart Home** (米家) — Control Xiaomi Mi Home devices
- **Electronic Pet** — Gamified companion with memory and personality
- **Music Generation** — AI music creation
- **And more** — Custom MCP servers can be added

## License

MIT
