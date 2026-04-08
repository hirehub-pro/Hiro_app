import { StringValidator } from "./Validator";
/**
 * The payment mode you configure for an introductory offer, promotional offer, or offer code on an auto-renewable subscription.
 *
 * {@link https://developer.apple.com/documentation/appstoreserverapi/offerdiscounttype offerDiscountType}
 */
export declare enum OfferDiscountType {
    FREE_TRIAL = "FREE_TRIAL",
    PAY_AS_YOU_GO = "PAY_AS_YOU_GO",
    PAY_UP_FRONT = "PAY_UP_FRONT"
}
export declare class OfferDiscountTypeValidator extends StringValidator {
}
