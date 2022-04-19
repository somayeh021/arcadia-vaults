// SPDX-License-Identifier: UNLICENSED
pragma solidity >0.8.10;

import "../../lib/ds-test/src/test.sol";
import "../../lib/forge-std/src/stdlib.sol";
import "../../lib/forge-std/src/console.sol";
import "../../lib/forge-std/src/Vm.sol";

import "../tests/ERC20NoApprove.sol";
import "../tests/SimplifiedChainlinkOracle.sol";
import "../OracleHub.sol";
import "../utils/Constants.sol";
import "../AssetRegistry/AbstractSubRegistry.sol";
import "../AssetRegistry/MainRegistry.sol";

contract AbstractSubRegistryForTest is SubRegistry {
	constructor (address mainRegistry, address oracleHub) SubRegistry(mainRegistry, oracleHub) {}

  function setAssetInformation(address assetAddress) public onlyOwner {

    if (!inSubRegistry[assetAddress]) {
      inSubRegistry[assetAddress] = true;
      assetsInSubRegistry.push(assetAddress);
    }
    isAssetAddressWhiteListed[assetAddress] = true;
  }

}
contract AbstractSubRegistryTest is DSTest {
  using stdStorage for StdStorage;

  Vm private vm = Vm(HEVM_ADDRESS);
  StdStorage private stdstore;

	AbstractSubRegistryForTest internal abstractSubRegistry;
	OracleHub private oracleHub;
	MainRegistry private mainRegistry;

  ERC20NoApprove private eth;
  ERC20NoApprove private snx;
  ERC20NoApprove private link;

  address private creatorAddress = address(1);
  address private tokenCreatorAddress = address(2);

//this is a before
  constructor () {

    vm.startPrank(tokenCreatorAddress);
    eth = new ERC20NoApprove(uint8(Constants.ethDecimals));
    snx = new ERC20NoApprove(uint8(Constants.snxDecimals));
    link = new ERC20NoApprove(uint8(Constants.linkDecimals));
    vm.stopPrank();

		vm.startPrank(creatorAddress);
		mainRegistry = new MainRegistry(MainRegistry.NumeraireInformation({numeraireToUsdOracleUnit:0, assetAddress:0x0000000000000000000000000000000000000000, numeraireToUsdOracle:0x0000000000000000000000000000000000000000, numeraireLabel:'USD', numeraireUnit:1}));
		oracleHub = new OracleHub();
		vm.stopPrank();
  }

  //this is a before each
  function setUp() public {
    vm.prank(creatorAddress);
    abstractSubRegistry = new AbstractSubRegistryForTest(address(mainRegistry), address(oracleHub));		
  }

	function testAssetWhitelistedWhenAddedToSubregistry (address assetAddress) public {
		vm.prank(creatorAddress);
		abstractSubRegistry.setAssetInformation(assetAddress);

		assertTrue(abstractSubRegistry.isAssetAddressWhiteListed(assetAddress));
	}

	function testNonOwnerAddsExistingAssetToWhitelist (address unprivilegedAddress) public {
		vm.prank(creatorAddress);
		abstractSubRegistry.setAssetInformation(address(eth));

		vm.startPrank(unprivilegedAddress);
		vm.expectRevert("Ownable: caller is not the owner");
		abstractSubRegistry.addToWhiteList(address(eth));
		vm.stopPrank();

		assertTrue(abstractSubRegistry.isAssetAddressWhiteListed(address(eth)));
	}

	function testOwnerAddsNonExistingAssetToWhitelist () public {
		vm.startPrank(creatorAddress);
		vm.expectRevert("Asset not known in Sub-Registry");
		abstractSubRegistry.addToWhiteList(address(eth));
		vm.stopPrank();

		assertTrue(!abstractSubRegistry.isAssetAddressWhiteListed(address(eth)));
	}

	function testOwnerAddsExistingAssetToWhitelist () public {
		vm.startPrank(creatorAddress);
		abstractSubRegistry.setAssetInformation(address(eth));
		abstractSubRegistry.addToWhiteList(address(eth));
		vm.stopPrank();

		assertTrue(abstractSubRegistry.isAssetAddressWhiteListed(address(eth)));
	}

	function testNonOwnerRemovesExistingAssetFromWhitelist (address unprivilegedAddress) public {
		vm.prank(creatorAddress);
		abstractSubRegistry.setAssetInformation(address(eth));

		vm.assume(unprivilegedAddress != address(this));
		vm.assume(unprivilegedAddress != creatorAddress);

		vm.startPrank(unprivilegedAddress);
		vm.expectRevert("Ownable: caller is not the owner");
		abstractSubRegistry.removeFromWhiteList(address(eth));
		vm.stopPrank();

		assertTrue(abstractSubRegistry.isAssetAddressWhiteListed(address(eth)));
	}

	function testOwnerRemovesNonExistingAssetFromWhitelist () public {
		vm.startPrank(creatorAddress);
		vm.expectRevert("Asset not known in Sub-Registry");
		abstractSubRegistry.removeFromWhiteList(address(eth));
		vm.stopPrank();

		assertTrue(!abstractSubRegistry.isAssetAddressWhiteListed(address(eth)));
	}

	function testOwnerRemovesExistingAssetFromWhitelist () public {
		vm.startPrank(creatorAddress);
		abstractSubRegistry.setAssetInformation(address(eth));
		abstractSubRegistry.removeFromWhiteList(address(eth));
		vm.stopPrank();

		assertTrue(!abstractSubRegistry.isAssetAddressWhiteListed(address(eth)));
	}

	function testNonOwnerAddsRemovedAssetToWhitelist (address unprivilegedAddress) public {
		vm.startPrank(creatorAddress);
		abstractSubRegistry.setAssetInformation(address(eth));
		abstractSubRegistry.removeFromWhiteList(address(eth));
		vm.stopPrank();

		vm.startPrank(unprivilegedAddress);
		vm.expectRevert("Ownable: caller is not the owner");
		abstractSubRegistry.addToWhiteList(address(eth));
		vm.stopPrank();

		assertTrue(!abstractSubRegistry.isAssetAddressWhiteListed(address(eth)));
	}

	function testOwnerAddsRemovedAssetToWhitelist () public {
		vm.startPrank(creatorAddress);
		abstractSubRegistry.setAssetInformation(address(eth));
		abstractSubRegistry.removeFromWhiteList(address(eth));

		abstractSubRegistry.addToWhiteList(address(eth));
		vm.stopPrank();

		assertTrue(abstractSubRegistry.isAssetAddressWhiteListed(address(eth)));
	}

}