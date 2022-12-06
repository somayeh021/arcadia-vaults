/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity >=0.4.22 <0.9.0;

import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../interfaces/IOraclesHub.sol";
import "../interfaces/IMainRegistry.sol";
import {FixedPointMathLib} from "../utils/FixedPointMathLib.sol";

/**
 * @title Abstract Pricing Module
 * @author Arcadia Finance
 * @notice Sub-Registries have the pricing logic and basic information for tokens that can, or could at some point, be deposited in the vaults
 * @dev No end-user should directly interact with Sub-Registries, only the Main-registry, Oracle-Hub or the contract owner
 * @dev This abstract contract contains the minimal functions that each Pricing Module should have to properly work with the Main-Registry
 */
abstract contract PricingModule is Ownable {
    using FixedPointMathLib for uint256;

    uint16 public constant VARIABLE_DECIMAL = 100;

    uint16 public constant MIN_COLLATERAL_FACTOR = 0;
    uint16 public constant MIN_LIQUIDATION_THRESHOLD = 100;

    uint16 public constant MAX_COLLATERAL_FACTOR = 100;
    uint16 public constant MAX_LIQUIDATION_THRESHOLD = 10000;

    uint16 public constant DEFAULT_COLLATERAL_FACTOR = 20;
    uint16 public constant DEFAULT_LIQUIDATION_THRESHOLD = 110;

    address public mainRegistry;
    address public oracleHub;

    address[] public assetsInPricingModule;

    mapping(address => bool) public inPricingModule;
    mapping(address => bool) public isAssetAddressWhiteListed;

    //struct with input variables necessary to avoid stack to deep error
    struct GetValueInput {
        address assetAddress;
        uint256 assetId;
        uint256 assetAmount;
        uint256 baseCurrency;
    }

    modifier onlyMainRegistry() {
        require(msg.sender == mainRegistry, "APM: ONLY_MAIN_REGISTRY");
        _;
    }

    /**
     * @notice A Pricing Module must always be initialised with the address of the Main-Registry and the Oracle-Hub
     * @param _mainRegistry The address of the Main-registry
     * @param _oracleHub The address of the Oracle-Hub
     */
    constructor(address _mainRegistry, address _oracleHub) {
        mainRegistry = _mainRegistry;
        oracleHub = _oracleHub;
    }

    /*///////////////////////////////////////////////////////////////
                        WHITE LIST MANAGEMENT
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks for a token address and the corresponding Id, if it is white-listed
     * @return A boolean, indicating if the asset passed as input is whitelisted
     * @dev For tokens without Id (for instance ERC20 tokens), the Id should be set to 0
     */
    function isWhiteListed(address, uint256) external view virtual returns (bool) {
        return false;
    }

    /**
     * @notice Removes an asset from the white-list
     * @param assetAddress The token address of the asset that needs to be removed from the white-list
     */
    function removeFromWhiteList(address assetAddress) external onlyOwner {
        require(inPricingModule[assetAddress], "Asset not known in Pricing Module");
        isAssetAddressWhiteListed[assetAddress] = false;
    }

    /**
     * @notice Adds an asset back to the white-list
     * @param assetAddress The token address of the asset that needs to be added back to the white-list
     */
    function addToWhiteList(address assetAddress) external onlyOwner {
        require(inPricingModule[assetAddress], "Asset not known in Pricing Module");
        isAssetAddressWhiteListed[assetAddress] = true;
    }

    /*///////////////////////////////////////////////////////////////
                          PRICING LOGIC
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the value of a certain asset, denominated in USD or in another BaseCurrency
     * @dev The value of the asset can be denominated in:
     * - USD.
     * - A given BaseCurrency, different from USD.
     * - A combination of USD and a given BaseCurrency, different from USD (will be very exceptional,
     * but theoratically possible for eg. a UNI V2 LP position of two underlying assets,
     * one denominated in USD and the other one in the different BaseCurrency).
     * @dev All price feeds should be fetched in the Oracle-Hub
     */
    function getValue(GetValueInput memory) public view virtual returns (uint256, uint256, uint256, uint256) {}

    function setRiskVariables(address, uint16[] memory, uint16[] memory) external virtual {}
    function _setRiskVariables(
        address assetAddress,
        uint16[] memory assetCollateralFactors,
        uint16[] memory assetLiquidationThresholds
    ) internal virtual {}
}
