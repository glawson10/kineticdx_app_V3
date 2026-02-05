"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateToken = generateToken;
exports.hashToken = hashToken;
var crypto = require("crypto");
function generateToken() {
    return crypto.randomBytes(32).toString("hex");
}
function hashToken(token) {
    return crypto.createHash("sha256").update(token).digest("hex");
}
