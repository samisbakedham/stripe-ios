//
//  String+Localized.swift
//  StripeCore
//
//  Created by Mel Ludowise on 8/4/21.
//

import Foundation

@_spi(STP) public extension String {
    enum Localized {
        // TODO(IDPROD-3114): Migrate the localized string `Cancel` from Stripe
        public static var close: String {
            return STPLocalizedString("Close", "Text for close button")
        }
        
        public static var scan_card_title_capitalization: String {
            STPLocalizedString("Scan Card", "Text for button to scan a credit card")
        }
        
        public static var scan_card: String {
            STPLocalizedString("Scan card", "Button title to open camera to scan credit/debit card")
        }
    }
}
