// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Ethereal} from "../src/ethereal.sol";
import "forge-std/console.sol";

contract EtherealTest is Test {
    Ethereal public ethereal;
    string public constant BASE_URL = "https://ethereal.app";
    address user1;
    address user2;
    uint256 mintedTokenId;

    function setUp() public {
        ethereal = new Ethereal();
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
    }

    function _createCollection(
        string memory _name,
        bool _validator,
        address _validatorAddress,
        bool _ethereum,
        string memory _baseURI
    ) internal {
        ethereal.createCollection("1st Collection", false, address(0), true, BASE_URL);
    }

    function _createGem(uint256 collection, uint256 denomination, uint256 redeemFee, bool active)
        internal
        returns (uint256 _id)
    {
        _id = ethereal.createGem(collection, denomination, redeemFee, active);
    }

    function test_CreateCollection() public {
        _createCollection("1st Collection", false, address(0), true, BASE_URL);
        (string memory name, bool validator, address validatorAddress, bool ethereum, string memory baseURI) =
            ethereal.collections(0);

        assertEq(name, "1st Collection");
        assertFalse(validator);
        assertEq(validatorAddress, address(0));
        assertTrue(ethereum);
        assertEq(ethereal.getCollectionsLength(), 1);
    }

    function test_UpdateCollectionByOwner() public {
        _createCollection("1st Collection", false, address(0), true, BASE_URL);
        ethereal.updateCollection(0, "1st Collection - updated", true, address(0), true, BASE_URL);

        (string memory name, bool validator,,,) = ethereal.collections(0);
        assertEq(name, "1st Collection - updated");
        assertTrue(validator);
        assertEq(ethereal.getCollectionsLength(), 1);
    }

    function test_CreateGemByOwner() public {
        _createCollection("1st Collection", false, address(0), true, BASE_URL);
        _createGem(0, 1e17, 10, true);

        (uint256 collection, uint256 denomination, uint256 redeemFee, bool active) = ethereal.gems(0);
        assertEq(collection, 0);
        assertEq(denomination, 1e17);
        assertEq(redeemFee, 10);
        assertTrue(active);
        assertEq(ethereal.getGemsLength(), 1);
    }

    // Mint tests

    function setUpMint() public {
        ethereal = new Ethereal();

        _createCollection("1st Collection", false, address(0), true, BASE_URL);
        _createGem(0, 100 * 1e18, 10, true);
    }

    function test_MintForUser() public {
        setUpMint();
        vm.deal(user1, 100 * 1e18); // Ensuring user1 has enough ETH

        vm.prank(user1);
        uint256 tokenId = ethereal.mint{value: 100 * 1e18}(0, user1);
        (uint256 balance, uint256 collection, uint256 gem) = ethereal.metadata(tokenId);
        assertEq(balance, 100 * 1e18);
        assertEq(collection, 0);
        assertEq(gem, 0);
    }

    function test_MintDifferentCollectionForSameUser() public {
        setUpMint();
        _createCollection("2nd Collection", false, address(0), true, BASE_URL);
        _createCollection("3rd Collection", false, address(0), true, BASE_URL);
        _createGem(2, 5 * 1e18, 1e17, true);

        vm.deal(user1, 5 * 1e18);
        vm.prank(user1);
        uint256 tokenId = ethereal.mint{value: 5 * 1e18}(1, user1);

        (uint256 balance, uint256 collection, uint256 gem) = ethereal.metadata(tokenId);
        assertEq(balance, 5 * 1e18);
        assertEq(collection, 2);
        assertEq(gem, 1);
    }

    function testFail_MintForWrongEtherAmount() public {
        setUpMint();
        vm.deal(user1, 10 * 1e18);
        vm.prank(user1);
        ethereal.mint{value: 10 * 1e18}(0, user1);
    }

    function testFail_MintNotActiveGem() public {
        setUpMint();
        ethereal.ceaseGem(0);
        vm.deal(user1, 100 * 1e18);
        vm.prank(user1);
        ethereal.mint{value: 100 * 1e18}(0, user1);
    }

    // Redeem tests

    function setUpRedeem() public {
        ethereal = new Ethereal();
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        _createCollection("1st Collection", false, address(0), true, BASE_URL);
        _createGem(0, 100 * 1e18, 10, true);

        vm.deal(user1, 100 * 1e18); // Ensuring user1 has enough ETH
        vm.prank(user1);
        mintedTokenId = ethereal.mint{value: 100 * 1e18}(0, user1); // Mint a token and store its ID
    }

    function test_UserRedeem() public {
        setUpRedeem();
        assertEq(ethereal.fees(), 0);

        vm.prank(user1);
        ethereal.redeem(mintedTokenId);
        assertEq(ethereal.fees(), 1 ether * 0.1);
    }

    function test_IncreaseUserBalanceOnRedeem() public {
        setUpRedeem();

        uint256 userBalanceBeforeRedeem = user1.balance;
        vm.prank(user1);
        ethereal.redeem(mintedTokenId);

        assertTrue(user1.balance > userBalanceBeforeRedeem, "User balance should increase after redeeming");
    }

    function test_NewOwnerOfNFTCanRedeem() public {
        setUpRedeem();

        vm.prank(user1);
        ethereal.safeTransferFrom(user1, user2, mintedTokenId);
        assertEq(ethereal.fees(), 0);
        vm.prank(user2);
        ethereal.redeem(mintedTokenId);
        assertEq(ethereal.fees(), 1 ether * 0.1);
    }

    function test_RedemptionOfCeasedGem() public {
        setUpRedeem();

        ethereal.ceaseGem(0);
        (,,, bool active) = ethereal.gems(0);
        assertFalse(active, "Gem should be inactive after cease");

        assertEq(ethereal.fees(), 0);

        vm.prank(user1);
        ethereal.redeem(mintedTokenId); // This should still work after gem is ceased.
        assertEq(ethereal.fees(), 1 ether * 0.1);
    }
}
