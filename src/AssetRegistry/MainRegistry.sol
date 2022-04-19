// This is a private, unpublished repository.
// All rights reserved to Arcadia Finance.
// Any modification, publication, reproduction, commercialisation, incorporation, sharing or any other kind of use of any part of this code or derivatives thereof is not allowed.
// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.4.22 <0.9.0;

import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../interfaces/IChainLinkData.sol";
import "../interfaces/IOraclesHub.sol";

import {FixedPointMathLib} from '../utils/FixedPointMathLib.sol';

interface ISubRegistry {
  function isAssetAddressWhiteListed(address) external view returns (bool);
  struct GetValueInput {
    address assetAddress;
    uint256 assetId;
    uint256 assetAmount;
    uint256 numeraire;
  }
  
  function isWhiteListed(address, uint256) external view returns (bool);
  function getValue(GetValueInput memory) external view returns (uint256, uint256);
}

/** 
  * @title Main Asset registry
  * @author Arcadia Finance
  * @notice The Main-registry stores basic information for each token that can, or could at some point, be deposited in the vaults
  * @dev No end-user should directly interact with the Main-registry, only vaults, Sub-Registries or the contract owner
 */ 
contract MainRegistry is Ownable {
  using FixedPointMathLib for uint256;

  uint256 public constant CREDIT_RATING_CATOGERIES = 10;

  bool public assetsUpdatable = true;
  address[] private subRegistries;
  address[] public assetsInMainRegistry;

  mapping (address => bool) public inMainRegistry;
  mapping (address => bool) public isSubRegistry;
  mapping (address => address) public assetToSubRegistry;

  address public factoryAddress;

  struct NumeraireInformation {
    uint64 numeraireToUsdOracleUnit;
    uint64 numeraireUnit;
    address assetAddress;
    address numeraireToUsdOracle;
    string numeraireLabel;
  }

  uint256 public numeraireLastIndex;
  mapping (uint256 => NumeraireInformation) public numeraireToInformation;

  mapping (address => mapping (uint256 => uint256)) public assetToNumeraireToCreditRating;




  /**
   * @dev Only Sub-registries can call functions marked by this modifier.
   **/
  modifier onlySubRegistry {
    require(isSubRegistry[msg.sender], 'Caller is not a sub-registry.');
    _;
  }

  /**
   * @notice The Main Registry must always be initialised with at least one Numeraire: USD
   * @dev If the Numeraire has no native token, numeraireDecimals should be set to 0 and assetAddress to the null address
   * @param _numeraireInformation A Struct with information about the Numeraire USD
   */
  constructor (NumeraireInformation memory _numeraireInformation) {
    //Main registry must be initialised with usd
    numeraireToInformation[numeraireLastIndex] = _numeraireInformation;
  }

  /**
   * @dev Sets the new Factory address
   * @param _factoryAddress The address of the Factory
   */
  function setFactory(address _factoryAddress) public {
    factoryAddress = _factoryAddress;
  }

  /**
   * @notice Checks for a list of tokens and a list of corresponding IDs if all tokens are white-listed
   * @param _assetAddresses The list of token addresses that needs to be checked 
   * @param _assetIds The list of corresponding token Ids that needs to be checked
   * @dev For each token address, a corresponding id at the same index should be present,
   *  for tokens without Id (ERC20 for instance), the Id should be set to 0
   * @return A boolean, indicating of all assets passed as input are whitelisted
   */
  function batchIsWhiteListed(
    address[] calldata _assetAddresses, 
    uint256[] calldata _assetIds
  ) public view returns (bool) {

    //Check if all ERC721 tokens are whitelisted
    uint256 addressesLength = _assetAddresses.length;
    require(addressesLength == _assetIds.length, "LENGTH_MISMATCH");

    for (uint256 i; i < addressesLength;) {
      if (!inMainRegistry[_assetAddresses[i]]) {
        return false;
      } else if (!ISubRegistry(assetToSubRegistry[_assetAddresses[i]]).isWhiteListed(_assetAddresses[i], _assetIds[i])) {
        return false;
      }
      unchecked {++i;}
    }

    return true;

  }

  /**
   * @notice returns a list of all white-listed token addresses
   * @dev Function is not gas-optimsed and not intended to be called by other smart contracts
   * @return A list of all white listed token Adresses
   */
  function getWhiteList() external view returns (address[] memory) {
    uint256 maxLength = assetsInMainRegistry.length;
    address[] memory whiteList = new address[](maxLength);

    uint256 counter = 0;
    for (uint256 i; i < maxLength;) {
      address assetAddress = assetsInMainRegistry[i];
      if (ISubRegistry(assetToSubRegistry[assetAddress]).isAssetAddressWhiteListed(assetAddress)) {
        whiteList[counter] = assetAddress;
        unchecked {++counter;}
      }
      unchecked {++i;}
    }

    return whiteList;
  }

  /**
   * @notice Add a Sub-registry Address to the list of Sub-Registries
   * @param subAssetRegistryAddress Address of the Sub-Registry
   */
  function addSubRegistry(address subAssetRegistryAddress) external onlyOwner {
    require(!isSubRegistry[subAssetRegistryAddress], 'Sub-Registry already exists');
    isSubRegistry[subAssetRegistryAddress] = true;
    subRegistries.push(subAssetRegistryAddress);
  }

  /**
   * @notice Add a new asset to the Main Registry, or overwrite an existing one (if assetsUpdatable is True)
   * @param assetAddress The address of the asset
   * @param assetCreditRatings The List of Credit Rating Categories for the asset for the different Numeraires
   * @dev The list of Credit Ratings should or be as long as the number of numeraires added to the Main Registry,
   *  or the list must have lenth 0. If the list has length zero, the credit ratings of the asset for all numeraires is
   *  is initiated as credit rating with index 0 by default (worst credit rating).
   *  Each Credit Rating Category is labeled with an integer, Category 0 (the default) is for the most risky assets.
   *  Category from 1 to 10 will be used to label groups of assets with similart risk profiles
   *  (Comparable to ratings like AAA, A-, B... for debtors in traditional finance).
   */
  function addAsset(address assetAddress, uint256[] memory assetCreditRatings) external onlySubRegistry {
    if (inMainRegistry[assetAddress]) {
      require(assetsUpdatable, 'Asset already known in Registry and not updatable');
    } else {
      inMainRegistry[assetAddress] = true;
      assetsInMainRegistry.push(assetAddress);
    }
    assetToSubRegistry[assetAddress] = msg.sender;

  
    uint256 assetCreditRatingsLength = assetCreditRatings.length;
    require(assetCreditRatingsLength == numeraireLastIndex + 1 || assetCreditRatingsLength == 0, 'Length list of credit ratings must be 0 or equal to number of numeraires');
    for (uint256 i; i < assetCreditRatingsLength; i++) {
      require(assetCreditRatings[i] < CREDIT_RATING_CATOGERIES, "Non existing credit Rating Category");
      assetToNumeraireToCreditRating[assetAddress][i] = assetCreditRatings[i];
    }
  }

  /**
   * @notice Change the Credit Rating Category for one or more assets for one or more numeraires
   * @param assets The List of addresses of the assets
   * @param numeraires The corresponding List of Numeraires
   * @param newCreditRating The corresponding List of new Credit Ratings
   * @dev The function loops over all indexes, and changes for each index the Credit Rating Category of the combination of asset and numeraire.
   *  In case multiple numeraires for the same assets need to be changed, the address must be repeated in the assets.
   *  Each Credit Rating Category is labeled with an integer, Category 0 (the default) is for the most risky assets.
   *  Category from 1 to 10 will be used to label groups of assets with similart risk profiles
   *  (Comparable to ratings like AAA, A-, B... for debtors in traditional finance).
   */
  function batchSetCreditRating(address[] calldata assets, uint256[] calldata numeraires, uint256[] calldata newCreditRating) external onlyOwner {
    uint256 assetsLength = assets.length;
    require(assetsLength == numeraires.length && assetsLength == newCreditRating.length, "MR BSCR: LENGTH_MISMATCH");

    for (uint i; i < assetsLength;) {
      require(newCreditRating[i] < CREDIT_RATING_CATOGERIES, "Non existing credit Rating Category");
      assetToNumeraireToCreditRating[assets[i]][numeraires[i]] = newCreditRating[i];
      unchecked {++i;}
    }
  }

  /**
   * @notice Disables the updatability of assets. In the disabled states, asset properties become immutable
   **/
  function setAssetsToNonUpdatable() external onlyOwner {
    assetsUpdatable = false;
  }

  /**
   * @notice Add a new numeraire to the Main Registry, or overwrite an existing one
   * @param numeraireInformation A Struct with information about the Numeraire
   * @param assetCreditRatings The List of the Credit Rating Categories of the numeraire, for all the different assets in the Main registry
   * @dev The list of Credit Rating Categories should or be as long as the number of assets added to the Main Registry,
   *  or the list must have lenth 0. If the list has length zero, the credit ratings of the numeraire for all assets is
   *  is initiated as credit rating with index 0 by default (worst credit rating).
   *  Each Credit Rating Category is labeled with an integer, Category 0 (the default) is for the most risky assets.
   *  Category from 1 to 10 will be used to label groups of assets with similart risk profiles
   *  (Comparable to ratings like AAA, A-, B... for debtors in traditional finance).
   *  ToDo: Add tests that existing numeraire cannot be entered second time?
   */
  function addNumeraire(NumeraireInformation calldata numeraireInformation, uint256[] memory assetCreditRatings) external onlyOwner {
    unchecked {++numeraireLastIndex;}
    numeraireToInformation[numeraireLastIndex] = numeraireInformation;

    uint256 assetCreditRatingsLength = assetCreditRatings.length;
    require(assetCreditRatingsLength == assetsInMainRegistry.length || assetCreditRatingsLength == 0, 'Length list of credit ratings must be 0 or equal number of assets in main registy');
    for (uint256 i; i < assetCreditRatingsLength;) {
      require(assetCreditRatings[i] < CREDIT_RATING_CATOGERIES, "Non existing credit Rating Category");
      assetToNumeraireToCreditRating[assetsInMainRegistry[i]][numeraireLastIndex] = assetCreditRatings[i];
      unchecked {++i;}
    }    
  }

  /**
   * @notice Calculate the total value of a list of assets denominated in a given Numeraire
   * @param _assetAddresses The List of token addresses of the assets
   * @param _assetIds The list of corresponding token Ids that needs to be checked
   * @dev For each token address, a corresponding id at the same index should be present,
   *  for tokens without Id (ERC20 for instance), the Id should be set to 0
   * @param _assetAmounts The list of corresponding amounts of each Token-Id combination
   * @param numeraire An identifier (uint256) of the Numeraire
   * @return The total value of the list of assets denominated in Numeraire
   * @dev Todo: Not yet tested for Over-and underflow
   */
  function getTotalValue(
    address[] calldata _assetAddresses, 
    uint256[] calldata _assetIds,
    uint256[] calldata _assetAmounts,
    uint256 numeraire
  ) public view returns (uint256) {
    uint256 valueInUsd;
    uint256 valueInNumeraire;

    require(numeraire <= numeraireLastIndex, "Unknown Numeraire");
    NumeraireInformation memory numeraireInformation = numeraireToInformation[numeraire];

    uint256 len = _assetAddresses.length;
    require(len == _assetIds.length && len == _assetAmounts.length, "MR GV: LENGTH_MISMATCH");
    ISubRegistry.GetValueInput memory getValueInput;
    getValueInput.numeraire = numeraire;

    for (uint256 i; i < len;) {
      address assetAddress = _assetAddresses[i];
      require(inMainRegistry[assetAddress], "Unknown asset");

      getValueInput.assetAddress = assetAddress;
      getValueInput.assetId = _assetIds[i];
      getValueInput.assetAmount = _assetAmounts[i];

      if (assetAddress == numeraireInformation.assetAddress) { //Should only be allowed if the numeraire is ETH, not for stablecoins or wrapped tokens
        valueInNumeraire = valueInNumeraire + _assetAmounts[i].mulDivDown(FixedPointMathLib.WAD, numeraireInformation.numeraireUnit); //_assetAmounts must be a with 18 decimals precision
      } else {
          //Calculate value of the next asset and add it to the total value of the vault
          (uint256 tempValueInUsd, uint256 tempValueInNumeraire) = ISubRegistry(assetToSubRegistry[assetAddress]).getValue(getValueInput);
          valueInUsd = valueInUsd + tempValueInUsd;
          valueInNumeraire = valueInNumeraire + tempValueInNumeraire;
      }
      unchecked {++i;}
    }
    if (numeraire == 0) { //Check if numeraire is USD
      return valueInUsd;
    } else if (valueInUsd > 0) {
      //Get the Numeraire-USD rate
      (,int256 rate,,,) = IChainLinkData(numeraireInformation.numeraireToUsdOracle).latestRoundData();
      //Add valueInUsd to valueInNumeraire, to check if conversion from int to uint can always be done
      valueInNumeraire = valueInNumeraire + valueInUsd.mulDivDown(numeraireInformation.numeraireToUsdOracleUnit, uint256(rate));
    }

    return valueInNumeraire;       

  }

  /**
   * @notice Calculate the value per asset of a list of assets denominated in a given Numeraire
   * @param _assetAddresses The List of token addresses of the assets
   * @param _assetIds The list of corresponding token Ids that needs to be checked
   * @dev For each token address, a corresponding id at the same index should be present,
   *  for tokens without Id (ERC20 for instance), the Id should be set to 0
   * @param _assetAmounts The list of corresponding amounts of each Token-Id combination
   * @param numeraire An identifier (uint256) of the Numeraire
   * @return The list of values per assets denominated in Numeraire
   * @dev Todo: Not yet tested for Over-and underflow
   */
  function getListOfValuesPerAsset(
    address[] calldata _assetAddresses, 
    uint256[] calldata _assetIds,
    uint256[] calldata _assetAmounts,
    uint256 numeraire
  ) public view returns (uint256[] memory) {
    
    uint256[] memory valuesPerAsset = new uint256[](_assetAddresses.length);

    require(numeraire <= numeraireLastIndex, "Unknown Numeraire");
    NumeraireInformation memory numeraireInformation = numeraireToInformation[numeraire];

    uint256 len = _assetAddresses.length;
    require(len == _assetIds.length && len == _assetAmounts.length, "MR GLV: LENGTH_MISMATCH");
    ISubRegistry.GetValueInput memory getValueInput;
    getValueInput.numeraire = numeraire;

    int256 rateNumeraireToUsd;

    for (uint256 i; i < len;) {
      address assetAddress = _assetAddresses[i];
      require(inMainRegistry[assetAddress], "Unknown asset");

      getValueInput.assetAddress = assetAddress;
      getValueInput.assetId = _assetIds[i];
      getValueInput.assetAmount = _assetAmounts[i];

      if (assetAddress == numeraireInformation.assetAddress) { //Should only be allowed if the numeraire is ETH, not for stablecoins or wrapped tokens
        valuesPerAsset[i] = _assetAmounts[i].mulDivDown(FixedPointMathLib.WAD, numeraireInformation.numeraireUnit); //_assetAmounts must be a with 18 decimals precision
      } else {
        //Calculate value of the next asset and add it to the total value of the vault
        (uint256 valueInUsd, uint256 valueInNumeraire) = ISubRegistry(assetToSubRegistry[assetAddress]).getValue(getValueInput);
        if (numeraire == 0) { //Check if numeraire is USD
          valuesPerAsset[i] = valueInUsd;
        } else if (valueInNumeraire > 0) {
            valuesPerAsset[i] = valueInNumeraire;
        } else {
          //Check if the Numeraire-USD rate is already fetched
          if (rateNumeraireToUsd == 0) {
            //Get the Numeraire-USD rate ToDo: Ask via the OracleHub?
            (,rateNumeraireToUsd,,,) = IChainLinkData(numeraireInformation.numeraireToUsdOracle).latestRoundData();  
          }
          valuesPerAsset[i] = valueInUsd.mulDivDown(numeraireInformation.numeraireToUsdOracleUnit, uint256(rateNumeraireToUsd));
        }
      }
      unchecked {++i;}
    }
    return valuesPerAsset;
  }

  /**
   * @notice Calculate the value per Credit Rating Category of a list of assets denominated in a given Numeraire
   * @param _assetAddresses The List of token addresses of the assets
   * @param _assetIds The list of corresponding token Ids that needs to be checked
   * @dev For each token address, a corresponding id at the same index should be present,
   *  for tokens without Id (ERC20 for instance), the Id should be set to 0
   * @param _assetAmounts The list of corresponding amounts of each Token-Id combination
   * @param numeraire An identifier (uint256) of the Numeraire
   * @return The list of values per Credit Rating Category denominated in Numeraire
   * @dev Todo: Not yet tested for Over-and underflow
   */
 function getListOfValuesPerCreditRating(
    address[] calldata _assetAddresses, 
    uint256[] calldata _assetIds,
    uint256[] calldata _assetAmounts,
    uint256 numeraire
  ) public view returns (uint256[] memory) {

    uint256[] memory ValuesPerCreditRating = new uint256[](CREDIT_RATING_CATOGERIES);
    uint256[] memory valuesPerAsset = getListOfValuesPerAsset(_assetAddresses, _assetIds, _assetAmounts, numeraire);

    uint256 valuesPerAssetLength = valuesPerAsset.length;
    for (uint256 i; i < valuesPerAssetLength;) {
      address assetAdress = _assetAddresses[i];
      ValuesPerCreditRating[assetToNumeraireToCreditRating[assetAdress][numeraire]] += valuesPerAsset[i];
      unchecked {++i;}
    }

    return ValuesPerCreditRating;
  }

}