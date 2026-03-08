"use strict";
/**
 * Canonical JSON and SHA-256 hash for projection payloads.
 * Used for caching and no-op write detection.
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.canonicalize = canonicalize;
exports.canonicalJson = canonicalJson;
exports.sha256Hex = sha256Hex;
const crypto = __importStar(require("crypto"));
/**
 * Recursively sort object keys so that JSON.stringify produces a stable string.
 * Arrays are left in order; only object keys are sorted.
 */
function canonicalize(obj) {
    if (obj === null || typeof obj !== "object") {
        return obj;
    }
    if (Array.isArray(obj)) {
        return obj.map(canonicalize);
    }
    const sorted = {};
    const keys = Object.keys(obj).sort();
    for (const k of keys) {
        sorted[k] = canonicalize(obj[k]);
    }
    return sorted;
}
/**
 * Returns a stable JSON string (sorted keys) for the given object.
 */
function canonicalJson(obj) {
    return JSON.stringify(canonicalize(obj));
}
/**
 * SHA-256 hex digest of the canonical JSON of the given object.
 */
function sha256Hex(obj) {
    const str = canonicalJson(obj);
    return crypto.createHash("sha256").update(str, "utf8").digest("hex");
}
//# sourceMappingURL=hash.js.map