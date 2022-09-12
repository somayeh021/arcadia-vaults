/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity >0.8.10;

import "../../../lib/forge-std/src/Test.sol";

import "../../Factory.sol";
import "../../Proxy.sol";
import "../../Vault.sol";
import "../../mockups/ERC20SolmateMock.sol";
import "../../mockups/ERC721SolmateMock.sol";
import "../../mockups/ERC1155SolmateMock.sol";
import "../../AssetRegistry/MainRegistry.sol";
import "../../AssetRegistry/FloorERC721SubRegistry.sol";
import "../../AssetRegistry/StandardERC20SubRegistry.sol";
import "../../AssetRegistry/FloorERC1155SubRegistry.sol";
import "../../Liquidator.sol";
import "../../OracleHub.sol";

import "../../utils/Constants.sol";
import "../../ArcadiaOracle.sol";
import "../fixtures/ArcadiaOracleFixture.f.sol";

import {LiquidityPool} from "../../../lib/arcadia-lending/src/LiquidityPool.sol";
import {DebtToken} from "../../../lib/arcadia-lending/src/DebtToken.sol";
import {Tranche} from "../../../lib/arcadia-lending/src/Tranche.sol";
import {Asset} from "../../../lib/arcadia-lending/src/mocks/Asset.sol";


contract gasBuyVault_2ERC202ERC721 is Test {
    using stdStorage for StdStorage;

    Factory private factory;
    Vault private vault;
    Vault private proxy;
    address private proxyAddr;
    ERC20Mock private eth;
    ERC20Mock private snx;
    ERC20Mock private link;
    ERC20Mock private safemoon;
    ERC721Mock private bayc;
    ERC721Mock private mayc;
    ERC721Mock private dickButs;
    ERC20Mock private wbayc;
    ERC20Mock private wmayc;
    ERC1155Mock private interleave;
    ERC1155Mock private genericStoreFront;
    OracleHub private oracleHub;
    ArcadiaOracle private oracleEthToUsd;
    ArcadiaOracle private oracleLinkToUsd;
    ArcadiaOracle private oracleSnxToEth;
    ArcadiaOracle private oracleWbaycToEth;
    ArcadiaOracle private oracleWmaycToUsd;
    ArcadiaOracle private oracleInterleaveToEth;
    ArcadiaOracle private oracleGenericStoreFrontToEth;
    MainRegistry private mainRegistry;
    StandardERC20Registry private standardERC20Registry;
    FloorERC721SubRegistry private floorERC721SubRegistry;
    FloorERC1155SubRegistry private floorERC1155SubRegistry;
    Liquidator private liquidator;

    Asset asset;
    LiquidityPool pool;
    Tranche tranche;
    DebtToken debt;

    address private creatorAddress = address(1);
    address private tokenCreatorAddress = address(2);
    address private oracleOwner = address(3);
    address private unprivilegedAddress = address(4);
    address private vaultOwner = address(6);
    address private liquidatorBot = address(7);
    address private vaultBuyer = address(8);
    address private liquidityProvider = address(9);

    uint256 rateEthToUsd = 3000 * 10**Constants.oracleEthToUsdDecimals;
    uint256 rateLinkToUsd = 20 * 10**Constants.oracleLinkToUsdDecimals;
    uint256 rateSnxToEth = 1600000000000000;
    uint256 rateWbaycToEth = 85 * 10**Constants.oracleWbaycToEthDecimals;
    uint256 rateWmaycToUsd = 50000 * 10**Constants.oracleWmaycToUsdDecimals;
    uint256 rateInterleaveToEth =
        1 * 10**(Constants.oracleInterleaveToEthDecimals - 2);
    uint256 rateGenericStoreFrontToEth = 1 * 10**(8);

    address[] public oracleEthToUsdArr = new address[](1);
    address[] public oracleLinkToUsdArr = new address[](1);
    address[] public oracleSnxToEthEthToUsd = new address[](2);
    address[] public oracleWbaycToEthEthToUsd = new address[](2);
    address[] public oracleWmaycToUsdArr = new address[](1);
    address[] public oracleInterleaveToEthEthToUsd = new address[](2);
    address[] public oracleGenericStoreFrontToEthEthToUsd = new address[](2);

    address[] public s_1;
    uint256[] public s_2;
    uint256[] public s_3;
    uint256[] public s_4;

    // EVENTS
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // FIXTURES
    ArcadiaOracleFixture arcadiaOracleFixture =
        new ArcadiaOracleFixture(oracleOwner);

    //this is a before
    constructor() {
        vm.startPrank(tokenCreatorAddress);

        eth = new ERC20Mock("ETH Mock", "mETH", uint8(Constants.ethDecimals));
        eth.mint(tokenCreatorAddress, 200000 * 10**Constants.ethDecimals);

        snx = new ERC20Mock("SNX Mock", "mSNX", uint8(Constants.snxDecimals));
        snx.mint(tokenCreatorAddress, 200000 * 10**Constants.snxDecimals);

        link = new ERC20Mock(
            "LINK Mock",
            "mLINK",
            uint8(Constants.linkDecimals)
        );
        link.mint(tokenCreatorAddress, 200000 * 10**Constants.linkDecimals);

        safemoon = new ERC20Mock(
            "Safemoon Mock",
            "mSFMN",
            uint8(Constants.safemoonDecimals)
        );
        safemoon.mint(
            tokenCreatorAddress,
            200000 * 10**Constants.safemoonDecimals
        );

        bayc = new ERC721Mock("BAYC Mock", "mBAYC");
        bayc.mint(tokenCreatorAddress, 0);
        bayc.mint(tokenCreatorAddress, 1);
        bayc.mint(tokenCreatorAddress, 2);
        bayc.mint(tokenCreatorAddress, 3);
        bayc.mint(tokenCreatorAddress, 4);
        bayc.mint(tokenCreatorAddress, 5);
        bayc.mint(tokenCreatorAddress, 6);
        bayc.mint(tokenCreatorAddress, 7);
        bayc.mint(tokenCreatorAddress, 8);
        bayc.mint(tokenCreatorAddress, 9);
        bayc.mint(tokenCreatorAddress, 10);
        bayc.mint(tokenCreatorAddress, 11);
        bayc.mint(tokenCreatorAddress, 12);

        mayc = new ERC721Mock("MAYC Mock", "mMAYC");
        mayc.mint(tokenCreatorAddress, 0);
        mayc.mint(tokenCreatorAddress, 1);
        mayc.mint(tokenCreatorAddress, 2);
        mayc.mint(tokenCreatorAddress, 3);
        mayc.mint(tokenCreatorAddress, 4);
        mayc.mint(tokenCreatorAddress, 5);
        mayc.mint(tokenCreatorAddress, 6);
        mayc.mint(tokenCreatorAddress, 7);
        mayc.mint(tokenCreatorAddress, 8);
        mayc.mint(tokenCreatorAddress, 9);

        dickButs = new ERC721Mock("DickButs Mock", "mDICK");
        dickButs.mint(tokenCreatorAddress, 0);
        dickButs.mint(tokenCreatorAddress, 1);
        dickButs.mint(tokenCreatorAddress, 2);

        wbayc = new ERC20Mock(
            "wBAYC Mock",
            "mwBAYC",
            uint8(Constants.wbaycDecimals)
        );
        wbayc.mint(tokenCreatorAddress, 100000 * 10**Constants.wbaycDecimals);

        interleave = new ERC1155Mock("Interleave Mock", "mInterleave");
        interleave.mint(tokenCreatorAddress, 1, 100000);
        interleave.mint(tokenCreatorAddress, 2, 100000);
        interleave.mint(tokenCreatorAddress, 3, 100000);
        interleave.mint(tokenCreatorAddress, 4, 100000);
        interleave.mint(tokenCreatorAddress, 5, 100000);

        genericStoreFront = new ERC1155Mock("Generic Storefront Mock", "mGSM");
        genericStoreFront.mint(tokenCreatorAddress, 1, 100000);
        genericStoreFront.mint(tokenCreatorAddress, 2, 100000);
        genericStoreFront.mint(tokenCreatorAddress, 3, 100000);
        genericStoreFront.mint(tokenCreatorAddress, 4, 100000);
        genericStoreFront.mint(tokenCreatorAddress, 5, 100000);

        vm.stopPrank();

        vm.prank(creatorAddress);
        oracleHub = new OracleHub();

        oracleEthToUsd = arcadiaOracleFixture.initMockedOracle(
            uint8(Constants.oracleEthToUsdDecimals),
            "ETH / USD",
            rateEthToUsd
        );
        oracleLinkToUsd = arcadiaOracleFixture.initMockedOracle(
            uint8(Constants.oracleLinkToUsdDecimals),
            "LINK / USD",
            rateLinkToUsd
        );
        oracleSnxToEth = arcadiaOracleFixture.initMockedOracle(
            uint8(Constants.oracleSnxToEthDecimals),
            "SNX / ETH",
            rateSnxToEth
        );
        oracleWbaycToEth = arcadiaOracleFixture.initMockedOracle(
            uint8(Constants.oracleWbaycToEthDecimals),
            "WBAYC / ETH",
            rateWbaycToEth
        );
        oracleWmaycToUsd = arcadiaOracleFixture.initMockedOracle(
            uint8(Constants.oracleWmaycToUsdDecimals),
            "WBAYC / USD",
            rateWmaycToUsd
        );
        oracleInterleaveToEth = arcadiaOracleFixture.initMockedOracle(
            uint8(Constants.oracleInterleaveToEthDecimals),
            "INTERLEAVE / ETH",
            rateInterleaveToEth
        );
        oracleGenericStoreFrontToEth = arcadiaOracleFixture.initMockedOracle(
            uint8(10),
            "GenericStoreFront / ETH",
            rateGenericStoreFrontToEth
        );

        vm.startPrank(creatorAddress);
        oracleHub.addOracle(
            OracleHub.OracleInformation({
                oracleUnit: uint64(Constants.oracleEthToUsdUnit),
                baseAssetBaseCurrency: 0,
                quoteAsset: "ETH",
                baseAsset: "USD",
                oracleAddress: address(oracleEthToUsd),
                quoteAssetAddress: address(eth),
                baseAssetIsBaseCurrency: true
            })
        );
        oracleHub.addOracle(
            OracleHub.OracleInformation({
                oracleUnit: uint64(Constants.oracleLinkToUsdUnit),
                baseAssetBaseCurrency: 0,
                quoteAsset: "LINK",
                baseAsset: "USD",
                oracleAddress: address(oracleLinkToUsd),
                quoteAssetAddress: address(link),
                baseAssetIsBaseCurrency: true
            })
        );
        oracleHub.addOracle(
            OracleHub.OracleInformation({
                oracleUnit: uint64(Constants.oracleSnxToEthUnit),
                baseAssetBaseCurrency: 1,
                quoteAsset: "SNX",
                baseAsset: "ETH",
                oracleAddress: address(oracleSnxToEth),
                quoteAssetAddress: address(snx),
                baseAssetIsBaseCurrency: true
            })
        );
        oracleHub.addOracle(
            OracleHub.OracleInformation({
                oracleUnit: uint64(Constants.oracleWbaycToEthUnit),
                baseAssetBaseCurrency: 1,
                quoteAsset: "WBAYC",
                baseAsset: "ETH",
                oracleAddress: address(oracleWbaycToEth),
                quoteAssetAddress: address(wbayc),
                baseAssetIsBaseCurrency: true
            })
        );
        oracleHub.addOracle(
            OracleHub.OracleInformation({
                oracleUnit: uint64(Constants.oracleWmaycToUsdUnit),
                baseAssetBaseCurrency: 0,
                quoteAsset: "WMAYC",
                baseAsset: "USD",
                oracleAddress: address(oracleWmaycToUsd),
                quoteAssetAddress: address(wmayc),
                baseAssetIsBaseCurrency: true
            })
        );
        oracleHub.addOracle(
            OracleHub.OracleInformation({
                oracleUnit: uint64(Constants.oracleInterleaveToEthUnit),
                baseAssetBaseCurrency: 1,
                quoteAsset: "INTERLEAVE",
                baseAsset: "ETH",
                oracleAddress: address(oracleInterleaveToEth),
                quoteAssetAddress: address(interleave),
                baseAssetIsBaseCurrency: true
            })
        );
        oracleHub.addOracle(
            OracleHub.OracleInformation({
                oracleUnit: uint64(10**10),
                baseAssetBaseCurrency: 1,
                quoteAsset: "GenericStoreFront",
                baseAsset: "ETH",
                oracleAddress: address(oracleGenericStoreFrontToEth),
                quoteAssetAddress: address(genericStoreFront),
                baseAssetIsBaseCurrency: true
            })
        );
        vm.stopPrank();

        vm.startPrank(tokenCreatorAddress);
        eth.transfer(vaultOwner, 100000 * 10**Constants.ethDecimals);
        link.transfer(vaultOwner, 100000 * 10**Constants.linkDecimals);
        snx.transfer(vaultOwner, 100000 * 10**Constants.snxDecimals);
        safemoon.transfer(vaultOwner, 100000 * 10**Constants.safemoonDecimals);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 0);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 1);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 2);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 3);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 4);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 5);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 6);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 7);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 8);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 9);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 10);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 11);
        bayc.transferFrom(tokenCreatorAddress, vaultOwner, 12);
        mayc.transferFrom(tokenCreatorAddress, vaultOwner, 0);
        mayc.transferFrom(tokenCreatorAddress, vaultOwner, 1);
        mayc.transferFrom(tokenCreatorAddress, vaultOwner, 2);
        mayc.transferFrom(tokenCreatorAddress, vaultOwner, 3);
        mayc.transferFrom(tokenCreatorAddress, vaultOwner, 4);
        mayc.transferFrom(tokenCreatorAddress, vaultOwner, 5);
        mayc.transferFrom(tokenCreatorAddress, vaultOwner, 6);
        mayc.transferFrom(tokenCreatorAddress, vaultOwner, 7);
        mayc.transferFrom(tokenCreatorAddress, vaultOwner, 8);
        mayc.transferFrom(tokenCreatorAddress, vaultOwner, 9);
        dickButs.transferFrom(tokenCreatorAddress, vaultOwner, 0);
        interleave.safeTransferFrom(
            tokenCreatorAddress,
            vaultOwner,
            1,
            100000,
            "0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        interleave.safeTransferFrom(
            tokenCreatorAddress,
            vaultOwner,
            2,
            100000,
            "0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        interleave.safeTransferFrom(
            tokenCreatorAddress,
            vaultOwner,
            3,
            100000,
            "0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        interleave.safeTransferFrom(
            tokenCreatorAddress,
            vaultOwner,
            4,
            100000,
            "0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        interleave.safeTransferFrom(
            tokenCreatorAddress,
            vaultOwner,
            5,
            100000,
            "0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        genericStoreFront.safeTransferFrom(
            tokenCreatorAddress,
            vaultOwner,
            1,
            100000,
            "0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        genericStoreFront.safeTransferFrom(
            tokenCreatorAddress,
            vaultOwner,
            2,
            100000,
            "0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        genericStoreFront.safeTransferFrom(
            tokenCreatorAddress,
            vaultOwner,
            3,
            100000,
            "0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        genericStoreFront.safeTransferFrom(
            tokenCreatorAddress,
            vaultOwner,
            4,
            100000,
            "0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        genericStoreFront.safeTransferFrom(
            tokenCreatorAddress,
            vaultOwner,
            5,
            100000,
            "0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        eth.transfer(unprivilegedAddress, 1000 * 10**Constants.ethDecimals);
        vm.stopPrank();


        oracleEthToUsdArr[0] = address(oracleEthToUsd);

        oracleLinkToUsdArr[0] = address(oracleLinkToUsd);

        oracleSnxToEthEthToUsd[0] = address(oracleSnxToEth);
        oracleSnxToEthEthToUsd[1] = address(oracleEthToUsd);

        oracleWbaycToEthEthToUsd[0] = address(oracleWbaycToEth);
        oracleWbaycToEthEthToUsd[1] = address(oracleEthToUsd);

        oracleWmaycToUsdArr[0] = address(oracleWmaycToUsd);

        oracleInterleaveToEthEthToUsd[0] = address(oracleInterleaveToEth);
        oracleInterleaveToEthEthToUsd[1] = address(oracleEthToUsd);

        oracleGenericStoreFrontToEthEthToUsd[0] = address(
            oracleGenericStoreFrontToEth
        );
        oracleGenericStoreFrontToEthEthToUsd[1] = address(oracleEthToUsd);

        vm.prank(creatorAddress);
        factory = new Factory();

        vm.startPrank(tokenCreatorAddress);
        asset = new Asset("Asset", "ASSET", uint8(Constants.assetDecimals));
        asset.mint(liquidityProvider, type(uint128).max);
        vm.stopPrank();

        vm.startPrank(creatorAddress);
        pool = new LiquidityPool(asset, creatorAddress, address(factory));
        pool.updateInterestRate(5 * 10**16); //5% with 18 decimals precision

        debt = new DebtToken(pool);
        pool.setDebtToken(address(debt));

        tranche = new Tranche(pool, "Senior", "SR");
        pool.addTranche(address(tranche), 50);
        vm.stopPrank();

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);


        vm.prank(address(tranche));
        pool.deposit(type(uint128).max, liquidityProvider);
    }

    //this is a before each
    function setUp() public {
        vm.startPrank(creatorAddress);
        mainRegistry = new MainRegistry(
            MainRegistry.BaseCurrencyInformation({
                baseCurrencyToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                baseCurrencyToUsdOracle: 0x0000000000000000000000000000000000000000,
                liquidityPool: address(pool),
                baseCurrencyLabel: "USD",
                baseCurrencyUnit: 1
            })
        );
        uint256[] memory emptyList = new uint256[](0);
        mainRegistry.addBaseCurrency(
            MainRegistry.BaseCurrencyInformation({
                baseCurrencyToUsdOracleUnit: uint64(
                    10**Constants.oracleEthToUsdDecimals
                ),
                assetAddress: address(eth),
                baseCurrencyToUsdOracle: address(oracleEthToUsd),
                liquidityPool: address(pool),
                baseCurrencyLabel: "ETH",
                baseCurrencyUnit: uint64(10**Constants.ethDecimals)
            }),
            emptyList
        );

        standardERC20Registry = new StandardERC20Registry(
            address(mainRegistry),
            address(oracleHub)
        );
        floorERC721SubRegistry = new FloorERC721SubRegistry(
            address(mainRegistry),
            address(oracleHub)
        );
        floorERC1155SubRegistry = new FloorERC1155SubRegistry(
            address(mainRegistry),
            address(oracleHub)
        );

        mainRegistry.addSubRegistry(address(standardERC20Registry));
        mainRegistry.addSubRegistry(address(floorERC721SubRegistry));
        mainRegistry.addSubRegistry(address(floorERC1155SubRegistry));

        uint256[] memory assetCreditRatings = new uint256[](2);
        assetCreditRatings[0] = 0;
        assetCreditRatings[1] = 0;

        standardERC20Registry.setAssetInformation(
            StandardERC20Registry.AssetInformation({
                oracleAddresses: oracleEthToUsdArr,
                assetUnit: uint64(10**Constants.ethDecimals),
                assetAddress: address(eth)
            }),
            assetCreditRatings
        );
        standardERC20Registry.setAssetInformation(
            StandardERC20Registry.AssetInformation({
                oracleAddresses: oracleLinkToUsdArr,
                assetUnit: uint64(10**Constants.linkDecimals),
                assetAddress: address(link)
            }),
            assetCreditRatings
        );
        standardERC20Registry.setAssetInformation(
            StandardERC20Registry.AssetInformation({
                oracleAddresses: oracleSnxToEthEthToUsd,
                assetUnit: uint64(10**Constants.snxDecimals),
                assetAddress: address(snx)
            }),
            assetCreditRatings
        );

        floorERC721SubRegistry.setAssetInformation(
            FloorERC721SubRegistry.AssetInformation({
                oracleAddresses: oracleWbaycToEthEthToUsd,
                idRangeStart: 0,
                idRangeEnd: type(uint256).max,
                assetAddress: address(bayc)
            }),
            assetCreditRatings
        );
        floorERC721SubRegistry.setAssetInformation(
            FloorERC721SubRegistry.AssetInformation({
                oracleAddresses: oracleWmaycToUsdArr,
                idRangeStart: 0,
                idRangeEnd: type(uint256).max,
                assetAddress: address(mayc)
            }),
            assetCreditRatings
        );
        floorERC1155SubRegistry.setAssetInformation(
            FloorERC1155SubRegistry.AssetInformation({
                oracleAddresses: oracleInterleaveToEthEthToUsd,
                id: 1,
                assetAddress: address(interleave)
            }),
            assetCreditRatings
        );
        floorERC1155SubRegistry.setAssetInformation(
            FloorERC1155SubRegistry.AssetInformation({
                oracleAddresses: oracleGenericStoreFrontToEthEthToUsd,
                id: 1,
                assetAddress: address(genericStoreFront)
            }),
            assetCreditRatings
        );

        liquidator = new Liquidator(
            0x0000000000000000000000000000000000000000,
            address(mainRegistry)
        );
        vm.stopPrank();

        vm.startPrank(vaultOwner);
        vault = new Vault();
        vm.stopPrank();

        vm.startPrank(creatorAddress);
        factory.setNewVaultInfo(
            address(mainRegistry),
            address(vault),
            Constants.upgradeProof1To2
        );
        factory.confirmNewVaultInfo();
        factory.setLiquidator(address(liquidator));
        pool.setLiquidator(address(liquidator));
        liquidator.setFactory(address(factory));
        mainRegistry.setFactory(address(factory));
        vm.stopPrank();

        vm.prank(vaultOwner);
        proxyAddr = factory.createVault(
            uint256(
                keccak256(
                    abi.encodeWithSignature(
                        "doRandom(uint256,uint256,bytes32)",
                        block.timestamp,
                        block.number,
                        blockhash(block.number)
                    )
                )
            ),
            0
        );
        proxy = Vault(proxyAddr);

        vm.startPrank(oracleOwner);
        oracleEthToUsd.transmit(int256(rateEthToUsd));
        oracleLinkToUsd.transmit(int256(rateLinkToUsd));
        oracleSnxToEth.transmit(int256(rateSnxToEth));
        oracleWbaycToEth.transmit(int256(rateWbaycToEth));
        oracleWmaycToUsd.transmit(int256(rateWmaycToUsd));
        oracleInterleaveToEth.transmit(int256(rateInterleaveToEth));
        vm.stopPrank();

        vm.roll(1); //increase block for random salt

        vm.startPrank(vaultOwner);
        proxy.authorize(address(pool), true);
        asset.approve(address(proxy), type(uint256).max);

        bayc.setApprovalForAll(address(proxy), true);
        mayc.setApprovalForAll(address(proxy), true);
        dickButs.setApprovalForAll(address(proxy), true);
        interleave.setApprovalForAll(address(proxy), true);
        eth.approve(address(proxy), type(uint256).max);
        link.approve(address(proxy), type(uint256).max);
        snx.approve(address(proxy), type(uint256).max);
        safemoon.approve(address(proxy), type(uint256).max);
        asset.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.prank(vaultBuyer);
        asset.approve(address(liquidator), type(uint256).max);

        vm.prank(tokenCreatorAddress);
        eth.mint(vaultOwner, 1e18);

        vm.startPrank(vaultOwner);

        s_1 = new address[](4);
        s_1[0] = address(eth);
        s_1[1] = address(link);
        s_1[2] = address(bayc);
        s_1[3] = address(mayc);

        s_2 = new uint256[](4);
        s_2[0] = 0;
        s_2[1] = 0;
        s_2[2] = 1;
        s_2[3] = 1;

        s_3 = new uint256[](4);
        s_3[0] = 10**Constants.ethDecimals;
        s_3[1] = 10**Constants.linkDecimals;
        s_3[2] = 1;
        s_3[3] = 1;

        s_4 = new uint256[](4);
        s_4[0] = 0;
        s_4[1] = 0;
        s_4[2] = 1;
        s_4[3] = 1;

        proxy.deposit(s_1, s_2, s_3, s_4);
        vm.stopPrank();

        vm.prank(vaultOwner);
        uint256 valueEth = (((10**18 * rateEthToUsd) /
            10**Constants.oracleEthToUsdDecimals) * s_3[0]) /
            10**Constants.ethDecimals;
        uint256 valueLink = (((10**18 * rateLinkToUsd) /
            10**Constants.oracleLinkToUsdDecimals) * s_3[1]) /
            10**Constants.linkDecimals;
        uint256 valueBayc = ((10**18 * rateWbaycToEth * rateEthToUsd) /
            10 **
                (Constants.oracleWbaycToEthDecimals +
                    Constants.oracleEthToUsdDecimals)) * s_3[2];
        uint256 valueMayc = ((10**18 * rateWmaycToUsd) /
            10**Constants.oracleWmaycToUsdDecimals) * s_3[3];
        pool.borrow(
            uint128(
                ((valueEth + valueLink + valueBayc + valueMayc) * 100) / 150
            )
       , address(proxy), vaultOwner);

        vm.startPrank(oracleOwner);
        oracleEthToUsd.transmit(int256(rateEthToUsd) / 2);
        oracleWbaycToEth.transmit(int256(rateWbaycToEth) / 2);
        oracleLinkToUsd.transmit(int256(rateLinkToUsd) / 2);
        oracleWmaycToUsd.transmit(int256(rateWmaycToUsd) / 2);
        vm.stopPrank();

        vm.prank(liquidatorBot);
        factory.liquidate(address(proxy));

        vm.prank(tokenCreatorAddress);
        asset.mint(vaultBuyer, 10**10 * 10**18);
    }

    function testBuyVaultStart() public {
        vm.roll(1); //compile warning to make it a view
        vm.prank(vaultBuyer);
        liquidator.buyVault(address(proxy), 0);
    }

    function testBuyVaultBl100() public {
        vm.roll(100);
        vm.prank(vaultBuyer);
        liquidator.buyVault(address(proxy), 0);
    }

    function testBuyVaultBl500() public {
        vm.roll(500);
        vm.prank(vaultBuyer);
        liquidator.buyVault(address(proxy), 0);
    }

    function testBuyVaultBl1000() public {
        vm.roll(1000);
        vm.prank(vaultBuyer);
        liquidator.buyVault(address(proxy), 0);
    }

    function testBuyVaultBl1500() public {
        vm.roll(1500);
        vm.prank(vaultBuyer);
        liquidator.buyVault(address(proxy), 0);
    }

    function testBuyVaultBl2000() public {
        vm.roll(2000);
        vm.prank(vaultBuyer);
        liquidator.buyVault(address(proxy), 0);
    }
}
