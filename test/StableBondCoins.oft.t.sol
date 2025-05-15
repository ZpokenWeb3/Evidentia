// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../src/StableBondCoinsOFT.sol";

// LayerZero test utils
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {StableOFTAdapter} from "../src/StableOFTAdapter.sol";
import {Test, console} from "forge-std/Test.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract StableOFTAdapterTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    // Stable coins
    StableBondCoins public srcStableBondCoins;
    StableBondCoinsOFT public dstOFTStableCoins;

    // OFT Adapters
    StableOFTAdapter public srcOFTAdapter;

    // Roles and addresses
    address public defaultAdmin;
    address public minter;
    address public user1;
    address public user2;

    // Chain IDs for testing
    uint32 public constant SRC_CHAIN_ID = 1;
    uint32 public constant DST_CHAIN_ID = 2;

    // Contract roles
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function setUp() public override {
        super.setUp();

        // Create test addresses
        defaultAdmin = address(this); // Use the test contract as the admin instead of a separate address
        minter = makeAddr("minter");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Fund users with ETH for gas
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(defaultAdmin, 10 ether);

        // Setup LayerZero endpoints for two chains
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // Deploy and initialize tokens on both chains

        // Source chain token
        srcStableBondCoins = StableBondCoins(
            Upgrades.deployUUPSProxy(
                "StableBondCoins.sol",
                abi.encodeCall(srcStableBondCoins.initialize, (defaultAdmin, minter, "Stable Bond Coins", "SBC", 6))
            )
        );

        // Source chain OFT adapter
        Options memory sourceOpts;
        sourceOpts.constructorData = abi.encode(address(srcStableBondCoins), address(endpoints[SRC_CHAIN_ID]));
        sourceOpts.unsafeAllow = "constructor,missing-initializer-call,state-variable-immutable";

    address srcProxyAddr = Upgrades.deployTransparentProxy(
            "StableOFTAdapter.sol", defaultAdmin, abi.encodeCall(StableOFTAdapter.initialize, (defaultAdmin)), sourceOpts
        );
        srcOFTAdapter = StableOFTAdapter(srcProxyAddr);

        // Destination chain OFT native token
        Options memory dstOpts;
        dstOpts.constructorData = abi.encode(address(endpoints[DST_CHAIN_ID]));
        dstOpts.unsafeAllow = "constructor,missing-initializer-call,state-variable-immutable";

    bytes memory dstInitData =
            abi.encodeCall(StableBondCoinsOFT.initialize, (defaultAdmin, minter, "Stable Bond Coins", "SBC"));
        address dstProxyAddr = Upgrades.deployTransparentProxy("StableBondCoinsOFT.sol", defaultAdmin, dstInitData, dstOpts);
        dstOFTStableCoins = StableBondCoinsOFT(dstProxyAddr);

        // Setup OFT connection (setPeer) - No need for startPrank as defaultAdmin is now this contract
        srcOFTAdapter.setPeer(DST_CHAIN_ID, bytes32(uint256(uint160(address(dstOFTStableCoins)))));
        dstOFTStableCoins.setPeer(SRC_CHAIN_ID, bytes32(uint256(uint160(address(srcOFTAdapter)))));

        // Initial token minting
        vm.startPrank(minter);
        srcStableBondCoins.mint(user1, 1000 * 10 ** 6); // 1000 tokens
        dstOFTStableCoins.mint(user2, 1000 * 10 ** 6);
        vm.stopPrank();
    }

    function testSendTokensCrossChain() public {
        uint256 amount = 100 * 10 ** 6; // 100 tokens

        // Initial balances
        uint256 user1SrcInitialBalance = srcStableBondCoins.balanceOf(user1);
        uint256 user1DstInitialBalance = dstOFTStableCoins.balanceOf(user1);

        // Create proper options for ULN
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0) // gas for execution on target chain
            .addExecutorLzComposeOption(0, 200000, 0); // compose option

        // Create SendParam for OFT V2
        SendParam memory sendParam = SendParam({
            dstEid: DST_CHAIN_ID,
            to: bytes32(uint256(uint160(user1))),
            amountLD: amount,
            minAmountLD: amount * 95 / 100, // 5% allowed slippage
            extraOptions: options,
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        vm.startPrank(user1);

        srcStableBondCoins.approve(address(srcOFTAdapter), amount);
        // Get fee using quoteSend
        MessagingFee memory fee = srcOFTAdapter.quoteSend(sendParam, false);

        // Send tokens
        srcOFTAdapter.send{value: fee.nativeFee}(
            sendParam,
            fee,
            user1 // refund address
        );

        vm.stopPrank();

        // Tokens should not be received until packet verification
        assertEq(
            srcStableBondCoins.balanceOf(user1), user1SrcInitialBalance - amount, "Source chain balance not decreased"
        );
        assertEq(
            dstOFTStableCoins.balanceOf(user1),
            user1DstInitialBalance,
            "Destination chain balance should not change before verification"
        );

        // Verify packets to simulate cross-chain transfer
        verifyPackets(DST_CHAIN_ID, addressToBytes32(address(dstOFTStableCoins)));

        // Check balances after transfer
        assertEq(
            dstOFTStableCoins.balanceOf(user1),
            user1DstInitialBalance + amount,
            "Destination chain balance not increased"
        );
    }

    function testSendBatchCrossChain() public {
        // Setup multiple recipients
        address[] memory recipients = new address[](2);
        recipients[0] = makeAddr("recipient1");
        recipients[1] = makeAddr("recipient2");

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 30 * 10 ** 6;
        amounts[1] = 40 * 10 ** 6;

        vm.startPrank(user1);

        // Send to each recipient separately
        for (uint256 i = 0; i < recipients.length; i++) {
            // Create proper options for ULN
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
                .addExecutorLzComposeOption(0, 200000, 0);

            SendParam memory sendParam = SendParam({
                dstEid: DST_CHAIN_ID,
                to: bytes32(uint256(uint160(recipients[i]))),
                amountLD: amounts[i],
                minAmountLD: amounts[i] * 95 / 100, // 5% allowed slippage
                extraOptions: options,
                composeMsg: bytes(""),
                oftCmd: bytes("")
            });

            srcStableBondCoins.approve(address(srcOFTAdapter), amounts[0] + amounts[1]);
            // Get fee for this transfer
            MessagingFee memory fee = srcOFTAdapter.quoteSend(sendParam, false);

            // Send tokens
            srcOFTAdapter.send{value: fee.nativeFee}(
                sendParam,
                fee,
                user1 // refund address
            );
        }

        vm.stopPrank();

        // Verify packets to simulate cross-chain transfer
        verifyPackets(DST_CHAIN_ID, addressToBytes32(address(dstOFTStableCoins)));

        // Check recipient balances
        assertEq(dstOFTStableCoins.balanceOf(recipients[0]), amounts[0], "Invalid first recipient balance");
        assertEq(dstOFTStableCoins.balanceOf(recipients[1]), amounts[1], "Invalid second recipient balance");
    }

    function testSetDelegateAndOwnership() public {
        address newDelegate = makeAddr("newDelegate");

        // Change owner - no need for startPrank as defaultAdmin is now this contract
        srcOFTAdapter.transferOwnership(newDelegate);

        assertEq(srcOFTAdapter.owner(), newDelegate, "Owner not changed");

        // Test configuration change with new owner
        vm.startPrank(newDelegate);

        // Setup delegate in the endpoint
        srcOFTAdapter.setDelegate(address(1234));

        vm.stopPrank();
    }
}
