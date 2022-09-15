/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity >=0.8.0 <0.9.0;

import "../utils/LogExpMath.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IERC1155.sol";
import "../interfaces/IERC4626.sol";
import "../interfaces/ILiquidator.sol";
import "../interfaces/IRegistry.sol";
import "../interfaces/IMainRegistry.sol";
import "../interfaces/ILendingPool.sol";

import "../interfaces/ITrustedProtocol.sol";

/** 
  * @title An Arcadia Vault used to deposit a combination of all kinds of assets
  * @author Arcadia Finance
  * @notice Users can use this vault to deposit assets (ERC20, ERC721, ERC1155, ...). 
            The vault will denominate all the pooled assets into one baseCurrency (one unit of account, like usd or eth).
            An increase of value of one asset will offset a decrease in value of another asset.
            Users can take out a credit line against the single denominated value.
            Ensure your total value denomination remains above the liquidation threshold, or risk being liquidated!
  * @dev A vault is a smart contract that will contain multiple assets.
         Using getValue(<baseCurrency>), the vault returns the combined total value of all (whitelisted) assets the vault contains.
         Integrating this vault as means of collateral management for your own protocol that requires collateral is encouraged.
         Arcadia's vault functions will guarantee you a certain value of the vault.
         For whitelists or liquidation strategies specific to your protocol, contact: dev at arcadia.finance
 */
contract VaultV2 {

    constructor() {}

    /*///////////////////////////////////////////////////////////////
                          VAULT MANAGEMENT
    ///////////////////////////////////////////////////////////////*/

    /**
     * @dev Storage slot with the address of the current implementation.
     *      This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Each vault has a certain 'life', equal to the amount of times the vault is liquidated.
    // Used by the liquidator contract for proceed claims
    uint256 public life;
    uint16 public vaultVersion;
    address public registryAddress;
    address public liquidator;

    struct VaultInfo {
        uint16 collThres; //2 decimals precision (factor 100)
        uint8 liqThres; //2 decimals precision (factor 100)
        address baseCurrency;
        //address baseCurrencyAddress;
    }

    VaultInfo public vault;

    struct AddressSlot {
        address value;
    }

     /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot)
        internal
        pure
        returns (AddressSlot storage r)
    {
        assembly {
            r.slot := slot
        }
    }

    /** 
    @notice Initiates the variables of the vault
    @dev A proxy will be used to interact with the vault logic.
         Therefore everything is initialised through an init function.
         This function will only be called (once) in the same transaction as the proxy vault creation through the factory.
         Costly function (156k gas)
    @param _owner The tx.origin: the sender of the 'createVault' on the factory
    @param _registryAddress The 'beacon' contract to which should be looked at for external logic.
    @param _vaultVersion The version of the vault logic.
  */
    function initialize(
        address _owner,
        address _registryAddress,
        uint16 _vaultVersion
    ) external payable {
        require(vaultVersion == 0, "V_I: Already initialized!");
        require(_vaultVersion != 0, "V_I: Invalid vault version");
        owner = _owner;
        registryAddress = _registryAddress;
        vaultVersion = _vaultVersion;
        //ToDo: riskmodule
        vault.collThres = 150;
        vault.liqThres = 110;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot & updates the vault version.
     */
    function upgradeVault(address newImplementation, uint16 newVersion) external onlyFactory {
        vaultVersion = newVersion;
        getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /*///////////////////////////////////////////////////////////////
                          ACCESS MANAGEMENT
    ///////////////////////////////////////////////////////////////*/

    address public owner;
    mapping(address => bool) public allowed;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Throws if called by any account other than the factory adress.
     */
    modifier onlyFactory() {
        require(
            msg.sender == IMainRegistry(registryAddress).factoryAddress(),
            "VL: You are not the factory"
        );
        _;
    }

    /**
     * @dev Throws if called by any account other than an authorised adress.
     */
    modifier onlyAuthorized() {
        require(
            allowed[msg.sender],
            "VL: You are not authorized"
        );
        _;
    }

    function authorize(address user, bool isAuthorized) external onlyOwner {
        allowed[user] = isAuthorized;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "VL: You are not the owner");
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner via the factory.
     * A transfer of ownership of this vault by a transfer
     * of ownership of the accompanying ERC721 Vault NFT
     * issued by the factory. Owner of Vault NFT = owner of vault
     */
    function transferOwnership(address newOwner) public onlyFactory {
        if (newOwner == address(0)) {
            revert("New owner cannot be zero address upon liquidation");
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /*///////////////////////////////////////////////////////////////
                    ASSET DEPOSIT/WITHDRAWN LOGIC
    ///////////////////////////////////////////////////////////////*/

    address[] public erc20Stored;
    address[] public erc721Stored;
    address[] public erc1155Stored;

    uint256[] public erc721TokenIds;
    uint256[] public erc1155TokenIds;

    /** 
    @notice Deposits assets into the proxy vault by the proxy vault owner.
    @dev All arrays should be of same length, each index in each array corresponding
         to the same asset that will get deposited. If multiple asset IDs of the same contract address
         are deposited, the assetAddress must be repeated in assetAddresses.
         The ERC20 gets deposited by transferFrom. ERC721 & ERC1155 using safeTransferFrom.
         Can only be called by the proxy vault owner to avoid attacks where malicous actors can deposit 1 wei assets,
         increasing gas costs upon credit issuance and withrawals.
         Example inputs:
            [wETH, DAI, Bayc, Interleave], [0, 0, 15, 2], [10**18, 10**18, 1, 100], [0, 0, 1, 2]
            [Interleave, Interleave, Bayc, Bayc, wETH], [3, 5, 16, 17, 0], [123, 456, 1, 1, 10**18], [2, 2, 1, 1, 0]
    @param assetAddresses The contract addresses of the asset. For each asset to be deposited one address,
                          even if multiple assets of the same contract address are deposited.
    @param assetIds The asset IDs that will be deposited for ERC721 & ERC1155. 
                    When depositing an ERC20, this will be disregarded, HOWEVER a value (eg. 0) must be filled!
    @param assetAmounts The amounts of the assets to be deposited. 
    @param assetTypes The types of the assets to be deposited.
                      0 = ERC20
                      1 = ERC721
                      2 = ERC1155
                      Any other number = failed tx
  */
    function deposit(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        uint256[] calldata assetTypes
    ) external payable onlyOwner {
        uint256 assetAddressesLength = assetAddresses.length;

        require(
            assetAddressesLength == assetIds.length &&
                assetAddressesLength == assetAmounts.length &&
                assetAddressesLength == assetTypes.length,
            "Length mismatch"
        );

        require(
            IRegistry(registryAddress).batchIsWhiteListed(
                assetAddresses,
                assetIds
            ),
            "Not all assets are whitelisted!"
        );

        for (uint256 i; i < assetAddressesLength; ) {
            if (assetTypes[i] == 0) {
                _depositERC20(msg.sender, assetAddresses[i], assetAmounts[i]);
            } else if (assetTypes[i] == 1) {
                _depositERC721(msg.sender, assetAddresses[i], assetIds[i]);
            } else if (assetTypes[i] == 2) {
                _depositERC1155(
                    msg.sender,
                    assetAddresses[i],
                    assetIds[i],
                    assetAmounts[i]
                );
            } else {
                require(false, "Unknown asset type");
            }
            unchecked {
                ++i;
            }
        }
    }

    /** 
    @notice Internal function used to deposit ERC20 tokens.
    @dev Used for all tokens types = 0. Note the transferFrom, not the safeTransferFrom to allow legacy ERC20s.
         After successful transfer, the function checks whether the same asset has been deposited. 
         This check is done using a loop: writing it in a mapping vs extra loops is in favor of extra loops in this case.
         If the address has not yet been seen, the ERC20 token address is stored.
    @param _from Address the tokens should be taken from. This address must have pre-approved the proxy vault.
    @param ERC20Address The asset address that should be transferred.
    @param amount The amount of ERC20 tokens to be transferred.
  */
    function _depositERC20(
        address _from,
        address ERC20Address,
        uint256 amount
    ) private {
        require(
            IERC20(ERC20Address).transferFrom(_from, address(this), amount),
            "Transfer from failed"
        );

        uint256 erc20StoredLength = erc20Stored.length;
        for (uint256 i; i < erc20StoredLength; ) {
            if (erc20Stored[i] == ERC20Address) {
                return;
            }
            unchecked {
                ++i;
            }
        }

        erc20Stored.push(ERC20Address); //TODO: see what the most gas efficient manner is to store/read/loop over this list to avoid duplicates
    }

    /** 
    @notice Internal function used to deposit ERC721 tokens.
    @dev Used for all tokens types = 1. Note the transferFrom. No amounts are given since ERC721 are one-off's.
         After successful transfer, the function pushes the ERC721 address to the stored token and stored ID array.
         This may cause duplicates in the ERC721 stored addresses array, but this is intended. 
    @param _from Address the tokens should be taken from. This address must have pre-approved the proxy vault.
    @param ERC721Address The asset address that should be transferred.
    @param id The ID of the token to be transferred.
  */
    function _depositERC721(
        address _from,
        address ERC721Address,
        uint256 id
    ) private {
        IERC721(ERC721Address).transferFrom(_from, address(this), id);

        erc721Stored.push(ERC721Address); //TODO: see what the most gas efficient manner is to store/read/loop over this list to avoid duplicates
        erc721TokenIds.push(id);
    }

    /** 
    @notice Internal function used to deposit ERC1155 tokens.
    @dev Used for all tokens types = 2. Note the safeTransferFrom.
         After successful transfer, the function checks whether the combination of address & ID has already been stored.
         If not, the function pushes the new address and ID to the stored arrays.
         This may cause duplicates in the ERC1155 stored addresses array, but this is intended. 
    @param _from The Address the tokens should be taken from. This address must have pre-approved the proxy vault.
    @param ERC1155Address The asset address that should be transferred.
    @param id The ID of the token to be transferred.
    @param amount The amount of ERC1155 tokens to be transferred.
  */
    function _depositERC1155(
        address _from,
        address ERC1155Address,
        uint256 id,
        uint256 amount
    ) private {
        IERC1155(ERC1155Address).safeTransferFrom(
            _from,
            address(this),
            id,
            amount,
            ""
        );

        bool addrSeen;

        uint256 erc1155StoredLength = erc1155Stored.length;
        for (uint256 i; i < erc1155StoredLength; ) {
            if (erc1155Stored[i] == ERC1155Address) {
                if (erc1155TokenIds[i] == id) {
                    addrSeen = true;
                    break;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (!addrSeen) {
            erc1155Stored.push(ERC1155Address); //TODO: see what the most gas efficient manner is to store/read/loop over this list to avoid duplicates
            erc1155TokenIds.push(id);
        }
    }

    /** 
    @notice Processes withdrawals of assets by and to the owner of the proxy vault.
    @dev All arrays should be of same length, each index in each array corresponding
         to the same asset that will get withdrawn. If multiple asset IDs of the same contract address
         are to be withdrawn, the assetAddress must be repeated in assetAddresses.
         The ERC20 get withdrawn by transfers. ERC721 & ERC1155 using safeTransferFrom.
         Can only be called by the proxy vault owner.
         Will fail if balance on proxy vault is not sufficient for one of the withdrawals.
         Will fail if "the value after withdrawal / open debt (including unrealised debt) > collateral threshold".
         If no debt is taken yet on this proxy vault, users are free to withraw any asset at any time.
         Example inputs:
            [wETH, DAI, Bayc, Interleave], [0, 0, 15, 2], [10**18, 10**18, 1, 100], [0, 0, 1, 2]
            [Interleave, Interleave, Bayc, Bayc, wETH], [3, 5, 16, 17, 0], [123, 456, 1, 1, 10**18], [2, 2, 1, 1, 0]
    @dev After withdrawing assets, the interest rate is renewed
    @param assetAddresses The contract addresses of the asset. For each asset to be withdrawn one address,
                          even if multiple assets of the same contract address are withdrawn.
    @param assetIds The asset IDs that will be withdrawn for ERC721 & ERC1155. 
                    When withdrawing an ERC20, this will be disregarded, HOWEVER a value (eg. 0) must be filled!
    @param assetAmounts The amounts of the assets to be withdrawn. 
    @param assetTypes The types of the assets to be withdrawn.
                      0 = ERC20
                      1 = ERC721
                      2 = ERC1155
                      Any other number = failed tx
  */
    function withdraw(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        uint256[] calldata assetTypes
    ) external payable onlyOwner {
        uint256 assetAddressesLength = assetAddresses.length;

        require(
            assetAddressesLength == assetIds.length &&
                assetAddressesLength == assetAmounts.length &&
                assetAddressesLength == assetTypes.length,
            "Length mismatch"
        );

        for (uint256 i; i < assetAddressesLength; ) {
            if (assetTypes[i] == 0) {
                _withdrawERC20(msg.sender, assetAddresses[i], assetAmounts[i]);
            } else if (assetTypes[i] == 1) {
                _withdrawERC721(msg.sender, assetAddresses[i], assetIds[i]);
            } else if (assetTypes[i] == 2) {
                _withdrawERC1155(
                    msg.sender,
                    assetAddresses[i],
                    assetIds[i],
                    assetAmounts[i]
                );
            } else {
                require(false, "Unknown asset type");
            }
            unchecked {
                ++i;
            }
        }

        uint256 usedMargin = getUsedMargin();
        if (usedMargin != 0) {
            require(getCollateralValue() > usedMargin, "V_W: coll. value too low!");
        }
    }

    /** 
    @notice Internal function used to withdraw ERC20 tokens.
    @dev Used for all tokens types = 0. Note the transferFrom, not the safeTransferFrom to allow legacy ERC20s.
         After successful transfer, the function checks whether the proxy vault has any leftover balance of said asset.
         If not, it will pop() the ERC20 asset address from the stored addresses array.
         Note: this shifts the order of erc20Stored! 
         This check is done using a loop: writing it in a mapping vs extra loops is in favor of extra loops in this case.
    @param to Address the tokens should be sent to. This will in any case be the proxy vault owner
              either being the original user or the liquidator!.
    @param ERC20Address The asset address that should be transferred.
    @param amount The amount of ERC20 tokens to be transferred.
  */
    function _withdrawERC20(
        address to,
        address ERC20Address,
        uint256 amount
    ) private {
        require(
            IERC20(ERC20Address).transfer(to, amount),
            "Transfer from failed"
        );

        if (IERC20(ERC20Address).balanceOf(address(this)) == 0) {
            uint256 erc20StoredLength = erc20Stored.length;

            if (erc20StoredLength == 1) {
                // there was only one ERC20 stored on the contract, safe to remove list
                erc20Stored.pop();
            } else {
                for (uint256 i; i < erc20StoredLength; ) {
                    if (erc20Stored[i] == ERC20Address) {
                        erc20Stored[i] = erc20Stored[erc20StoredLength - 1];
                        erc20Stored.pop();
                        break;
                    }
                    unchecked {
                        ++i;
                    }
                }
            }
        }
    }

    /** 
    @notice Internal function used to withdraw ERC721 tokens.
    @dev Used for all tokens types = 1. Note the safeTransferFrom. No amounts are given since ERC721 are one-off's.
         After successful transfer, the function checks whether any other ERC721 is deposited in the proxy vault.
         If not, it pops the stored addresses and stored IDs (pop() of two arrs is 180 gas cheaper than deleting).
         If there are, it loops through the stored arrays and searches the ID that's withdrawn, 
         then replaces it with the last index, followed by a pop().
         Sensitive to ReEntrance attacks! SafeTransferFrom therefore done at the end of the function.
    @param to Address the tokens should be taken from. This address must have pre-approved the proxy vault.
    @param ERC721Address The asset address that should be transferred.
    @param id The ID of the token to be transferred.
  */
    function _withdrawERC721(
        address to,
        address ERC721Address,
        uint256 id
    ) private {
        uint256 tokenIdLength = erc721TokenIds.length;

        if (tokenIdLength == 1) {
            // there was only one ERC721 stored on the contract, safe to remove both lists
            erc721TokenIds.pop();
            erc721Stored.pop();
        } else {
            for (uint256 i; i < tokenIdLength; ) {
                if (
                    erc721TokenIds[i] == id &&
                    erc721Stored[i] == ERC721Address
                ) {
                    erc721TokenIds[i] = erc721TokenIds[tokenIdLength - 1];
                    erc721TokenIds.pop();
                    erc721Stored[i] = erc721Stored[tokenIdLength - 1];
                    erc721Stored.pop();
                    break;
                }
                unchecked {
                    ++i;
                }
            }
        }

        IERC721(ERC721Address).safeTransferFrom(address(this), to, id);
    }

    /** 
    @notice Internal function used to withdraw ERC1155 tokens.
    @dev Used for all tokens types = 2. Note the safeTransferFrom.
         After successful transfer, the function checks whether there is any balance left for that ERC1155.
         If there is, it simply transfers the tokens.
         If not, it checks whether it can pop() (used for gas savings vs delete) the stored arrays.
         If there are still other ERC1155's on the contract, it looks for the ID and token address to be withdrawn
         and then replaces it with the last index, followed by a pop().
         Sensitive to ReEntrance attacks! SafeTransferFrom therefore done at the end of the function.
    @param to Address the tokens should be taken from. This address must have pre-approved the proxy vault.
    @param ERC1155Address The asset address that should be transferred.
    @param id The ID of the token to be transferred.
    @param amount The amount of ERC1155 tokens to be transferred.
  */
    function _withdrawERC1155(
        address to,
        address ERC1155Address,
        uint256 id,
        uint256 amount
    ) private {
        uint256 tokenIdLength = erc1155TokenIds.length;
        if (
            IERC1155(ERC1155Address).balanceOf(address(this), id) - amount == 0
        ) {
            if (tokenIdLength == 1) {
                erc1155TokenIds.pop();
                erc1155Stored.pop();
            } else {
                for (uint256 i; i < tokenIdLength; ) {
                    if (erc1155TokenIds[i] == id) {
                        if (erc1155Stored[i] == ERC1155Address) {
                            erc1155TokenIds[i] = erc1155TokenIds[
                                tokenIdLength - 1
                            ];
                            erc1155TokenIds.pop();
                            erc1155Stored[i] = erc1155Stored[
                                tokenIdLength - 1
                            ];
                            erc1155Stored.pop();
                            break;
                        }
                    }
                    unchecked {
                        ++i;
                    }
                }
            }
        }

        IERC1155(ERC1155Address).safeTransferFrom(
            address(this),
            to,
            id,
            amount,
            ""
        );
    }

    /** 
    @notice Generates three arrays about the stored assets in the proxy vault
            in the format needed for vault valuation functions.
    @dev No balances are stored on the contract. Both for gas savings upon deposit and to allow for rebasing/... tokens.
         Loops through the stored asset addresses and fills the arrays. 
         The vault valuation function fetches the asset type through the asset registries.
         There is no importance of the order in the arrays, but all indexes of the arrays correspond to the same asset.
    @return assetAddresses An array of asset addresses.
    @return assetIds An array of asset IDs. Will be '0' for ERC20's
    @return assetAmounts An array of the amounts/balances of the asset on the proxy vault. wil be '1' for ERC721's
  */
    function generateAssetData()
        public
        view
        returns (
            address[] memory assetAddresses,
            uint256[] memory assetIds,
            uint256[] memory assetAmounts
        )
    {
        uint256 totalLength;
        unchecked {
            totalLength =
                erc20Stored.length +
                erc721Stored.length +
                erc1155Stored.length;
        } //cannot practiaclly overflow. No max(uint256) contracts deployed
        assetAddresses = new address[](totalLength);
        assetIds = new uint256[](totalLength);
        assetAmounts = new uint256[](totalLength);

        uint256 i;
        uint256 erc20StoredLength = erc20Stored.length;
        address cacheAddr;
        for (; i < erc20StoredLength; ) {
            cacheAddr = erc20Stored[i];
            assetAddresses[i] = cacheAddr;
            //assetIds[i] = 0; //gas: no need to store 0, index will continue anyway
            assetAmounts[i] = IERC20(cacheAddr).balanceOf(address(this));
            unchecked {
                ++i;
            }
        }

        uint256 j;
        uint256 erc721StoredLength = erc721Stored.length;
        for (; j < erc721StoredLength; ) {
            cacheAddr = erc721Stored[j];
            assetAddresses[i] = cacheAddr;
            assetIds[i] = erc721TokenIds[j];
            assetAmounts[i] = 1;
            unchecked {
                ++i;
            }
            unchecked {
                ++j;
            }
        }

        uint256 k;
        uint256 erc1155StoredLength = erc1155Stored.length;
        for (; k < erc1155StoredLength; ) {
            cacheAddr = erc1155Stored[k];
            assetAddresses[i] = cacheAddr;
            assetIds[i] = erc1155TokenIds[k];
            assetAmounts[i] = IERC1155(cacheAddr).balanceOf(
                address(this),
                erc1155TokenIds[k]
            );
            unchecked {
                ++i;
            }
            unchecked {
                ++k;
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                        BASE CURRENCY LOGIC
    ///////////////////////////////////////////////////////////////*/

    /** 
    @notice Sets the baseCurrency of a vault.
    @param baseCurrency the new baseCurrency for the vault.
  */
    function setBaseCurrency(address baseCurrency) public onlyAuthorized {
        _setBaseCurrency(baseCurrency);
    }

    /** 
    @notice Internal function: sets baseCurrency.
    @param _baseCurrency the new baseCurrency for the vault.
    @dev First checks if there is no locked value. If there is no value locked then the baseCurrency gets changed to the param
  */
    function _setBaseCurrency(
        address _baseCurrency
    ) private {
        require(getUsedMargin() == 0, "VL_SBC: Can't change baseCurrency when Used Margin > 0");
        require(IMainRegistry(registryAddress).isBaseCurrency(_baseCurrency), "VL_SBC: baseCurrency not found");
        vault.baseCurrency = _baseCurrency; //Change this to where ever it is going to be actually set
    }

    /*///////////////////////////////////////////////////////////////
                    MARGIN ACCOUNT SETTINGS
    ///////////////////////////////////////////////////////////////*/

    bool isTrustedProtocolSet;
    address public trustedProtocol;

    /** 
    @notice Initiates a margin account on the vault for one trusted application..
    @param protocol The contract address of the trusted application.
    @dev The open position is fetched at a contract of the application -> only allow trusted audited protocols!!!
    @dev Currently only one trusted protocol can be set.
    */
    function openTrustedMarginAccount(address protocol) onlyOwner public {
        require(!isTrustedProtocolSet, "V_OMA: ALREADY SET");
        //ToDo: Check in Factory/Mainregistry if protocol is indeed trusted?

        (bool success, address baseCurrency, address liquidator_) = ITrustedProtocol(protocol).openMarginAccount();
        require(success, "V_OMA: OPENING ACCOUNT REVERTED");

        liquidator = liquidator_;
        trustedProtocol = protocol;
        if (vault.baseCurrency != baseCurrency) _setBaseCurrency(baseCurrency);
        IERC20(baseCurrency).approve(protocol, type(uint256).max);
        isTrustedProtocolSet = true;
        allowed[protocol] = true;
    }

    /** 
    @notice Closes the margin account on the vault of the trusted application..
    @dev The open position is fetched at a contract of the application -> only allow trusted audited protocols!!!
    @dev Currently only one trusted protocol can be set.
    */
    function closeTrustedMarginAccount() public onlyOwner {
        require(isTrustedProtocolSet, "V_CMA: NOT SET");
        require(ITrustedProtocol(trustedProtocol).getOpenPosition(address(this)) == 0, "V_CMA: NON-ZERO OPEN POSITION");

        isTrustedProtocolSet = false;
        allowed[trustedProtocol] = false;
    }

    /*///////////////////////////////////////////////////////////////
                          MARGIN REQUIREMENTS
    ///////////////////////////////////////////////////////////////*/

    /** 
    @notice Returns the total value of the vault in a specific baseCurrency
    @dev Fetches all stored assets with their amounts on the proxy vault.
         Using a specified baseCurrency, fetches the value of all assets on the proxy vault in said baseCurrency.
    @param baseCurrency The asset to return the value in.
    @return vaultValue Total value stored on the vault, expressed in baseCurrency.
    */
    function getVaultValue(address baseCurrency)
        public
        view
        returns (uint256 vaultValue)
    {
        (
            address[] memory assetAddresses,
            uint256[] memory assetIds,
            uint256[] memory assetAmounts
        ) = generateAssetData();
        vaultValue = IRegistry(registryAddress).getTotalValue(
            assetAddresses,
            assetIds,
            assetAmounts,
            baseCurrency
        );
    }

    /** 
    @notice Calculates the total collateral value of the vault.
    @return collateralValue The collateral value, returned in the decimals of the base currency.
    @dev Returns the value denominated in the baseCurrency in which the proxy vault is initialised.
    @dev The collateral value of the vault is equal to the spot value of the underlying assets,
         discounted by a haircut (with a factor 100 / collateral_threshold). Since the value of
         collateralised assets can fluctuate, the haircut guarantees that the vault 
         remains over-collateralised with a high confidence level (99,9%+). The size of the
         haircut depends on the underlying risk of the assets in the vault, the bigger the volatility
         or the smaller the on-chain liquidity, the biggert the haircut will be.
    */
    function getCollateralValue()
        public
        view
        returns (uint256 collateralValue)
    {
        //gas: cannot overflow unless currentValue is more than
        // 1.15**57 *10**18 decimals, which is too many billions to write out
        unchecked {
            collateralValue = getVaultValue(vault.baseCurrency) * 100 / vault.collThres;
        }
    }

    /** 
    @notice Calculates the total collateral value of the vault.
    @param vaultValue The total spot value of all the assets in the vault.
    @return collateralValue The collateral value, returned in the decimals of the base currency.
    @dev Returns the value denominated in the baseCurrency in which the proxy vault is initialised.
    @dev The collateral value of the vault is equal to the spot value of the underlying assets,
         discounted by a haircut (with a factor 100 / collateral_threshold). Since the value of
         collateralised assets can fluctuate, the haircut guarantees that the vault 
         remains over-collateralised with a high confidence level (99,9%+). The size of the
         haircut depends on the underlying risk of the assets in the vault, the bigger the volatility
         or the smaller the on-chain liquidity, the biggert the haircut will be.
    */
    function getCollateralValue(uint256 vaultValue)
        public
        view
        returns (uint256 collateralValue)
    {
        //gas: cannot overflow unless currentValue is more than
        // 1.15**57 *10**18 decimals, which is too many billions to write out
        unchecked {
            collateralValue = vaultValue * 100 / vault.collThres;
        }
    }

    /** 
    @notice Returns the used margin of the proxy vault.
    @return usedMargin The used amount of margin a user has taken
    @dev The used margin is denominated in the baseCurrency of the proxy vault.
    @dev Currently only one trusted application (Arcadia Lending) can open a margin account.
         The open position is fetched at a contract of the application -> only allow trusted audited protocols!!! 
    */
    function getUsedMargin() public returns (uint128 usedMargin) {
        usedMargin = ITrustedProtocol(trustedProtocol).getOpenPosition(address(this)); // ToDo: Check if cast is safe
    }

    /** 
    @notice Calculates the remaining margin the owner of the proxy vault can use.
    @return freeMargin The remaining amount of margin a user can take.
    @dev The free margin is denominated in the baseCurrency of the proxy vault,
         with an equal number of decimals as the base currency.
    */
    function getFreeMargin()
        public
        returns (uint256 freeMargin)
    {
        uint256 collateralValue = getCollateralValue();
        uint256 usedMargin = getUsedMargin();

        //gas: explicit check is done to prevent underflow
        unchecked {
            freeMargin = collateralValue > usedMargin
                ? collateralValue - usedMargin
                : 0;
        }
    }

    /** 
    @notice Calculates the remaining margin the owner of the proxy vault can use.
    @param vaultValue The total spot value of all the assets in the vault.
    @dev Returns the remaining credit in the baseCurrency in which the proxy vault is initialised.
    @return freeMargin The remaining amount of margin a user can take, 
            returned in the decimals of the base currency.
  */
    function getFreeMargin(uint256 vaultValue)
        public
        returns (uint256 freeMargin)
    {
        uint256 collateralValue = getCollateralValue(vaultValue);
        uint256 usedMargin = getUsedMargin();

        //gas: explicit check is done to prevent underflow
        unchecked {
            freeMargin = collateralValue > usedMargin
                ? collateralValue - usedMargin
                : 0;
        }
    }

    /** 
    @notice Can be called by authorised applications to open or increase a margin position.
    @param baseCurrency The Base-currency in which the margin position is denominated
    @param amount The amount the position is increased.
    @return success Boolean indicating if there is sufficient free margin to increase the margin position
    @dev All values expressed in the base currency of the vault with same number of decimals as the base currency.
    */
    function increaseMarginPosition(address baseCurrency, uint256 amount) public onlyAuthorized returns (bool success) {
        if (baseCurrency != vault.baseCurrency) _setBaseCurrency(baseCurrency);
        success = getFreeMargin() >= amount;
    }

    /** 
    @notice Can be called by authorised applications to close or decrease a margin position.
    @param baseCurrency The Base-currency in which the margin position is denominated.
    @dev All values expressed in the base currency of the vault with same number of decimals as the base currency.
    @return success Boolean indicating if there the margin position is successfully decreased.
    @dev ToDo: Function mainly necessary for integration with untrusted protocols, which is not yet implemnted.
     */
    function decreaseMarginPosition(address baseCurrency, uint256) public view onlyAuthorized returns (bool success) {
        success = baseCurrency == vault.baseCurrency;
    }

    /*///////////////////////////////////////////////////////////////
                          LIQUIDATION LOGIC
    ///////////////////////////////////////////////////////////////*/

    /** 
    @notice Function called to start a vault liquidation.
    @dev Requires an unhealthy vault (value / debt < liqThres).
         Starts the vault auction on the liquidator contract.
         Increases the life of the vault to indicate a liquidation has happened.
         Sets debtInfo todo: needed?
         Transfers ownership of the proxy vault to the liquidator!
    @param liquidationKeeper Addross of the keeper who initiated the liquidation process.
    @param _liquidator Contract Address of the liquidation logic.
    @return success Boolean returning if the liquidation process is successfully started.
  */
    function liquidateVault(address liquidationKeeper, address _liquidator)
        public
        onlyFactory
        returns (bool success)
    {
        //gas: 35 gas cheaper to not take debt into memory
        uint256 totalValue = getVaultValue(vault.baseCurrency);
        uint128 openDebt = getUsedMargin();
        uint256 leftHand;
        uint256 rightHand;

        unchecked {
            //gas: cannot overflow unless totalValue is
            //higher than 1.15 * 10**57 * 10**18 decimals
            leftHand = totalValue * 100;
            //gas: cannot overflow: uint8 * uint128 << uint256
            rightHand = uint256(vault.liqThres) * uint256(openDebt);
        }

        require(leftHand < rightHand, "V_LV: This vault is healthy");

        uint8 baseCurrencyIdentifier = IRegistry(registryAddress).assetToBaseCurrency(vault.baseCurrency);

        require(
            ILiquidator(_liquidator).startAuction(
                address(this),
                life,
                liquidationKeeper,
                owner,
                openDebt,
                vault.liqThres,
                baseCurrencyIdentifier
            ),
            "V_LV: Failed to start auction!"
        );

        //gas: good luck overflowing this
        unchecked {
            ++life;
        }

        return true;
    }

    /*///////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ///////////////////////////////////////////////////////////////*/

    // https://twitter.com/0x_beans/status/1502420621250105346
    /** 
    @notice Returns the sum of all uints in an array.
    @param _data An uint256 array.
    @return sum The combined sum of uints in the array.
  */
    function sumElementsOfList(uint256[] memory _data)
        public
        payable
        returns (uint256 sum)
    {
        //cache
        uint256 len = _data.length;

        for (uint256 i = 0; i < len; ) {
            // optimizooooor
            assembly {
                sum := add(sum, mload(add(add(_data, 0x20), mul(i, 0x20))))
            }

            unchecked {
                ++i;
            }
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    //Function only used for tests
    function getLengths()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            erc20Stored.length,
            erc721Stored.length,
            erc721TokenIds.length,
            erc1155Stored.length
        );
    }

    function returnFive() external pure returns (uint256) {
        return 5;
    }
}