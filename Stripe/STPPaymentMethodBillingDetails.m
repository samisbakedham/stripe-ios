//
//  STPPaymentMethodBillingDetails.m
//  Stripe
//
//  Created by Yuki Tokuhiro on 3/5/19.
//  Copyright © 2019 Stripe, Inc. All rights reserved.
//

#import "STPPaymentMethodBillingDetails.h"

#import "STPPaymentMethodBillingDetailsAddress.h"
#import "NSDictionary+Stripe.h"

@interface STPPaymentMethodBillingDetails ()

@property (nonatomic, readwrite, nonnull, copy) NSDictionary *allResponseFields;

@end

@implementation STPPaymentMethodBillingDetails

- (NSString *)description {
    NSArray *props = @[
                        // Object
                        [NSString stringWithFormat:@"%@: %p", NSStringFromClass([self class]), self],
                        
                        // Properties
                        [NSString stringWithFormat:@"name = %@", self.name],
                        [NSString stringWithFormat:@"phone = %@", self.phone],
                        [NSString stringWithFormat:@"email = %@", self.email],
                        [NSString stringWithFormat:@"address = %@", self.address],
                        ];
    return [NSString stringWithFormat:@"<%@>", [props componentsJoinedByString:@"; "]];
}

#pragma mark - STPAPIResponseDecodable

+ (nullable instancetype)decodedObjectFromAPIResponse:(nullable NSDictionary *)response {
    NSDictionary *dict = [response stp_dictionaryByRemovingNulls];
    if (!dict) {
        return nil;
    }
    STPPaymentMethodBillingDetails *billingDetails = [self new];
    billingDetails.allResponseFields = dict;
    billingDetails.address = [STPPaymentMethodBillingDetailsAddress decodedObjectFromAPIResponse:[response stp_dictionaryForKey:@"address"]];
    billingDetails.email = [dict stp_stringForKey:@"email"];
    billingDetails.name = [dict stp_stringForKey:@"name"];
    billingDetails.phone = [dict stp_stringForKey:@"phone"];
    return billingDetails;
}

@end
