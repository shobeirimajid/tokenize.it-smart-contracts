// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/PersonalInvite.sol";
import "../contracts/PersonalInviteFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";

contract PersonalInviteTest is Test {
    PersonalInviteFactory factory;

    AllowList list;
    FeeSettings feeSettings;
    Token token;
    FakePaymentToken currency;

    uint256 MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant tokenReceiver =
        0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower =
        0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant currencyPayer =
        0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant currencyReceiver =
        0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider =
        0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder =
        0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint256 public constant price = 10000000;

    uint256 requirements = 92785934;

    function setUp() public {
        factory = new PersonalInviteFactory();
        list = new AllowList();

        list.set(tokenReceiver, requirements);

        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = new FeeSettings(fees, admin);

        token = new Token(
            trustedForwarder,
            feeSettings,
            admin,
            list,
            requirements,
            "token",
            "TOK"
        );
        vm.prank(paymentTokenProvider);
        currency = new FakePaymentToken(0, 18);
    }

    function testAcceptDeal(uint256 rawSalt) public {
        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            )
        );

        //uint rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        //bytes memory creationCode = type(PersonalInvite).creationCode;
        uint256 amount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;

        address expectedAddress = factory.getAddress(
            salt,
            tokenReceiver,
            tokenReceiver,
            currencyReceiver,
            amount,
            price,
            expiration,
            currency,
            token
        );

        uint256 tokenDecimals = token.decimals();

        vm.startPrank(paymentTokenProvider);
        currency.mint(tokenReceiver, (amount * price) / 10 ** tokenDecimals);
        vm.stopPrank();

        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, amount);

        vm.prank(tokenReceiver);
        currency.approve(
            expectedAddress,
            (amount * price) / 10 ** tokenDecimals
        );

        // make sure balances are as expected before deployment

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            )
        );

        uint currencyAmount = (amount * price) / 10 ** tokenDecimals;
        assertEq(currency.balanceOf(tokenReceiver), currencyAmount);
        assertEq(currency.balanceOf(currencyReceiver), 0);
        assertEq(token.balanceOf(tokenReceiver), 0);

        console.log(
            "feeCollector currency balance before deployment: %s",
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            )
        );
        // make sure balances are as expected after deployment
        uint256 feeCollectorCurrencyBalanceBefore = currency.balanceOf(
            FeeSettings(address(token.feeSettings())).feeCollector()
        );

        address inviteAddress = factory.deploy(
            salt,
            tokenReceiver,
            tokenReceiver,
            currencyReceiver,
            amount,
            price,
            expiration,
            currency,
            token
        );

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            )
        );

        assertEq(
            inviteAddress,
            expectedAddress,
            "deployed contract address is not correct"
        );

        console.log("buyer balance: %s", currency.balanceOf(tokenReceiver));
        console.log(
            "receiver balance: %s",
            currency.balanceOf(currencyReceiver)
        );
        console.log("buyer token balance: %s", token.balanceOf(tokenReceiver));
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertEq(currency.balanceOf(tokenReceiver), 0);

        assertEq(
            currency.balanceOf(currencyReceiver),
            currencyAmount -
                FeeSettings(address(token.feeSettings())).personalInviteFee(
                    currencyAmount
                )
        );

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            )
        );

        assertEq(
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            ),
            feeCollectorCurrencyBalanceBefore +
                FeeSettings(address(token.feeSettings())).personalInviteFee(
                    currencyAmount
                ),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(tokenReceiver), amount);

        assertEq(
            token.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            ),
            FeeSettings(address(token.feeSettings())).tokenFee(amount)
        );
    }

    function ensureCostIsRoundedUp(
        uint256 _tokenBuyAmount,
        uint256 _nominalPrice
    ) public {
        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            )
        );

        //uint rawSalt = 0;
        bytes32 salt = bytes32(uint256(8));

        //bytes memory creationCode = type(PersonalInvite).creationCode;
        uint256 expiration = block.timestamp + 1000;

        address expectedAddress = factory.getAddress(
            salt,
            currencyPayer,
            tokenReceiver,
            currencyReceiver,
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token
        );

        // set fees to 0, otherwise extra tokens are minted which causes an overflow
        Fees memory fees = Fees(UINT256_MAX, UINT256_MAX, UINT256_MAX, 0);
        FeeSettings(address(token.feeSettings())).planFeeChange(fees);
        FeeSettings(address(token.feeSettings())).executeFeeChange();

        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, _tokenBuyAmount);

        uint minCurrencyAmount = (_tokenBuyAmount * _nominalPrice) /
            10 ** token.decimals();
        console.log("minCurrencyAmount: %s", minCurrencyAmount);
        uint maxCurrencyAmount = minCurrencyAmount + 1;
        console.log("maxCurrencyAmount: %s", maxCurrencyAmount);

        vm.prank(paymentTokenProvider);
        currency.mint(currencyPayer, maxCurrencyAmount);
        vm.stopPrank();

        vm.prank(currencyPayer);
        currency.approve(expectedAddress, maxCurrencyAmount);

        // make sure balances are as expected before deployment

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            )
        );

        assertEq(
            currency.balanceOf(currencyPayer),
            maxCurrencyAmount,
            "CurrencyPayer has wrong balance"
        );
        assertEq(
            currency.balanceOf(currencyReceiver),
            0,
            "CurrencyReceiver has wrong balance"
        );
        assertEq(
            token.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            ),
            0,
            "feeCollector token balance is not correct"
        );
        assertEq(token.balanceOf(tokenReceiver), 0);

        console.log(
            "feeCollector currency balance before deployment: %s",
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            )
        );
        // make sure balances are as expected after deployment
        uint256 currencyReceiverBalanceBefore = currency.balanceOf(
            currencyReceiver
        );

        address inviteAddress = factory.deploy(
            salt,
            currencyPayer,
            tokenReceiver,
            currencyReceiver,
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token
        );

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            )
        );

        assertEq(
            inviteAddress,
            expectedAddress,
            "deployed contract address is not correct"
        );

        console.log(
            "currencyPayer balance: %s",
            currency.balanceOf(currencyPayer)
        );
        console.log(
            "currencyReceiver balance: %s",
            currency.balanceOf(currencyReceiver)
        );
        console.log(
            "tokenReceiver token balance: %s",
            token.balanceOf(tokenReceiver)
        );
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertTrue(
            currency.balanceOf(currencyPayer) <= 1,
            "currencyPayer has too much currency left"
        );

        assertTrue(
            currency.balanceOf(currencyReceiver) >
                currencyReceiverBalanceBefore,
            "currencyReceiver received no payment"
        );

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            )
        );

        assertTrue(
            maxCurrencyAmount - currency.balanceOf(currencyPayer) >= 1,
            "currencyPayer paid nothing"
        );
        uint totalCurrencyReceived = currency.balanceOf(currencyReceiver) +
            currency.balanceOf(
                FeeSettings(address(token.feeSettings())).feeCollector()
            );
        console.log("totalCurrencyReceived: %s", totalCurrencyReceived);
        assertTrue(
            totalCurrencyReceived >= minCurrencyAmount,
            "Receiver and feeCollector received less than expected"
        );

        assertTrue(
            totalCurrencyReceived <= maxCurrencyAmount,
            "Receiver and feeCollector received more than expected"
        );

        assertEq(
            token.balanceOf(tokenReceiver),
            _tokenBuyAmount,
            "tokenReceiver received no tokens"
        );
    }

    function testRoundUp0() public {
        // buy one token bit with price 1 currency bit per full token
        // -> would have to pay 10^-18 currency bits, which is not possible
        // we expect to round up to 1 currency bit
        ensureCostIsRoundedUp(1, 1);
    }

    function testRoundFixedExample0() public {
        ensureCostIsRoundedUp(583 * 10 ** token.decimals(), 82742);
    }

    function testRoundFixedExample1() public {
        ensureCostIsRoundedUp(583 * 10 ** token.decimals(), 82742);
    }

    function testRoundUpAnything(
        uint256 _tokenBuyAmount,
        uint256 _tokenPrice
    ) public {
        vm.assume(_tokenBuyAmount > 0);
        vm.assume(_tokenPrice > 0);
        vm.assume(UINT256_MAX / _tokenPrice > _tokenBuyAmount);
        // vm.assume(UINT256_MAX / _tokenPrice > 10 ** token.decimals());
        // vm.assume(
        //     UINT256_MAX / _tokenBuyAmount > _tokenPrice * 10 ** token.decimals()
        // ); // amount * price *10**18 < UINT256_MAX
        //vm.assume(_tokenPrice < UINT256_MAX / (100 * 10 ** token.decimals()));
        ensureCostIsRoundedUp(_tokenBuyAmount, _tokenPrice);
    }

    function ensureReverts(
        uint256 _tokenBuyAmount,
        uint256 _nominalPrice
    ) public {
        //uint rawSalt = 0;
        bytes32 salt = bytes32(uint256(8));

        //bytes memory creationCode = type(PersonalInvite).creationCode;
        uint256 expiration = block.timestamp + 1000;

        address expectedAddress = factory.getAddress(
            salt,
            currencyPayer,
            tokenReceiver,
            currencyReceiver,
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token
        );

        vm.startPrank(admin);
        console.log(
            "expectedAddress: %s",
            token.mintingAllowance(expectedAddress)
        );
        token.increaseMintingAllowance(expectedAddress, _tokenBuyAmount);
        vm.stopPrank();

        uint maxCurrencyAmount = UINT256_MAX;

        vm.prank(paymentTokenProvider);
        currency.mint(tokenReceiver, maxCurrencyAmount);

        vm.prank(tokenReceiver);
        currency.approve(expectedAddress, maxCurrencyAmount);

        // make sure balances are as expected before deployment
        vm.expectRevert("Create2: Failed on deploy");
        factory.deploy(
            salt,
            currencyPayer,
            tokenReceiver,
            currencyReceiver,
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token
        );
    }

    function testRevertOnOverflow(
        uint256 _tokenBuyAmount,
        uint256 _tokenPrice
    ) public {
        vm.assume(_tokenBuyAmount > 0);
        vm.assume(_tokenPrice > 0);

        vm.assume(UINT256_MAX / _tokenPrice < _tokenBuyAmount);
        //vm.assume(UINT256_MAX / _tokenBuyAmount > _tokenPrice);
        ensureReverts(_tokenBuyAmount, _tokenPrice);
    }

    function testAcceptWithDifferentTokenReceiver(uint256 rawSalt) public {
        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        //uint rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        //bytes memory creationCode = type(PersonalInvite).creationCode;
        uint256 tokenAmount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;
        uint256 tokenDecimals = token.decimals();
        uint256 currencyAmount = (tokenAmount * price) / 10 ** tokenDecimals;

        address expectedAddress = factory.getAddress(
            salt,
            currencyPayer,
            tokenReceiver,
            currencyReceiver,
            tokenAmount,
            price,
            expiration,
            currency,
            token
        );

        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, tokenAmount);

        vm.prank(paymentTokenProvider);
        currency.mint(currencyPayer, currencyAmount);

        vm.prank(currencyPayer);
        currency.approve(expectedAddress, currencyAmount);

        // make sure balances are as expected before deployment

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        assertEq(currency.balanceOf(currencyPayer), currencyAmount);
        assertEq(currency.balanceOf(currencyReceiver), 0);
        assertEq(currency.balanceOf(tokenReceiver), 0);
        assertEq(token.balanceOf(tokenReceiver), 0);

        console.log(
            "feeCollector currency balance before deployment: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        address inviteAddress = factory.deploy(
            salt,
            currencyPayer,
            tokenReceiver,
            currencyReceiver,
            tokenAmount,
            price,
            expiration,
            currency,
            token
        );

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        assertEq(
            inviteAddress,
            expectedAddress,
            "deployed contract address is not correct"
        );

        console.log("payer balance: %s", currency.balanceOf(currencyPayer));
        console.log(
            "receiver balance: %s",
            currency.balanceOf(currencyReceiver)
        );
        console.log(
            "tokenReceiver token balance: %s",
            token.balanceOf(tokenReceiver)
        );
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertEq(currency.balanceOf(currencyPayer), 0);

        assertEq(
            currency.balanceOf(currencyReceiver),
            currencyAmount -
                token.feeSettings().personalInviteFee(currencyAmount)
        );

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        assertEq(
            currency.balanceOf(token.feeSettings().feeCollector()),
            token.feeSettings().personalInviteFee(currencyAmount),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(tokenReceiver), tokenAmount);

        assertEq(
            token.balanceOf(token.feeSettings().feeCollector()),
            token.feeSettings().tokenFee(tokenAmount)
        );
    }
}
