"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
    return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createClinic = createClinic;
var https_1 = require("firebase-functions/v2/https");
var admin = require("firebase-admin");
var seedDefaults_1 = require("./seedDefaults");
var permissions_1 = require("./permissions");
var publicProjection_1 = require("./publicProjection");
function createClinic(req) {
    return __awaiter(this, void 0, void 0, function () {
        var uid, name, timezone, defaultLanguage, db, clinicRef, clinicId, now, clinicDoc, memberRef, userMembershipRef, memberDoc, userMembershipDoc, roles, location, services, batch, _i, roles_1, r, locRef, _a, services_1, s, publicBooking;
        var _b, _c, _d, _e, _f, _g;
        return __generator(this, function (_h) {
            switch (_h.label) {
                case 0:
                    if (!req.auth)
                        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
                    uid = req.auth.uid;
                    name = ((_c = (_b = req.data) === null || _b === void 0 ? void 0 : _b.name) !== null && _c !== void 0 ? _c : "").trim();
                    timezone = ((_e = (_d = req.data) === null || _d === void 0 ? void 0 : _d.timezone) !== null && _e !== void 0 ? _e : "Europe/Prague").trim();
                    defaultLanguage = ((_g = (_f = req.data) === null || _f === void 0 ? void 0 : _f.defaultLanguage) !== null && _g !== void 0 ? _g : "en").trim();
                    if (!name)
                        throw new https_1.HttpsError("invalid-argument", "Clinic name is required.");
                    if (name.length > 120)
                        throw new https_1.HttpsError("invalid-argument", "Clinic name too long.");
                    db = admin.firestore();
                    clinicRef = db.collection("clinics").doc();
                    clinicId = clinicRef.id;
                    now = admin.firestore.FieldValue.serverTimestamp();
                    clinicDoc = {
                        profile: {
                            name: name,
                            logoUrl: "",
                            address: "",
                            phone: "",
                            email: "",
                            timezone: timezone,
                            defaultLanguage: defaultLanguage,
                        },
                        settings: {
                            openingHours: {
                                weekStart: "mon",
                                daysOrder: "mon",
                                days: [], // keep empty here; UI can later write via settings.update permission
                            },
                            bookingRules: {
                                maxDaysInAdvance: 90,
                                minNoticeMinutes: 120,
                                cancelNoPenaltyHours: 24,
                                patientsCanReschedule: false,
                                allowGroupOverbook: true,
                                allowOverlapWithAssistant: true,
                                preventResourceDoubleBooking: true,
                            },
                            bookingStructure: {
                                defaultSlotMinutes: 20,
                                adminGridMinutes: 15,
                                publicSlotMinutes: 60,
                                slotMinutesByType: {},
                                bufferBeforeFirst: 0,
                                bufferBetween: 5,
                                bufferAfterLast: 0,
                            },
                            appearance: {
                                bookedColor: 0xFF3B82F6,
                                attendedColor: 0xFF10B981,
                                cancelledColor: 0xFFF59E0B,
                                noShowColor: 0xFFEF4444,
                                nowLineColor: 0xFF111827,
                                slotHeight: 48,
                                showWeekends: false,
                            },
                            billing: {
                                defaultFee: 0.0,
                                vatPercent: 0.0,
                                invoicePrefix: "",
                            },
                            communicationDefaults: {
                                senderName: name,
                                senderEmail: "",
                            },
                            security: {
                                allowNewPatients: true,
                                requireConsent: true,
                            },
                        },
                        status: {
                            active: true,
                            plan: "free",
                            createdAt: now,
                            updatedAt: now,
                        },
                        ownerUid: uid,
                        schemaVersion: 3,
                    };
                    memberRef = clinicRef.collection("members").doc(uid);
                    userMembershipRef = db.collection("users").doc(uid).collection("memberships").doc(clinicId);
                    memberDoc = {
                        roleId: "owner",
                        permissions: (0, permissions_1.ownerPermissions)(),
                        active: true,
                        createdAt: now,
                        updatedAt: now,
                    };
                    userMembershipDoc = {
                        clinicNameCache: name,
                        roleId: "owner",
                        active: true,
                        createdAt: now,
                    };
                    roles = (0, seedDefaults_1.seedDefaultRoles)();
                    location = (0, seedDefaults_1.seedDefaultLocation)();
                    services = (0, seedDefaults_1.seedStarterServices)();
                    batch = db.batch();
                    batch.set(clinicRef, clinicDoc);
                    batch.set(memberRef, memberDoc);
                    batch.set(userMembershipRef, userMembershipDoc);
                    // Seed roles
                    for (_i = 0, roles_1 = roles; _i < roles_1.length; _i++) {
                        r = roles_1[_i];
                        batch.set(clinicRef.collection("roles").doc(r.id), r.data);
                    }
                    locRef = clinicRef.collection("locations").doc(location.id);
                    batch.set(locRef, location.data);
                    for (_a = 0, services_1 = services; _a < services_1.length; _a++) {
                        s = services_1[_a];
                        batch.set(clinicRef.collection("services").doc(s.id), s.data);
                    }
                    publicBooking = (0, publicProjection_1.buildPublicBookingProjection)({
                        clinicId: clinicId,
                        clinicName: name,
                        logoUrl: "",
                        clinicDoc: clinicDoc,
                        services: services,
                    });
                    batch.set(clinicRef.collection("public").doc("booking"), publicBooking);
                    return [4 /*yield*/, batch.commit()];
                case 1:
                    _h.sent();
                    return [2 /*return*/, { clinicId: clinicId }];
            }
        });
    });
}
