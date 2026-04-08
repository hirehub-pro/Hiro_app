"use strict";
// Copyright (c) 2023 Apple Inc. Licensed under MIT License.
Object.defineProperty(exports, "__esModule", { value: true });
exports.OfferTypeValidator = exports.OfferType = void 0;
const Validator_1 = require("./Validator");
/**
 * The type of subscription offer.
 *
 * {@link https://developer.apple.com/documentation/appstoreserverapi/offertype offerType}
 */
var OfferType;
(function (OfferType) {
    OfferType[OfferType["INTRODUCTORY_OFFER"] = 1] = "INTRODUCTORY_OFFER";
    OfferType[OfferType["PROMOTIONAL_OFFER"] = 2] = "PROMOTIONAL_OFFER";
    OfferType[OfferType["SUBSCRIPTION_OFFER_CODE"] = 3] = "SUBSCRIPTION_OFFER_CODE";
    OfferType[OfferType["WIN_BACK_OFFER"] = 4] = "WIN_BACK_OFFER";
})(OfferType || (exports.OfferType = OfferType = {}));
class OfferTypeValidator extends Validator_1.NumberValidator {
}
exports.OfferTypeValidator = OfferTypeValidator;
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiT2ZmZXJUeXBlLmpzIiwic291cmNlUm9vdCI6IiIsInNvdXJjZXMiOlsiLi4vLi4vbW9kZWxzL09mZmVyVHlwZS50cyJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiO0FBQUEsNERBQTREOzs7QUFFNUQsMkNBQThDO0FBRTlDOzs7O0dBSUc7QUFDSCxJQUFZLFNBS1g7QUFMRCxXQUFZLFNBQVM7SUFDakIscUVBQXNCLENBQUE7SUFDdEIsbUVBQXFCLENBQUE7SUFDckIsK0VBQTJCLENBQUE7SUFDM0IsNkRBQWtCLENBQUE7QUFDdEIsQ0FBQyxFQUxXLFNBQVMseUJBQVQsU0FBUyxRQUtwQjtBQUVELE1BQWEsa0JBQW1CLFNBQVEsMkJBQWU7Q0FBRztBQUExRCxnREFBMEQiLCJzb3VyY2VzQ29udGVudCI6WyIvLyBDb3B5cmlnaHQgKGMpIDIwMjMgQXBwbGUgSW5jLiBMaWNlbnNlZCB1bmRlciBNSVQgTGljZW5zZS5cblxuaW1wb3J0IHsgTnVtYmVyVmFsaWRhdG9yIH0gZnJvbSBcIi4vVmFsaWRhdG9yXCI7XG5cbi8qKlxuICogVGhlIHR5cGUgb2Ygc3Vic2NyaXB0aW9uIG9mZmVyLlxuICpcbiAqIHtAbGluayBodHRwczovL2RldmVsb3Blci5hcHBsZS5jb20vZG9jdW1lbnRhdGlvbi9hcHBzdG9yZXNlcnZlcmFwaS9vZmZlcnR5cGUgb2ZmZXJUeXBlfVxuICovXG5leHBvcnQgZW51bSBPZmZlclR5cGUge1xuICAgIElOVFJPRFVDVE9SWV9PRkZFUiA9IDEsXG4gICAgUFJPTU9USU9OQUxfT0ZGRVIgPSAyLFxuICAgIFNVQlNDUklQVElPTl9PRkZFUl9DT0RFID0gMyxcbiAgICBXSU5fQkFDS19PRkZFUiA9IDQsXG59XG5cbmV4cG9ydCBjbGFzcyBPZmZlclR5cGVWYWxpZGF0b3IgZXh0ZW5kcyBOdW1iZXJWYWxpZGF0b3Ige30iXX0=