# TitanMatik — Project boundaries

Status: accepted
Date: 2026-11-04

## Non-negotiable separation

TitanMatik and ArtyomOS are two independent projects. Do not merge, integrate, or couple their architecture, infrastructure, code, databases, users, APIs, credentials, deployment, billing, licensing, or operational workflows by default.

- TitanMatik: Hero Wars automation distribution, customer Telegram bot, licensing, referrals, payments, customer portal, and admin panel.
- ArtyomOS: separate personal system; it is NOT a TitanMatik runtime dependency, backend, database, control plane, or required documentation destination.
- Sharing a technology choice (e.g. Cloudflare, GitHub, D1, Telegram) does not imply sharing an instance, account, database, Worker, or service.
- Plan and implement TitanMatik work only within TitanMatik-specific resources. Do not propose recording TitanMatik ADRs/RFCs in ArtyomOS as a routine step.
- Any future cross-project integration requires an explicit user request and a separate documented decision.

This document is a project-boundary rule, not an implementation claim. Existing deployments must be audited before asserting they are isolated.
