// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/ERC2771Helper.sol";
import "../contracts/ContinuousFundraising.sol";

import "@opengsn/contracts/src/forwarder/Forwarder.sol"; // chose specific version to avoid import error: yarn add @opengsn/contracts@2.2.5

contract TokenERC2771Test is Test {
    using ECDSA for bytes32; // for verify with var.recover()

    AllowList allowList;
    FeeSettings feeSettings;

    Token token;
    FakePaymentToken paymentToken;
    //Forwarder trustedForwarder;
    ERC2771Helper ERC2771helper;

    // copied from openGSN IForwarder
    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
        uint256 validUntil;
    }

    address public constant trustedForwarder =
        0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    // DO NOT USE IN PRODUCTION! Key was generated online for testing only.
    uint256 public constant companyAdminPrivateKey =
        0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public companyAdmin; // = 0x38d6703d37988C644D6d31551e9af6dcB762E618;

    address public constant mintAllower =
        0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant investor =
        0x6109709EcFA91A80626FF3989d68f67F5b1dd126;

    address public constant receiver =
        0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant platformHotWallet =
        0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant sender = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    address public constant platformAdmin =
        0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant feeCollector =
        0x0109709eCFa91a80626FF3989D68f67f5b1dD120;

    uint256 public constant tokenFeeDenominator = 100;
    uint256 public constant continuousFundraisingFeeDenominator = 50;
    uint256 public constant personalInviteFeeDenominator = 70;

    bytes32 domainSeparator;
    bytes32 requestType;

    function setUp() public {
        // calculate address
        companyAdmin = vm.addr(companyAdminPrivateKey);

        // deploy allow list
        vm.prank(platformAdmin);
        allowList = new AllowList();

        // deploy fee settings
        Fees memory fees = Fees(
            tokenFeeDenominator,
            continuousFundraisingFeeDenominator,
            personalInviteFeeDenominator,
            0
        );
        vm.prank(platformAdmin);
        feeSettings = new FeeSettings(fees, feeCollector);

        // deploy helper functions (only for testing with foundry)
        ERC2771helper = new ERC2771Helper();
    }

    /**
     * this test executes several EIP-2771 transactions on several contracts with the same domainSeparator
     * and on several functions with different signatures but using the same requestTypeHash
     */
    function testSeveralContractsOneDomainSeparator() public {
        Forwarder _forwarder = new Forwarder();
        uint256 _tokenMintAmount = 1000 * 10 ** 18;

        // deploy company token
        token = new Token(
            address(_forwarder),
            feeSettings,
            companyAdmin,
            allowList,
            0x0,
            "TESTTOKEN",
            "TEST"
        );

        // deploy fundraising
        paymentToken = new FakePaymentToken(6 * 10 ** 18, 18);
        vm.prank(companyAdmin);
        ContinuousFundraising raise = new ContinuousFundraising(
            address(_forwarder),
            payable(receiver),
            1000 * 10 ** 18,
            2000 * 10 ** 18,
            688,
            10 * 1000 * 10 ** 18,
            paymentToken,
            token
        );

        // register domainSeparator with forwarder
        domainSeparator = ERC2771helper.registerDomain(
            _forwarder,
            "some_string",
            "some_version_string"
        );

        // register request type with forwarder
        requestType = ERC2771helper.registerRequestType(
            _forwarder,
            "some_function_name",
            "no_real_parameters"
        );

        /*
         * increase minting allowance
         */
        //vm.prank(companyAdmin);
        //token.increaseMintingAllowance(companyAdmin, tokenMintAmount);

        // 1. build request
        bytes memory payload = abi.encodeWithSelector(
            token.increaseMintingAllowance.selector,
            companyAdmin,
            _tokenMintAmount
        );

        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: companyAdmin,
            to: address(token),
            value: 0,
            gas: 1000000,
            nonce: _forwarder.getNonce(companyAdmin),
            data: payload,
            validUntil: 0
        });

        bytes memory suffixData = "0";

        // 2. pack and hash request
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    _forwarder._getEncoded(request, requestType, suffixData)
                )
            )
        );

        // 3. sign request
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            companyAdminPrivateKey,
            digest
        );
        bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        require(
            digest.recover(signature) == request.from,
            "FWD: signature mismatch"
        );

        assertEq(
            token.mintingAllowance(companyAdmin),
            0,
            "Minting allowance is not 0"
        );

        // 4.  execute request
        vm.prank(platformHotWallet);
        _forwarder.execute(
            request,
            domainSeparator,
            requestType,
            suffixData,
            signature
        );

        assertEq(
            token.mintingAllowance(companyAdmin),
            _tokenMintAmount,
            "Minting allowance is not tokenMintAmount"
        );

        /*
         * mint tokens
         */

        // 1. build request
        payload = abi.encodeWithSelector(
            token.mint.selector,
            investor,
            _tokenMintAmount
        );

        request = IForwarder.ForwardRequest({
            from: companyAdmin,
            to: address(token),
            value: 0,
            gas: 1000000,
            nonce: _forwarder.getNonce(companyAdmin),
            data: payload,
            validUntil: 0
        });

        // 2. pack and hash request
        digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    _forwarder._getEncoded(request, requestType, suffixData)
                )
            )
        );

        // 3. sign request
        (v, r, s) = vm.sign(companyAdminPrivateKey, digest);
        signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        require(
            digest.recover(signature) == request.from,
            "FWD: signature mismatch"
        );

        // 4.  execute request
        assertEq(
            token.mintingAllowance(companyAdmin),
            _tokenMintAmount,
            "Minting allowance is wrong"
        );
        assertEq(
            token.balanceOf(investor),
            0,
            "Investor has tokens before mint"
        );
        assertEq(
            token.balanceOf(feeCollector),
            0,
            "FeeCollector has tokens before mint"
        );

        // send call through forwarder contract
        vm.prank(platformHotWallet);
        _forwarder.execute(
            request,
            domainSeparator,
            requestType,
            suffixData,
            signature
        );

        assertEq(
            token.balanceOf(investor),
            _tokenMintAmount,
            "Investor received wrong token amount"
        );
        assertEq(
            token.mintingAllowance(companyAdmin),
            0,
            "Minting allowance is not 0 after mint"
        );
        assertEq(
            token.balanceOf(feeCollector),
            feeSettings.tokenFee(_tokenMintAmount),
            "FeeCollector received wrong token amount"
        );

        /*
         * update settings on continuous fundraising
         */

        // build request
        payload = abi.encodeWithSelector(raise.pause.selector);

        request = IForwarder.ForwardRequest({
            from: companyAdmin,
            to: address(raise),
            value: 0,
            gas: 1000000,
            nonce: _forwarder.getNonce(companyAdmin),
            data: payload,
            validUntil: 0
        });

        suffixData = "0";

        // pack and hash request
        digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    _forwarder._getEncoded(request, requestType, suffixData)
                )
            )
        );

        // sign request
        //bytes memory signature
        (v, r, s) = vm.sign(companyAdminPrivateKey, digest);
        signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        require(
            digest.recover(signature) == request.from,
            "FWD: signature mismatch"
        );

        // // encode buy call and sign it https://book.getfoundry.sh/cheatcodes/sign
        // bytes memory buyCallData = abi.encodeWithSignature("buy(uint256)", tokenBuyAmount);

        /*
            execute request and check results
        */
        assertEq(raise.paused(), false);

        // send call through forwarder contract
        _forwarder.execute(
            request,
            domainSeparator,
            requestType,
            suffixData,
            signature
        );
        assertEq(raise.paused(), true);
    }
}
