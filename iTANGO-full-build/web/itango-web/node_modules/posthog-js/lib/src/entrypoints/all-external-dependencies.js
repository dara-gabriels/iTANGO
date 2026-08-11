"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
require("./recorder");
require("./surveys");
require("./logs");
require("./exception-autocapture");
require("./tracing-headers");
// Full bundles must include every web-vitals callback flavor because no-external
// builds cannot fetch a different flavor after initialization.
require("./web-vitals-with-attribution-soft-navs");
require("./web-vitals-soft-navs");
require("./web-vitals-with-attribution");
require("./web-vitals");
require("./dead-clicks-autocapture");
//# sourceMappingURL=all-external-dependencies.js.map