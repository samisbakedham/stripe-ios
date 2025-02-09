//
//  BiometricConsentViewControllerTest.swift
//  StripeIdentityTests
//
//  Created by Mel Ludowise on 2/14/22.
//

import Foundation
import XCTest
@testable import StripeIdentity

final class BiometricConsentViewControllerTest: XCTestCase {

    static let mockVerificationPage = try! VerificationPageMock.response200.make()

    private var vc: BiometricConsentViewController!
    private let mockSheetController = VerificationSheetControllerMock()

    override func setUp() {
        super.setUp()

        vc = try! BiometricConsentViewController(
            merchantLogo: UIImage(),
            consentContent: BiometricConsentViewControllerTest.mockVerificationPage.biometricConsent,
            sheetController: mockSheetController
        )
    }

    func testAccept() {
        // Tap accept button
        vc.flowViewModel.buttons.first?.didTap()

        // Verify biometricConsent is saved
        XCTAssertEqual(mockSheetController.dataStore.biometricConsent, true)
        XCTAssertTrue(mockSheetController.didRequestSaveData)
    }

    func testDeny() {
        // Tap accept button
        vc.flowViewModel.buttons.last?.didTap()

        // Verify biometricConsent is saved
        XCTAssertEqual(mockSheetController.dataStore.biometricConsent, false)
        XCTAssertTrue(mockSheetController.didRequestSaveData)
    }
}
