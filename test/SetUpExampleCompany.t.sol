// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/ContinuousFundraising.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/ERC2771Helper.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol"; // chose specific version to avoid import error: yarn add @opengsn/contracts@2.2.5

/**
 * @title Company Setup Example
 * @notice This test is used to demonstrate how to set up a company on the platform. It is not intended to be used as a test, but rather as a reference.
 *          The setUp function will prepare the tokenize.it platform. The test function will then demonstrate how to set up the first of many companys.
 */
contract CompanySetUpTest is Test {
    using ECDSA for bytes32; // for verify with var.recover()

    ContinuousFundraising raise;
    AllowList list;
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

    // this address will be the admin of contracts controlled by the platform (AllowList, FeeSettings)
    address public constant platformAdmin =
        0xDFcEB49eD21aE199b33A76B726E2bea7A72127B0;
    address public constant platformHotWallet =
        0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;

    address public constant trustedForwarder =
        0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant mintAllower =
        0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver =
        0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider =
        0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant sender = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    // DO NOT USE IN PRODUCTION! Key was generated online for testing only.
    uint256 public constant investorPrivateKey =
        0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public investor; // = 0x38d6703d37988C644D6d31551e9af6dcB762E618;

    // DO NOT USE IN PRODUCTION! Key was generated online for testing only.
    uint256 public constant companyAdminPrivateKey =
        0x8da4ef21b864d2cc526dbdb2a120bd2874c36c9d0a1fb7f8c63d7f7a8b41de8f;
    address public companyAdmin; // = 0x63FaC9201494f0bd17B9892B9fae4d52fe3BD377;

    uint8 public constant paymentTokenDecimals = 6;
    uint256 public constant paymentTokenAmount =
        1000 * 10 ** paymentTokenDecimals;

    uint256 public constant price = 7 * 10 ** paymentTokenDecimals; // 7 payment tokens per token

    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10 ** 18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token

    uint256 public constant requirements = 0x3842; // 0b111100000010

    uint256 tokenBuyAmount;
    uint256 costInPaymentToken;

    uint256 tokenFeeDenominator = 100;
    uint256 paymentTokenFeeDenominator = 50;

    function setUp() public {
        // set up AllowList
        vm.prank(platformAdmin);
        list = new AllowList();

        // set up FeeSettings
        Fees memory fees = Fees(
            tokenFeeDenominator,
            paymentTokenFeeDenominator,
            paymentTokenFeeDenominator,
            0
        );
        vm.prank(platformAdmin);
        feeSettings = new FeeSettings(fees, admin);

        // setting up AllowList and FeeSettings is one-time step. These contracts will be used by all companies.

        // derive addresses from the private keys. Irl the addresses would be provided by the wallet that holds their private keys.
        investor = vm.addr(investorPrivateKey);
        companyAdmin = vm.addr(companyAdminPrivateKey);

        // set up currency. In real life (irl) this would be a real currency, but for testing purposes we use a fake one.
        vm.prank(paymentTokenProvider);
        paymentToken = new FakePaymentToken(
            paymentTokenAmount,
            paymentTokenDecimals
        ); // 1000 tokens with 6 decimals
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(investor, paymentTokenAmount); // transfer currency to investor so they can buy tokens later
        assertTrue(paymentToken.balanceOf(investor) == paymentTokenAmount);

        // setting up this helper library will not happen in real life. All functions in this will be written in javascript and executed in the web app.
        // Adding it was necessary to make the meta transactions work in solidity though.
        ERC2771helper = new ERC2771Helper();
    }

    function launchCompanyAndInvest(Forwarder forwarder) public {
        string memory name = "ProductiveExampleCompany";
        string memory symbol = "PEC";

        // launch the company token. The platform deploys the contract. There is no need to transfer ownership, because the token is never controlled by the address that deployed it.
        // Instead, it is immediately controlled by the address provided in the constructor, which is the companyAdmin in this case.
        vm.prank(platformHotWallet);
        token = new Token(
            trustedForwarder,
            feeSettings,
            companyAdmin,
            list,
            requirements,
            name,
            symbol
        );

        // // demonstration of the platform not being in control of the token
        // vm.prank(platformHotWallet);
        // vm.expectRevert();
        // token.pause(); // the platformHotWallet can not pause the token because it does not have the neccessary roles!

        // just some calculations
        tokenBuyAmount = 5 * 10 ** token.decimals();
        costInPaymentToken = (tokenBuyAmount * price) / 10 ** 18;

        // after setting up their company, the company admin might want to launch a fundraising campaign. They choose all settings in the web, but the contract
        // will be deployed by the platform.
        vm.prank(platformHotWallet);
        raise = new ContinuousFundraising(
            address(forwarder),
            payable(receiver),
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            maxAmountOfTokenToBeSold,
            paymentToken,
            token
        );

        // right after deployment, ownership of the fundraising contract is transferred to the company admin.
        vm.prank(platformHotWallet);
        raise.transferOwnership(companyAdmin);

        // the company admin can now enable the fundraising campaign by granting it a token minting allowance.
        // Because the company admin does not hold eth, they will use a meta transaction to call the function.
        // this requires quite some preparation, on the platform's side

        // register a domain separator with the forwarder. The this is a one-time step that will be done by the platform.
        // The domain separator identifies our platform to the forwarder, which prevents replay attacks (using same signature for other dapps).
        bytes32 domainSeparator = ERC2771helper.registerDomain(
            forwarder,
            "tokenize.it", // dapp name
            "v1.0" // dapp version
        );

        // register the function with the forwarder. This is also a one-time step that will be done by the platform once for every function that is called via meta transaction.
        bytes32 requestType = ERC2771helper.registerRequestType(
            forwarder,
            "setMintingAllowance",
            "address _minter, uint256 _allowance"
        );

        // build the message the company admin will sign.
        // build request
        bytes memory payload = abi.encodeWithSelector(
            token.setMintingAllowance.selector,
            address(raise),
            maxAmountOfTokenToBeSold
        );

        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: companyAdmin,
            to: address(token),
            value: 0,
            gas: 1000000,
            nonce: forwarder.getNonce(platformHotWallet),
            data: payload,
            validUntil: block.timestamp + 1 hours // like this, the signature will expire after 1 hour. So the platform hotwallet can take some time to execute the transaction.
        });

        // I honestly don't know why we need to do this.
        bytes memory suffixData = "0";

        // pack and hash request
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    forwarder._getEncoded(request, requestType, suffixData)
                )
            )
        );

        // sign request. This would usually happen in the web app, which would present the companyAdmin with a request to sign the message. Metamask would come up and present the message to sign.
        // If EIP-712 is used properly, Metamask is able to show some information about the contents of the message, too.
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            companyAdminPrivateKey,
            digest
        );
        bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        // check the signature is correct
        require(
            digest.recover(signature) == request.from,
            "FWD: signature mismatch"
        );

        // check the raise contract has no allowance yet
        assertTrue(
            token.mintingAllowance(address(raise)) == maxAmountOfTokenToBeSold
        );
        // If the platform has received the signature, it can now execute the meta transaction.
        vm.prank(platformHotWallet);
        forwarder.execute(
            request,
            domainSeparator,
            requestType,
            suffixData,
            signature
        );

        console.log("Forwarder address: ", address(forwarder));
        console.log(
            "allowance set to: ",
            token.mintingAllowance(address(raise))
        );

        // check the raise contract has the allowance now
        assertTrue(
            token.mintingAllowance(address(raise)) == maxAmountOfTokenToBeSold
        );

        // forwarder.execute(
        //     request,
        //     domainSeparator,
        //     requestType,
        //     suffixData,
        //     signature
        // );

        // // allow raise contract to mint
        // bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        // vm.prank(admin);
        // token.grantRole(roleMintAllower, mintAllower);
        // vm.prank(mintAllower);
        // token.setMintingAllowance(address(raise), maxAmountOfTokenToBeSold);

        // // give raise contract allowance
        // vm.prank(investor);
        // paymentToken.approve(address(raise), paymentTokenAmount);

        // assert(costInPaymentToken == 35 * 10 ** paymentTokenDecimals); // 35 payment tokens, manually calculated

        // /*
        //     create data and signature for execution
        // */
        // // // https://github.com/foundry-rs/foundry/issues/3330
        // // // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol
        // // bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, keccak256(payload));
        // // (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);

        // // todo: get nonce from forwarder

        // // build request
        // bytes memory payload = abi.encodeWithSelector(
        //     raise.buy.selector,
        //     tokenBuyAmount
        // );

        // IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
        //     from: investor,
        //     to: address(raise),
        //     value: 0,
        //     gas: 1000000,
        //     nonce: forwarder.getNonce(investor),
        //     data: payload,
        //     validUntil: 0
        // });

        // bytes memory suffixData = "0";

        // // pack and hash request
        // bytes32 digest = keccak256(
        //     abi.encodePacked(
        //         "\x19\x01",
        //         domainSeparator,
        //         keccak256(
        //             forwarder._getEncoded(request, requestType, suffixData)
        //         )
        //     )
        // );

        // // sign request
        // //bytes memory signature
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(investorPrivateKey, digest);
        // bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        // require(
        //     digest.recover(signature) == request.from,
        //     "FWD: signature mismatch"
        // );

        // // // encode buy call and sign it https://book.getfoundry.sh/cheatcodes/sign
        // // bytes memory buyCallData = abi.encodeWithSignature("buy(uint256)", tokenBuyAmount);

        // /*
        //     execute request and check results
        // */
        // vm.prank(investor);
        // assertEq(token.balanceOf(investor), 0);
        // assertEq(paymentToken.balanceOf(receiver), 0);
        // assertEq(paymentToken.balanceOf(address(raise)), 0);
        // assertEq(token.balanceOf(address(raise)), 0);
        // assertEq(token.balanceOf(receiver), 0);
        // assertEq(token.balanceOf(address(forwarder)), 0);
        // assertTrue(raise.tokensSold() == 0);
        // assertTrue(raise.tokensBought(investor) == 0);
        // //assertTrue(vm.getNonce(buyer) == 0); // it seems forge does not increase nonces with prank

        // console.log(
        //     "Token balance of buyer before: ",
        //     token.balanceOf(investor)
        // );
        // console.log("eth balance of buyer ", investor.balance);

        // // send call through forwarder contract
        // uint256 gasBefore = gasleft();
        // forwarder.execute(
        //     request,
        //     domainSeparator,
        //     requestType,
        //     suffixData,
        //     signature
        // );
        // // vm.prank(buyer);
        // // raise.buy(tokenBuyAmount);
        // console.log("Gas used: ", gasBefore - gasleft());

        // // investor receives as many tokens as they paid for
        // assertTrue(token.balanceOf(investor) == tokenBuyAmount);
        // // but fee collector receives additional tokens
        // assertTrue(
        //     token.balanceOf(feeSettings.feeCollector()) ==
        //         tokenBuyAmount / tokenFeeDenominator
        // );

        // // receiver receives payment tokens after fee has been deducted
        // assertEq(
        //     paymentToken.balanceOf(receiver),
        //     costInPaymentToken - costInPaymentToken / paymentTokenFeeDenominator
        // );
        // // fee collector receives fee in payment tokens
        // assertEq(
        //     paymentToken.balanceOf(feeSettings.feeCollector()),
        //     costInPaymentToken / paymentTokenFeeDenominator
        // );

        // assertEq(paymentToken.balanceOf(address(raise)), 0);
        // assertEq(token.balanceOf(address(raise)), 0);
        // assertEq(token.balanceOf(receiver), 0);
        // assertEq(token.balanceOf(address(forwarder)), 0);
        // assertTrue(raise.tokensSold() == tokenBuyAmount);
        // assertTrue(raise.tokensBought(investor) == tokenBuyAmount);
        // //assertTrue(vm.getNonce(buyer) == 0);

        // console.log(
        //     "paymentToken balance of receiver after: ",
        //     paymentToken.balanceOf(receiver)
        // );
        // console.log(
        //     "Token balance of buyer after: ",
        //     token.balanceOf(investor)
        // );

        // /*
        //     try to execute request again (must fail)
        // */
        // vm.expectRevert("FWD: nonce mismatch");
        // forwarder.execute(
        //     request,
        //     domainSeparator,
        //     requestType,
        //     suffixData,
        //     signature
        // );
    }

    function testLaunchCompanyAndInvestWithLocalForwarder() public {
        launchCompanyAndInvest(new Forwarder());
    }

    // function testBuyWithMainnetGSNForwarder() public {
    //     // uses deployed forwarder on mainnet with fork. https://docs-v2.opengsn.org/networks/ethereum/mainnet.html
    //     buyWithERC2771(
    //         Forwarder(payable(0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA))
    //     );
    // }
}
