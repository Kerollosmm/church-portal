# ui

## Overview
The `lib/ui` directory forms the complete presentation and user interface layer of the Church Portal. It organizes the Flutter visual interface into three core subdirectories: authenticated administrative tools (`admin`), public destination pages (`pages`), and reusable design system widgets and platform adapters (`widgets`). Together, these modules uphold the portal's Arabic-first RTL design, Cairo wall-clock time precision (`CairoTime`), zero hardcoded user content, and responsive accessibility across web and mobile viewports.

## Subdirectories & Boundaries
- [admin](./admin/README.md) - Authenticated administrative back-office management console (`/admin`), providing schema-driven content editors, configuration forms, and validation rules for church operations.
- [pages](./pages/README.md) - Public destination screens including home, liturgies, activities, education, clinics, Katameros daily readings, contact forms, push notification settings, and conversational AI assistant.
- [widgets](./widgets/README.md) - Reusable UI components, design tokens, responsive scaffolding, golden ambient visual effects, deferred installation sheets, and platform-specific view adapters.
