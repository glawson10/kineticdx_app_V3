"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildGoogleCalendarUrl = buildGoogleCalendarUrl;
function fmtGoogleUtc(ts) {
    // Google expects UTC format: YYYYMMDDTHHmmssZ
    return ts
        .toDate()
        .toISOString()
        .replace(/[-:]/g, "")
        .replace(/\.\d{3}Z$/, "Z");
}
function buildGoogleCalendarUrl(params) {
    var _a, _b;
    const qs = new URLSearchParams({
        action: "TEMPLATE",
        text: params.title,
        dates: `${fmtGoogleUtc(params.startAt)}/${fmtGoogleUtc(params.endAt)}`,
        details: (_a = params.details) !== null && _a !== void 0 ? _a : "",
        location: (_b = params.location) !== null && _b !== void 0 ? _b : "",
    });
    return `https://www.google.com/calendar/render?${qs.toString()}`;
}
//# sourceMappingURL=calendarLinks.js.map