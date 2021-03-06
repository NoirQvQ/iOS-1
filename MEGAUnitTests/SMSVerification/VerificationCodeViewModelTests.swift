import XCTest
@testable import MEGA

final class VerificationCodeViewModelTests: XCTestCase {
    
    func testAction_onViewReady_addPhoneNumber() {
        let sut = VerificationCodeViewModel(router: MockVerificationCodeViewRouter(),
                                            checkSMSUseCase: MockCheckSMSUseCase(),
                                            authUseCase: MockAuthUseCase(),
                                            verificationType: .addPhoneNumber,
                                            phoneNumber: "+64273142791")
        
        test(viewModel: sut,
             action: VerificationCodeAction.onViewReady,
             expectedCommands: [.configView(phoneNumber: "+64 27 314 2791", screenTitle: AMLocalizedString("Add Phone Number"))])
    }
    
    func testAction_onViewReady_unblockAccount() {
        let sut = VerificationCodeViewModel(router: MockVerificationCodeViewRouter(),
                                            checkSMSUseCase: MockCheckSMSUseCase(),
                                            authUseCase: MockAuthUseCase(),
                                            verificationType: .unblockAccount,
                                            phoneNumber: "+64273142791")
        
        test(viewModel: sut,
             action: VerificationCodeAction.onViewReady,
             expectedCommands: [.configView(phoneNumber: "+64 27 314 2791", screenTitle: AMLocalizedString("Verify Your Account"))])
    }

    func testAction_resendCode() {
        let router = MockVerificationCodeViewRouter()
        let sut = VerificationCodeViewModel(router: router,
                                            checkSMSUseCase: MockCheckSMSUseCase(),
                                            authUseCase: MockAuthUseCase(),
                                            verificationType: .addPhoneNumber,
                                            phoneNumber: "")
        
        test(viewModel: sut, action: VerificationCodeAction.resendCode, expectedCommands: [])
        XCTAssertEqual(router.goBack_calledTimes, 1)
    }
    
    func testAction_didCheckCodeSucceeded_addPhoneNumber() {
        let router = MockVerificationCodeViewRouter()
        let sut = VerificationCodeViewModel(router: router,
                                            checkSMSUseCase: MockCheckSMSUseCase(),
                                            authUseCase: MockAuthUseCase(),
                                            verificationType: .addPhoneNumber,
                                            phoneNumber: "")
        
        test(viewModel: sut, action: VerificationCodeAction.didCheckCodeSucceeded, expectedCommands: [])
        XCTAssertEqual(router.dismiss_calledTimes, 1)
    }
    
    func testAction_didCheckCodeSucceeded_unblockAccount_notLogin() {
        let router = MockVerificationCodeViewRouter()
        let sut = VerificationCodeViewModel(router: router,
                                            checkSMSUseCase: MockCheckSMSUseCase(),
                                            authUseCase: MockAuthUseCase(),
                                            verificationType: .unblockAccount,
                                            phoneNumber: "")
        
        test(viewModel: sut, action: VerificationCodeAction.didCheckCodeSucceeded, expectedCommands: [])
        XCTAssertEqual(router.dismiss_calledTimes, 1)
        XCTAssertEqual(router.goToOnboarding_calledTimes, 1)
    }
    
    func testAction_didCheckCodeSucceeded_unblockAccount_login() {
        let router = MockVerificationCodeViewRouter()
        let sut = VerificationCodeViewModel(router: router,
                                            checkSMSUseCase: MockCheckSMSUseCase(),
                                            authUseCase: MockAuthUseCase(loginSessionId: "mockSessionId"),
                                            verificationType: .unblockAccount,
                                            phoneNumber: "")
        
        test(viewModel: sut, action: VerificationCodeAction.didCheckCodeSucceeded, expectedCommands: [])
        XCTAssertEqual(router.dismiss_calledTimes, 1)
    }
    
    func testAction_checkVerificationCode_success() {
        let sut = VerificationCodeViewModel(router: MockVerificationCodeViewRouter(),
                                            checkSMSUseCase: MockCheckSMSUseCase(checkCodeResult: .success("")),
                                            authUseCase: MockAuthUseCase(),
                                            verificationType: .unblockAccount,
                                            phoneNumber: "")
        
        test(viewModel: sut,
             action: VerificationCodeAction.checkVerificationCode(""),
             expectedCommands: [.startLoading,
                                .finishLoading,
                                .checkCodeSucceeded])
    }
    
    func testAction_checkVerificationCode_error() {
        let errorMessageDict: [CheckSMSErrorEntity: String] =
            [.reachedDailyLimit: AMLocalizedString("You have reached the daily limit"),
             .codeDoesNotMatch: AMLocalizedString("The verification code doesn't match."),
             .alreadyVerifiedWithAnotherAccount: AMLocalizedString("Your account is already verified"),
             .generic: AMLocalizedString("Unknown error")]
        
        for (error, message) in errorMessageDict {
            let sut = VerificationCodeViewModel(router: MockVerificationCodeViewRouter(),
                                                checkSMSUseCase: MockCheckSMSUseCase(checkCodeResult: .failure(error)),
                                                authUseCase: MockAuthUseCase(),
                                                verificationType: .unblockAccount,
                                                phoneNumber: "")
            
            test(viewModel: sut,
                 action: VerificationCodeAction.checkVerificationCode(""),
                 expectedCommands: [.startLoading,
                                    .finishLoading,
                                    .checkCodeError(message: message)])
        }
    }
}

final class MockVerificationCodeViewRouter: VerificationCodeViewRouting {
    var dismiss_calledTimes = 0
    var goBack_calledTimes = 0
    var goToOnboarding_calledTimes = 0
    
    func dismiss() {
        dismiss_calledTimes += 1
    }
    
    func goBack() {
        goBack_calledTimes += 1
    }
    
    func goToOnboarding() {
        goToOnboarding_calledTimes += 1
    }
}
