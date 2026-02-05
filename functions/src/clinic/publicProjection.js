"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildPublicBookingProjection = buildPublicBookingProjection;
var admin = require("firebase-admin");
function buildPublicBookingProjection(args) {
    var _a, _b, _c, _d;
    var now = admin.firestore.FieldValue.serverTimestamp();
    return {
        clinicId: args.clinicId,
        clinicName: args.clinicName,
        logoUrl: args.logoUrl,
        openingHours: (_a = args.clinicDoc.settings.openingHours) !== null && _a !== void 0 ? _a : {},
        bookingRules: (_b = args.clinicDoc.settings.bookingRules) !== null && _b !== void 0 ? _b : {},
        slotMinutes: (_d = (_c = args.clinicDoc.settings.bookingStructure) === null || _c === void 0 ? void 0 : _c.publicSlotMinutes) !== null && _d !== void 0 ? _d : 60,
        services: args.services.map(function (s) {
            var _a, _b, _c, _d;
            return ({
                id: s.id,
                name: (_a = s.data.name) !== null && _a !== void 0 ? _a : "",
                minutes: (_b = s.data.defaultMinutes) !== null && _b !== void 0 ? _b : 30,
                price: (_c = s.data.defaultFee) !== null && _c !== void 0 ? _c : null,
                description: (_d = s.data.description) !== null && _d !== void 0 ? _d : "",
            });
        }),
        updatedAt: now,
    };
}
