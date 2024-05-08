// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// oz imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// oz upgradeable imports
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// local imports
import { IRevenueStream } from "./interfaces/IRevenueStream.sol";
import { IRevenueStreamETH } from "./interfaces/IRevenueStreamETH.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { RevenueStreamETH } from "./RevenueStreamETH.sol";

/**
 * @title RevenueDistributor
 * @author @chasebrownn
 * @notice This contract is the receiver of any veRWA revenue share. Any revenue tokens must be added to this contract via
 *         `addRevenueToken`. This contract will collect all revenue until `convertRewardToken` or `convertRewardTokenBatch`.
 *         These methods will convert any revenue tokens to ETH then distribute that ETH to the `revStreamETH` contract where
 *         a checkpoint will be hit and the assets will become claimable to RWA stakeholders.
 */
contract RevenueDistributor is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // ---------------
    // State Variables
    // ---------------

    /// @dev Stores all ERC-20 tokens used for revenue streams.
    address[] public revenueTokens;
    /// @dev If true, address key is allowed to distribute revenue from this contract.
    mapping(address => bool) public canDistribute;
    /// @dev Mapping used to fetch whether a `revenueToken` address is a supported revenue token.
    mapping(address revenueToken => bool) public isRevToken;
    /// @dev Mapping used to fetch the RevenueStream contract address for a revenueToken (if set).
    mapping(address revenueToken => address revenueStream) public revenueStreamForToken;
    /// @dev Stores a supported selector, given the `target` address. Prevents misuse.
    mapping(address target => mapping(bytes4 selector => bool approved)) public fetchSelector;
    /// @dev RevenueStream contract address where ETH will be distributed to if an ETH revenue stream exists.
    RevenueStreamETH public revStreamETH;
    /// @dev Destination contract address for veRWA NFT contract on REAL.
    address public veRwaNFT;
    /// @dev Stores local WETH address.
    IWETH public WETH;

    
    // ---------
    // Modifiers
    // ---------

    /**
     * @notice Modifier for verifying msg.sender is allowed to distribute revenue.
     */
    modifier isDistributor {
        require(canDistribute[msg.sender] || msg.sender == owner(), "RevenueDistributor: Not authorized");
        _;
    }


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when revenue is distributed (as ETH) from this contract to a RevenueStreamETH contract.
     * @param revStreamETH Address of revenue stream contract that received revenue.
     * @param amount Amount of ETH deposited into RevenueStreamETH.
     */
    event ETHRevenueDistributed(address indexed revStreamETH, uint256 amount);

    /**
     * @notice This event is emitted when revenue is distributed from this contract to a RevenueStream contract.
     * @param token Address of revenue token that was distributed.
     * @param revStream Address of revenue stream contract that received revenue.
     * @param amount Amount of revenue token deposited into RevenueStream.
     */
    event ERC20RevenueDistributed(address indexed token, address indexed revStream, uint256 amount);

    /**
     * @notice This event is emitted when an ERC-20 revenue token is converted to ETH prior to distribution.
     * @param token Address of rervenue token being converted.
     * @param swapAmount Amount of `token` used for conversion.
     * @param amountOut Amoun of ETH received post-conversion.
     */
    event RevTokenConverted(address indexed token, uint256 swapAmount, uint256 amountOut);
    
    /**
     * @notice This event is emitted when a new ERC-20 revenue token is added as a supported revenue token.
     * @param token Address of new rervenue token being added.
     */
    event RevTokenAdded(address indexed token);

    /**
     * @notice This event is emitted when an existing ERC-20 revenue token is removed from supported revenue tokens.
     * @param token Address of rervenue token being removed.
     */
    event RevTokenRemoved(address indexed token);

    /**
     * @notice This event is emitted when address(this) receives ETH.
     * @dev Needed for off-chain tracking of ETH input.
     * @param sender Sender of ETH.
     * @param amount Amount of ETH received.
     */
    event ETHReceived(address sender, uint256 amount);

    /**
     * @notice This event is emitted when a new `canDistribute` is set.
     * @param newDistributor New value stored in `canDistribute`.
     * @param canDistribute If true, `newDistributor` can distribute revenue.
     */
    event DistributorSet(address indexed newDistributor, bool canDistribute);

    /**
     * @notice This event is emitted when a new `WETH` is set.
     * @param newWETHAddress New value stored in `WETH`.
     */
    event WETHAddressSet(address indexed newWETHAddress);

    /**
     * @notice This event is emitted when a new `revStreamETH` is set.
     * @param newRevenueStreamETH New value stored in `revStreamETH`.
     */
    event RevenueStreamETHSet(address indexed newRevenueStreamETH);

    // TODO: Natspec
    event RevenueStreamForTokenSet(address indexed token, address indexed newRevenueStream);


    // -----------
    // Constructor
    // -----------

    constructor() {
        _disableInitializers();
    }


    // -----------
    // Initializer
    // -----------

    /**
     * @notice Initializes RevenueDistributor
     * @param _admin Address to be assigned as default admin.
     * @param _veRwa Address of VotingEscrowRWA contract.
     * @param _weth Address of WETH.
     */
    function initialize(
        address _admin,
        address _veRwa,
        address _weth
    ) external initializer {
        require(_admin != address(0));
        require(_veRwa != address(0));

        __Ownable_init(_admin);
        __UUPSUpgradeable_init();

        veRwaNFT = _veRwa;
        WETH = IWETH(_weth);
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method allows address(this) to receive ETH.
     */
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    /**
     * @notice Converts a specific revenue token to ETH and distribute to revenue stream.
     * @dev To avoid misuse, the selector used in `_data` must be approved via fetchSelector[`_target`][bytes4('_data'[0:4])].
     * @param _token Token to convert to ETH before distributing.
     * @param _amount Amount to convert for `_token`.
     * @param _target Target address for conversion.
     * @param _data Call data for conversion.
     * @return _amountOut Amount ETH received and distributed from conversion.
     */
    function convertRewardToken(
        address _token,
        uint256 _amount,
        address _target,
        bytes calldata _data
    ) external isDistributor returns (uint256 _amountOut) {
        require(isRevToken[_token], "invalid revenue token");
        require(revenueStreamForToken[_token] == address(0), "Token not meant to be swapped");
        require(_amount != 0, "amount cannot be 0");

        uint256 _before = IERC20(_token).balanceOf(address(this));
        require(_before >= _amount, "Insufficient balance");

        _amountOut = _convertToken(_token, _amount, _target, _data);
        require(_amountOut != 0, "insufficient output amount");

        uint256 _after = IERC20(_token).balanceOf(address(this));
        require(_after >= _before - _amount, "invalid input amount");
        
        _distributeETH();
    }

    /**
     * @notice Converts a batch of revenue tokens to ETH and distribute to revenue stream.
     * @dev To avoid misuse, the selector used in `_data` must be approved via fetchSelector[`_target`][bytes4('_data'[0:4])].
     * @param _tokens Tokens to convert to ETH before distributing.
     * @param _amounts Amounts to convert for each token.
     * @param _targets Target address for conversion(s).
     * @param _data Call data for conversion(s).
     * @return _amountsOut Amount ETH received and distributed for each conversion.
     */
    function convertRewardTokenBatch(
        address[] memory _tokens,
        uint256[] memory _amounts,
        address[] memory _targets,
        bytes[] calldata _data
    ) external isDistributor returns (uint256[] memory _amountsOut) {
        uint256 len = _tokens.length;
        require(len == _amounts.length,"Invalid length");
        require(_amounts.length == _targets.length,"Invalid length");
        require(_targets.length == _data.length,"Invalid length");
        _amountsOut = new uint256[](len);

        uint256 totalDeposit;
        for (uint256 i; i < len;) {

            address token = _tokens[i];
            uint256 amount = _amounts[i];

            require(isRevToken[token], "invalid revenue token");
            require(revenueStreamForToken[token] == address(0), "Token not meant to be swapped");
            require(amount != 0, "amount cannot be 0");

            uint256 _before = IERC20(token).balanceOf(address(this));
            require(_before >= amount, "Insufficient balance");

            uint256 converted = _convertToken(token, amount, _targets[i], _data[i]);
            require(converted != 0, "ETH received cant be 0");

            _amountsOut[i] = converted;
            totalDeposit += converted;

            unchecked {
                ++i;
            }
        }

        require(totalDeposit != 0, "insufficient output amount");
        _distributeETH();
    }

    // TODO: NatSpec & Test
    function distributeToken(address _token, uint256 _amount) external isDistributor {
        require(isRevToken[_token], "invalid revenue token");
        require(revenueStreamForToken[_token] != address(0), "No RevenueStream assigned to token");
        require(_amount != 0, "amount cannot be 0");

        _distributeERC20(_token, _amount);
    }

    // TODO: NatSpec & Test
    function distributeTokenBatch(address[] memory _tokens, uint256[] memory _amounts) external isDistributor {
        require(_tokens.length == _amounts.length, "Lengths do not match");
        for (uint256 i; i < _tokens.length;) {

            require(isRevToken[_tokens[i]], "invalid revenue token");
            require(revenueStreamForToken[_tokens[i]] != address(0), "No RevenueStream assigned to token");
            require(_amounts[i] != 0, "amount cannot be 0");

            _distributeERC20(_tokens[i], _amounts[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Permisioned method for distributing ETH to a designated RevenueStreamETH contract.
     */
    function distributeETH() external isDistributor {
        _distributeETH();
    }

    /**
     * @notice Permissiond method to assign whether a `_distributor` address can distribute revenue from this contract.
     * @param _distributor Address being granted (or revoked) permission to distribute revenue.
     * @param _canDistribute If true, `_distributor` can distribute revenue.
     */
    function setDistributor(address _distributor, bool _canDistribute) external onlyOwner {
        require(_distributor != address(0), "Cannot be address(0)");
        emit DistributorSet(_distributor, _canDistribute);
        canDistribute[_distributor] = _canDistribute;
    }

    /**
     * @notice Permissioned method
     */
    function setWeth(address _weth) external onlyOwner {
        require(_weth != address(0), "Cannot be address(0)");
        emit WETHAddressSet(_weth);
        WETH = IWETH(_weth);
    }

    /**
     * @notice This method is used to assign a new address to the global var `revStreamETH`.
     * @dev Should only be used in the event we're updating the distribution destination address.
     * @param _newRevStream Contract address of new RevenueStreamETH contract.
     */
    function updateRevenueStream(address payable _newRevStream) external onlyOwner {
        require(_newRevStream != address(0), "Cannot be address(0)");
        emit RevenueStreamETHSet(_newRevStream);
        revStreamETH = RevenueStreamETH(_newRevStream);
    }

    /**
     * @notice This method is used to add a new supported revenue token.
     * @param _revToken New ERC-20 revenue token to be added.
     */
    function addRevenueToken(address _revToken) external onlyOwner {
        require(!isRevToken[_revToken], "already added");

        isRevToken[_revToken] = true;
        revenueTokens.push(_revToken);

        emit RevTokenAdded(_revToken);
    }

    // TODO: NatSpec
    function setRevenueStreamForToken(address _revToken, address _revStream) external onlyOwner {
        require(isRevToken[_revToken], "token not added");
        require(revenueStreamForToken[_revToken] != _revStream, "revStream already set");

        revenueStreamForToken[_revToken] = _revStream;

        emit RevenueStreamForTokenSet(_revToken, _revStream);
    }

    /**
     * @notice This method is used to remove an existing revenue token.
     * @param _revToken ERC-20 revenue token to be removed.
     */
    function removeRevenueToken(address _revToken) external onlyOwner {
        require(isRevToken[_revToken], "token not added");

        isRevToken[_revToken] = false;
        uint256 len = revenueTokens.length;

        for (uint256 i; i < len;) {
            if (revenueTokens[i] == _revToken) {
                revenueTokens[i] = revenueTokens[len - 1];
                revenueTokens.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }

        emit RevTokenRemoved(_revToken);
    }

    /**
     * @notice This method sets the verified function call for a `_target`.
     * @dev If a selector is not assigned, we will not be able to call `_target` to convert revenue tokens.
     * @param _target Target contract address where `_selector` resides.
     * @param _selector Function selector for desired callable method for conversion.
     *
     * @dev Usage:
     *    If we wanted to call `swapExactTokensForETH` on the local UniswapV2Router to swap revenue tokens for ETH.
     *    We would call this method with the following arguments:
     *        _target == address(uniswapV2Router)
     *        _selector == bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)"))
     */
    function setSelectorForTarget(address _target, bytes4 _selector, bool isApproved) external onlyOwner {
        fetchSelector[_target][_selector] = isApproved;
    }

    /**
     * @notice This is a helper method for Gelato Functions.
     * @dev Gelato will fetch this method to see if it can execute an autonomous payload on behalf of this contract.
     * @return canExec If true, Gelato will execute `execPayload`.
     * @return execPayload Payload to execute.
     */
    function checker() external pure returns (bool canExec, bytes memory execPayload) {
        canExec = true;
        execPayload = abi.encodeWithSelector(this.convertRewardTokenBatch.selector);
    }

    /**
     * @notice View method for fetching the `revenueTokens` array.
     */
    function getRevenueTokensArray() external view returns (address[] memory) {
        return revenueTokens;
    }


    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Method for depositing ETH to a designated RevenueStreamETH contract.
     */
    function _distributeETH() internal {
        uint256 amount = address(this).balance;
        revStreamETH.depositETH{value: amount}();
        emit ETHRevenueDistributed(address(revStreamETH), amount);
    }

    /**
     * @notice Method for depositing ERC20 revenue tokens to a designated RevenueStream contract.
     */
    function _distributeERC20(address _token, uint256 _amount) internal {
        address revStream = revenueStreamForToken[_token];
        IERC20(_token).approve(revStream, _amount);
        IRevenueStream(revStream).deposit(_amount);
        emit ERC20RevenueDistributed(_token, revStream, _amount);
    }

    /**
     * @notice Converts a specific token to ETH.
     * @dev This function is used to convert any token to ETH. It contains the check
     * to verify that the target address and selector are correct to avoid exploits.
     * @param _tokenIn Token to convert.
     * @param _amount Amount to convert.
     * @param _target Target address for conversion.
     * @param _data Call data for conversion.
     * @return _amountOut Amount ETH received.
     */
    function _convertToken(
        address _tokenIn,
        uint256 _amount,
        address _target,
        bytes calldata _data
    ) internal returns (uint256 _amountOut) {
        uint256 preBalWETH = WETH.balanceOf(address(this));
        // check if this is a pre-approved contract for swapping/converting
        require(fetchSelector[_target][bytes4(_data[0:4])], "invalid selector");

        IERC20(_tokenIn).forceApprove(_target, _amount);
        (bool _success, ) = _target.call(_data);
        require(_success, "low swap level call failed");
        IERC20(_tokenIn).forceApprove(_target, 0);

        uint256 postBalWETH = WETH.balanceOf(address(this));
        _amountOut = postBalWETH - preBalWETH;

        require(_amountOut != 0, "no WETH received");

        WETH.withdraw(postBalWETH);

        emit RevTokenConverted(_tokenIn, _amount, _amountOut);
    }

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}