/**
 * Web Vitals entrypoint (with attribution)
 *
 * This bundle includes attribution data which provides additional debugging information:
 * - Which elements caused layout shifts (CLS)
 * - Timing breakdowns for LCP
 * - Interaction targets for INP
 *
 * This bundle is ~12KB (vs ~6KB for the non-attribution version).
 *
 * Note: Attribution can cause memory issues in SPAs because the onCLS callback
 * holds references to DOM elements that may be detached during navigation.
 * Only enable if you need the debugging data.
 *
 * Enable via: capture_performance: { web_vitals_attribution: true }
 *
 * @see web-vitals.ts for the lighter, default bundle
 */
import '@posthog/browser-common/utils/array-at-polyfill';
import { type WebVitalsCallbacks } from '../utils/globals';
declare const postHogWebVitalsCallbacks: WebVitalsCallbacks;
export default postHogWebVitalsCallbacks;
