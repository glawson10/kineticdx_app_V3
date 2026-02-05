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
exports.inviteMember = inviteMember;
var https_1 = require("firebase-functions/v2/https");
var admin = require("firebase-admin");
var hash_1 = require("./hash");
function inviteMember(req) {
    return __awaiter(this, void 0, void 0, function () {
        var _a, clinicId, email, roleId, db, uid, memberRef, memberSnap, roleRef, roleSnap, rawToken, tokenHash, inviteRef, expiresAt;
        var _b, _c, _d, _e;
        return __generator(this, function (_f) {
            switch (_f.label) {
                case 0:
                    if (!req.auth) {
                        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
                    }
                    _a = (_b = req.data) !== null && _b !== void 0 ? _b : {}, clinicId = _a.clinicId, email = _a.email, roleId = _a.roleId;
                    if (!clinicId || !email || !roleId) {
                        throw new https_1.HttpsError("invalid-argument", "clinicId, email and roleId are required.");
                    }
                    db = admin.firestore();
                    uid = req.auth.uid;
                    memberRef = db.collection("clinics").doc(clinicId)
                        .collection("members").doc(uid);
                    return [4 /*yield*/, memberRef.get()];
                case 1:
                    memberSnap = _f.sent();
                    if (!memberSnap.exists || ((_c = memberSnap.data()) === null || _c === void 0 ? void 0 : _c.active) !== true) {
                        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
                    }
                    if (((_e = (_d = memberSnap.data()) === null || _d === void 0 ? void 0 : _d.permissions) === null || _e === void 0 ? void 0 : _e["members.manage"]) !== true) {
                        throw new https_1.HttpsError("permission-denied", "Insufficient permissions.");
                    }
                    roleRef = db.collection("clinics").doc(clinicId)
                        .collection("roles").doc(roleId);
                    return [4 /*yield*/, roleRef.get()];
                case 2:
                    roleSnap = _f.sent();
                    if (!roleSnap.exists) {
                        throw new https_1.HttpsError("invalid-argument", "Role does not exist.");
                    }
                    rawToken = (0, hash_1.generateToken)();
                    tokenHash = (0, hash_1.hashToken)(rawToken);
                    inviteRef = db.collection("clinics").doc(clinicId)
                        .collection("invites").doc();
                    expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 1000 * 60 * 60 * 24 * 7 // 7 days
                    );
                    return [4 /*yield*/, inviteRef.set({
                            email: email.toLowerCase().trim(),
                            roleId: roleId,
                            tokenHash: tokenHash,
                            status: "pending",
                            createdByUid: uid,
                            createdAt: admin.firestore.FieldValue.serverTimestamp(),
                            expiresAt: expiresAt,
                        })];
                case 3:
                    _f.sent();
                    // TODO: send email here in future
                    // DEV ONLY: return token so you can test accept flow
                    return [2 /*return*/, {
                            success: true,
                            inviteId: inviteRef.id,
                            token: rawToken,
                            expiresAt: expiresAt,
                        }];
            }
        });
    });
}
