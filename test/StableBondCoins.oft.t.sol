// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {StableBondCoins} from "../src/StableBondCoins.sol";
import {Test, console} from "forge-std/Test.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

// LayerZero test utils
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

contract StableBondCoinsOFTTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    // Main contracts
    StableBondCoins public srcStableBondCoins;
    StableBondCoins public dstStableBondCoins;

    // Roles and addresses
    address public defaultAdmin;
    address public minter;
    address public delegate;
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
        defaultAdmin = makeAddr("defaultAdmin");
        minter = makeAddr("minter");
        delegate = makeAddr("delegate");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Fund users with ETH for gas
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);

        // Setup LayerZero endpoints for two chains
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // Deploy and initialize tokens on both chains

        // Source chain token
        StableBondCoins srcImpl = new StableBondCoins(address(endpoints[SRC_CHAIN_ID]));
        bytes memory srcInitData = abi.encodeCall(StableBondCoins.initialize, (defaultAdmin, minter, defaultAdmin));
        address srcProxyAddr = UnsafeUpgrades.deployUUPSProxy(address(srcImpl), srcInitData);
        srcStableBondCoins = StableBondCoins(srcProxyAddr);

        // Destination chain token
        StableBondCoins dstImpl = new StableBondCoins(address(endpoints[DST_CHAIN_ID]));
        bytes memory dstInitData = abi.encodeCall(StableBondCoins.initialize, (defaultAdmin, minter, defaultAdmin));
        address dstProxyAddr = UnsafeUpgrades.deployUUPSProxy(address(dstImpl), dstInitData);
        dstStableBondCoins = StableBondCoins(dstProxyAddr);

        vm.startPrank(defaultAdmin);
        // Setup OFT connection (setPeer)
        srcStableBondCoins.setPeer(DST_CHAIN_ID, bytes32(uint256(uint160(address(dstStableBondCoins)))));
        dstStableBondCoins.setPeer(SRC_CHAIN_ID, bytes32(uint256(uint160(address(srcStableBondCoins)))));
        vm.stopPrank();

        // Initial token minting
        vm.startPrank(minter);
        srcStableBondCoins.mint(user1, 1000 * 10 ** 6); // 1000 tokens
        dstStableBondCoins.mint(user2, 1000 * 10 ** 6);
        vm.stopPrank();
    }

    function testSendTokensCrossChain() public {
        uint256 amount = 100 * 10 ** 6; // 100 tokens

        // Initial balances
        uint256 user1SrcInitialBalance = srcStableBondCoins.balanceOf(user1);
        uint256 user1DstInitialBalance = dstStableBondCoins.balanceOf(user1);

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

        // Get fee using quoteSend
        MessagingFee memory fee = srcStableBondCoins.quoteSend(sendParam, false);

        // Send tokens
        srcStableBondCoins.send{value: fee.nativeFee}(
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
            dstStableBondCoins.balanceOf(user1),
            user1DstInitialBalance,
            "Destination chain balance should not change before verification"
        );

        // Verify packets to simulate cross-chain transfer
        verifyPackets(DST_CHAIN_ID, addressToBytes32(address(dstStableBondCoins)));

        // Check balances after transfer
        assertEq(
            dstStableBondCoins.balanceOf(user1),
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

            // Get fee for this transfer
            MessagingFee memory fee = srcStableBondCoins.quoteSend(sendParam, false);

            // Send tokens
            srcStableBondCoins.send{value: fee.nativeFee}(
                sendParam,
                fee,
                user1 // refund address
            );
        }

        vm.stopPrank();

        // Verify packets to simulate cross-chain transfer
        verifyPackets(DST_CHAIN_ID, addressToBytes32(address(dstStableBondCoins)));

        // Check recipient balances
        assertEq(dstStableBondCoins.balanceOf(recipients[0]), amounts[0], "Invalid first recipient balance");
        assertEq(dstStableBondCoins.balanceOf(recipients[1]), amounts[1], "Invalid second recipient balance");
    }

    function testSetDelegateAndOwnership() public {
        address newDelegate = makeAddr("newDelegate");

        // Change owner via admin
        vm.startPrank(defaultAdmin);
        srcStableBondCoins.transferOwnership(newDelegate);
        vm.stopPrank();

        assertEq(srcStableBondCoins.owner(), newDelegate, "Owner not changed");

        // Test configuration change with new owner
        vm.startPrank(newDelegate);

        // Configure new enforced option as example
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300000, 0);

        // Setup delegate in the endpoint
        srcStableBondCoins.setDelegate(address(1234));

        vm.stopPrank();
    }
}
