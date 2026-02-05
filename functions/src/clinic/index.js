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
exports.acceptInvite = acceptInvite;
var https_1 = require("firebase-functions/v2/https");
var admin = require("firebase-admin");
var hash_1 = require("./hash");
var permissions_1 = require("./permissions");
function acceptInvite(req) {
    return __awaiter(this, void 0, void 0, function () {
        var token, db, uid, userEmail, tokenHash, inviteQuery, inviteSnap, invite, clinicId, roleRef, roleSnap, rolePermissions, flattened, now, memberRef, userMembershipRef, clinicSnap, clinicName, batch;
        var _a, _b, _c, _d, _e, _f, _g, _h, _j;
        return __generator(this, function (_k) {
            switch (_k.label) {
                case 0:
                    if (!req.auth) {
                        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
                    }
                    token = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.token) !== null && _b !== void 0 ? _b : "").trim();
                    if (!token) {
                        throw new https_1.HttpsError("invalid-argument", "Invite token required.");
                    }
                    db = admin.firestore();
                    uid = req.auth.uid;
                    userEmail = (_c = req.auth.token.email) === null || _c === void 0 ? void 0 : _c.toLowerCase();
                    if (!userEmail) {
                        throw new https_1.HttpsError("failed-precondition", "User email not available.");
                    }
                    tokenHash = (0, hash_1.hashToken)(token);
                    return [4 /*yield*/, db.collectionGroup("invites")
                            .where("tokenHash", "==", tokenHash)
                            .limit(1)
                            .get()];
                case 1:
                    inviteQuery = _k.sent();
                    if (inviteQuery.empty) {
                        throw new https_1.HttpsError("not-found", "Invite not found or invalid.");
                    }
                    inviteSnap = inviteQuery.docs[0];
                    invite = inviteSnap.data();
                    clinicId = (_d = inviteSnap.ref.parent.parent) === null || _d === void 0 ? void 0 : _d.id;
                    if (!clinicId) {
                        throw new https_1.HttpsError("internal", "Clinic reference missing.");
                    }
                    if (invite.status !== "pending") {
                        throw new https_1.HttpsError("failed-precondition", "Invite already used or revoked.");
                    }
                    if (invite.expiresAt.toMillis() < Date.now()) {
                        throw new https_1.HttpsError("deadline-exceeded", "Invite expired.");
                    }
                    if (invite.email !== userEmail) {
                        throw new https_1.HttpsError("permission-denied", "Invite email does not match signed-in user.");
                    }
                    roleRef = db.collection("clinics").doc(clinicId)
                        .collection("roles").doc(invite.roleId);
                    return [4 /*yield*/, roleRef.get()];
                case 2:
                    roleSnap = _k.sent();
                    if (!roleSnap.exists) {
                        throw new https_1.HttpsError("invalid-argument", "Role no longer exists.");
                    }
                    rolePermissions = (_f = (_e = roleSnap.data()) === null || _e === void 0 ? void 0 : _e.permissions) !== null && _f !== void 0 ? _f : {};
                    flattened = (0, permissions_1.flattenPermissions)(rolePermissions);
                    now = admin.firestore.FieldValue.serverTimestamp();
                    memberRef = db.collection("clinics").doc(clinicId)
                        .collection("members").doc(uid);
                    userMembershipRef = db.collection("users").doc(uid)
                        .collection("memberships").doc(clinicId);
                    return [4 /*yield*/, db.collection("clinics").doc(clinicId).get()];
                case 3:
                    clinicSnap = _k.sent();
                    clinicName = (_j = (_h = (_g = clinicSnap.data()) === null || _g === void 0 ? void 0 : _g.profile) === null || _h === void 0 ? void 0 : _h.name) !== null && _j !== void 0 ? _j : clinicId;
                    batch = db.batch();
                    batch.set(memberRef, {
                        roleId: invite.roleId,
                        permissions: flattened,
                        active: true,
                        createdAt: now,
                        updatedAt: now,
                    });
                    batch.set(userMembershipRef, {
                        clinicNameCache: clinicName,
                        roleId: invite.roleId,
                        active: true,
                        createdAt: now,
                    });
                    batch.update(inviteSnap.ref, {
                        status: "accepted",
                        acceptedAt: now,
                        acceptedByUid: uid,
                    });
                    return [4 /*yield*/, batch.commit()];
                case 4:
                    _k.sent();
                    return [2 /*return*/, { success: true, clinicId: clinicId }];
            }
        });
    });
}
