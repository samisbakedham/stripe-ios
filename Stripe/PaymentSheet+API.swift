//
//  PaymentSheet+API.swift
//  StripeiOS
//
//  Created by Yuki Tokuhiro on 12/10/20.
//  Copyright © 2020 Stripe, Inc. All rights reserved.
//

import Foundation
import UIKit
@_spi(STP) import StripeCore
@_spi(STP) import StripeUICore

@available(iOSApplicationExtension, unavailable)
@available(macCatalystApplicationExtension, unavailable)
extension PaymentSheet {
    /// Confirms a PaymentIntent with the given PaymentOption and returns a PaymentResult
    static func confirm(
        configuration: PaymentSheet.Configuration,
        authenticationContext: STPAuthenticationContext,
        intent: Intent,
        paymentOption: PaymentOption,
        completion: @escaping (PaymentSheetResult) -> Void
    ) {
        let paymentHandler = STPPaymentHandler(apiClient: configuration.apiClient)
        // Translates a STPPaymentHandler result to a PaymentResult
        let paymentHandlerCompletion: (STPPaymentHandlerActionStatus, NSObject?, NSError?) -> Void =
            {
                (status, _, error) in
                
                if let paymentSheetAuthenticationContext = authenticationContext as? PaymentSheetAuthenticationContext {
                    // reset
                    paymentSheetAuthenticationContext.linkPaymentDetails = nil
                }
                
                switch status {
                case .canceled:
                    completion(.canceled)
                case .failed:
                    // Hold a strong reference to paymentHandler
                    let unknownError = PaymentSheetError.unknown(debugDescription: "STPPaymentHandler failed without an error: \(paymentHandler.description)")
                    completion(.failed(error: error ?? unknownError))
                case .succeeded:
                    completion(.completed)
                }
            }

        switch paymentOption {
        // MARK: Apple Pay
        case .applePay:
            guard let applePayConfiguration = configuration.applePay,
                let applePayContext = STPApplePayContext.create(
                    intent: intent,
                    merchantName: configuration.merchantDisplayName,
                    configuration: applePayConfiguration,
                    completion: completion)
            else {
                let message =
                    "Attempted Apple Pay but it's not supported by the device, not configured, or missing a presenter"
                assertionFailure(message)
                completion(.failed(error: PaymentSheetError.unknown(debugDescription: message)))
                return
            }
            applePayContext.presentApplePay()

        // MARK: New Payment Method
        case let .new(confirmParams):
            switch intent {
            // MARK: PaymentIntent
            case .paymentIntent(let paymentIntent):
                // The Dashboard app's user key (uk_) cannot pass `paymenMethodParams` ie payment_method_data
                if configuration.apiClient.publishableKey?.hasPrefix("uk_") ?? false {
                    configuration.apiClient.createPaymentMethod(with: confirmParams.paymentMethodParams) {
                        paymentMethod, error in
                        if let error = error {
                            completion(.failed(error: error))
                            return
                        }
                        let paymentIntentParams = confirmParams.makeDashboardParams(
                            paymentIntentClientSecret: paymentIntent.clientSecret,
                            paymentMethodID: paymentMethod?.stripeId ?? ""
                        )
                        paymentHandler.confirmPayment(
                            paymentIntentParams,
                            with: authenticationContext,
                            completion: paymentHandlerCompletion)
                    }
                } else {
                    let paymentIntentParams = confirmParams.makeParams(paymentIntentClientSecret: paymentIntent.clientSecret)
                    paymentIntentParams.returnURL = configuration.returnURL
                    paymentHandler.confirmPayment(paymentIntentParams,
                                                  with: authenticationContext,
                                                  completion: paymentHandlerCompletion)
                }
            // MARK: SetupIntent
            case .setupIntent(let setupIntent):
                let setupIntentParams = confirmParams.makeParams(setupIntentClientSecret: setupIntent.clientSecret)
                setupIntentParams.returnURL = configuration.returnURL
                paymentHandler.confirmSetupIntent(
                    setupIntentParams,
                    with: authenticationContext,
                    completion: paymentHandlerCompletion)
            }

        // MARK: Saved Payment Method
        case let .saved(paymentMethod):
            switch intent {
            // MARK: PaymentIntent
            case .paymentIntent(let paymentIntent):
                let paymentIntentParams = STPPaymentIntentParams(clientSecret: paymentIntent.clientSecret)
                paymentIntentParams.returnURL = configuration.returnURL
                paymentIntentParams.paymentMethodId = paymentMethod.stripeId
                // Overwrite in case payment_method_options was set previously - we don't want to save an already-saved payment method
                paymentIntentParams.paymentMethodOptions = STPConfirmPaymentMethodOptions()
                paymentIntentParams.paymentMethodOptions?.setSetupFutureUsageIfNecessary(false, paymentMethodType: paymentMethod.type)
                
                paymentHandler.confirmPayment(
                    paymentIntentParams,
                    with: authenticationContext,
                    completion: paymentHandlerCompletion)
            // MARK: SetupIntent
            case .setupIntent(let setupIntent):
                let setupIntentParams = STPSetupIntentConfirmParams(
                    clientSecret: setupIntent.clientSecret)
                setupIntentParams.returnURL = configuration.returnURL
                setupIntentParams.paymentMethodID = paymentMethod.stripeId
                paymentHandler.confirmSetupIntent(
                    setupIntentParams,
                    with: authenticationContext,
                    completion: paymentHandlerCompletion)

            }
            
        case .link(let linkAccount, let confirmOption):
            let confirmWithPaymentDetails: (ConsumerPaymentDetails) -> Void = { paymentDetails in
                if let paymentSheetAuthenticationContext = authenticationContext as? PaymentSheetAuthenticationContext {
                    paymentSheetAuthenticationContext.linkPaymentDetails = (linkAccount, paymentDetails)
                    
                    switch intent {
                    case .paymentIntent(let paymentIntent):
                        let paymentIntentParams = STPPaymentIntentParams(clientSecret: paymentIntent.clientSecret)
                        paymentIntentParams.paymentMethodParams = STPPaymentMethodParams(type: .link)
                        paymentIntentParams.returnURL = configuration.returnURL
                        paymentHandler.confirmPayment(paymentIntentParams,
                                                      with: authenticationContext,
                                                      completion: paymentHandlerCompletion)
                        
                    case .setupIntent(let setupIntent):
                        let setupIntentParams = STPSetupIntentConfirmParams(clientSecret: setupIntent.clientSecret)
                        setupIntentParams.paymentMethodParams = STPPaymentMethodParams(type: .link)
                        setupIntentParams.returnURL = configuration.returnURL
                        paymentHandler.confirmSetupIntent(
                            setupIntentParams,
                            with: authenticationContext,
                            completion: paymentHandlerCompletion)
                    }
                } else {
                    assertionFailure("Link only available if authenticationContest is PaymentSheetAuthenticationContext")
                    completion(.failed(error: NSError.stp_genericConnectionError()))
                }
            }

            let confirmWithPaymentMethodParams: (STPPaymentMethodParams) -> Void = { paymentMethodParams in
                linkAccount.createPaymentDetails(with: paymentMethodParams) { paymentDetails, paymentDetailsError in
                    if let paymentDetails = paymentDetails {
                        confirmWithPaymentDetails(paymentDetails)
                    } else {
                        completion(.failed(error: paymentDetailsError ?? NSError.stp_genericConnectionError()))
                    }
                }
            }

            switch confirmOption {
            case .forNewAccount(phoneNumber: let phoneNumber, paymentMethodParams: let paymentMethodParams):
                linkAccount.signUp(with: phoneNumber) { signUpError in
                    if let error = signUpError {
                        completion(.failed(error: error))
                    } else {
                        confirmWithPaymentMethodParams(paymentMethodParams)
                    }
                }
            case .withPaymentDetails(paymentDetails: let paymentDetails):
                confirmWithPaymentDetails(paymentDetails)
            case .withPaymentMethodParams(let paymentMethodParams):
                confirmWithPaymentMethodParams(paymentMethodParams)
            }

        }
    }

    /// Fetches the PaymentIntent or SetupIntent and Customer's saved PaymentMethods
    static func load(
        clientSecret: IntentClientSecret,
        configuration: Configuration,
        completion: @escaping ((Result<(Intent, [STPPaymentMethod], PaymentSheetLinkAccount?), Error>) -> Void)
    ) {
        let intentPromise = Promise<Intent>()
        let paymentMethodsPromise = Promise<[STPPaymentMethod]>()
        let loadSpecsPromise = Promise<Void>()
        let linkAccountPromise = Promise<PaymentSheetLinkAccount?>()
        
        intentPromise.observe { result in
            switch result {
            case .success(let intent):
                paymentMethodsPromise.observe { result in
                    switch result {
                    case .success(let paymentMethods):
                        // Filter out payment methods that the PI/SI or PaymentSheet doesn't support
                        let savedPaymentMethods = paymentMethods
                            .filter { intent.recommendedPaymentMethodTypes.contains($0.type) }
                            .filter { PaymentSheet.supportsSaveAndReuse(paymentMethod: $0.type, configuration: configuration, intent: intent) }
                        warnUnactivatedIfNeeded(unactivatedPaymentMethodTypes: intent.unactivatedPaymentMethodTypes)
                        loadSpecsPromise.observe { _ in
                            linkAccountPromise.observe { linkAccountResult in
                                switch linkAccountResult {
                                case .success(let linkAccount):
                                    completion(.success((intent, savedPaymentMethods, intent.recommendedPaymentMethodTypes.contains(.link) ? linkAccount : nil)))
                                case .failure(let error):
                                    completion(.failure(error))
                                }
                            }
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }

        // Fetch PaymentIntent or SetupIntent
        switch clientSecret {
        case .paymentIntent(let clientSecret):
            let paymentIntentHandlerCompletionBlock: ((STPPaymentIntent) -> Void) = { paymentIntent in
                guard ![.succeeded, .canceled, .requiresCapture].contains(paymentIntent.status) else {
                    // Error if the PaymentIntent is in a terminal state
                    let message = "PaymentSheet received a PaymentIntent in a terminal state: \(paymentIntent.status)"
                    completion(.failure(PaymentSheetError.unknown(debugDescription: message)))
                    return
                }
                intentPromise.resolve(with: .paymentIntent(paymentIntent))
            }

            configuration.apiClient.retrievePaymentIntentWithPreferences(withClientSecret: clientSecret) { result in
                switch result {
                case .success(let paymentIntent):
                    paymentIntentHandlerCompletionBlock(paymentIntent)
                case .failure(_):
                    // Fallback to regular retrieve PI when retrieve PI with preferences fails
                    configuration.apiClient.retrievePaymentIntent(withClientSecret: clientSecret) {
                        paymentIntent, error in
                        guard let paymentIntent = paymentIntent, error == nil else {
                            let error =
                                error
                                ?? PaymentSheetError.unknown(
                                    debugDescription: "Failed to retrieve PaymentIntent")
                            intentPromise.reject(with: error)
                            return
                        }

                        paymentIntentHandlerCompletionBlock(paymentIntent)
                    }
                }
            }
        case .setupIntent(let clientSecret):
            let setupIntentHandlerCompletionBlock: ((STPSetupIntent) -> Void) = { setupIntent in
                guard ![.succeeded, .canceled].contains(setupIntent.status) else {
                    // Error if the SetupIntent is in a terminal state
                    let message = "PaymentSheet received a SetupIntent in a terminal state: \(setupIntent.status)"
                    completion(.failure(PaymentSheetError.unknown(debugDescription: message)))
                    return
                }
                intentPromise.resolve(with: .setupIntent(setupIntent))
            }

            configuration.apiClient.retrieveSetupIntentWithPreferences(withClientSecret: clientSecret) { result in
                switch result {
                case .success(let setupIntent):
                    setupIntentHandlerCompletionBlock(setupIntent)
                case .failure(_):
                    // Fallback to regular retrieve SI when retrieve SI with preferences fails
                    configuration.apiClient.retrieveSetupIntent(withClientSecret: clientSecret) { setupIntent, error in
                        guard let setupIntent = setupIntent, error == nil else {
                            let error =
                                error
                                ?? PaymentSheetError.unknown(
                                    debugDescription: "Failed to retrieve SetupIntent")
                            intentPromise.reject(with: error)
                            return
                        }

                        setupIntentHandlerCompletionBlock(setupIntent)
                    }
                }
            }
        }

        // List the Customer's saved PaymentMethods
        let savedPaymentMethodTypes: [STPPaymentMethodType] = [.card] // hardcoded for now
        if let customerID = configuration.customer?.id, let ephemeralKey = configuration.customer?.ephemeralKeySecret {
            configuration.apiClient.listPaymentMethods(
                forCustomer: customerID,
                using: ephemeralKey,
                types: savedPaymentMethodTypes
            ) { paymentMethods, error in
                guard let paymentMethods = paymentMethods, error == nil else {
                    let error = error ?? PaymentSheetError.unknown(
                        debugDescription: "Failed to retrieve PaymentMethods for the customer"
                    )
                    paymentMethodsPromise.reject(with: error)
                    return
                }
                paymentMethodsPromise.resolve(with: paymentMethods)
            }
        } else {
            paymentMethodsPromise.resolve(with: [])
        }
        
        // Load configuration
        AddressSpecProvider.shared.loadAddressSpecs {
            loadSpecsPromise.resolve(with: ())
        }

        // Look up ConsumerSession
        let linkAccountService = LinkAccountService(apiClient: configuration.apiClient)
        let consumerSessionLookupBlock: (String?) -> Void = { email in
            linkAccountService.lookupAccount(withEmail: email) { result in
                switch result {
                case .success(let linkAccount):
                    linkAccountPromise.resolve(with: linkAccount)
                case .failure(let error):
                    linkAccountPromise.reject(with: error)
                }
            }
        }
        
        if linkAccountService.hasSessionCookie {
            consumerSessionLookupBlock(nil)
        } else if let email = configuration.customerEmail, !linkAccountService.hasEmailLoggedOut(email: email) {
            consumerSessionLookupBlock(email)
        } else if let customerID = configuration.customer?.id, let ephemeralKey = configuration.customer?.ephemeralKeySecret {
            configuration.apiClient.retrieveCustomer(customerID, using: ephemeralKey) { customer, _ in
                // If there's an error in this call we can just ignore it
                consumerSessionLookupBlock(customer?.email)
            }
        } else {
            linkAccountPromise.resolve(with: nil)
        }
    }
    
    private static func warnUnactivatedIfNeeded(unactivatedPaymentMethodTypes: [STPPaymentMethodType]) {
        guard !unactivatedPaymentMethodTypes.isEmpty else { return }
        
        let message = """
            [Stripe SDK] Warning: Your Intent contains the following payment method types which are activated for test mode but not activated for live mode: \(unactivatedPaymentMethodTypes.map({$0.displayName}).joined(separator: ",")). These payment method types will not be displayed in live mode until they are activated. To activate these payment method types visit your Stripe dashboard.
            More information: https://support.stripe.com/questions/activate-a-new-payment-method
            """
        print(message)
    }
}

/// Internal authentication context for PaymentSheet magic
protocol PaymentSheetAuthenticationContext: STPAuthenticationContext {
    func present(_ threeDS2ChallengeViewController: UIViewController, completion: @escaping () -> Void)
    func dismiss(_ threeDS2ChallengeViewController: UIViewController)
    
    var linkPaymentDetails: (PaymentSheetLinkAccount, ConsumerPaymentDetails)? { get set }
}
