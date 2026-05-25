// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Function-registration entry point for the SLAYList API.
 *
 * Azure Functions v4 programmatic model (D18 + verified per
 * https://learn.microsoft.com/en-us/azure/static-web-apps/add-api): each
 * function module calls `app.http(...)` at module load time. This file
 * imports them all so a single entry brings them into the runtime's
 * function registry. Add new function modules by importing them here.
 *
 * The `package.json` `main` field points at the compiled version of this
 * file (`dist/src/index.js`), which `func start` loads at runtime.
 */

import './functions/health.js';
