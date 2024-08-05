// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.6/contracts/access/Ownable.sol";
//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.6/contracts/access/AccessControl.sol";
//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.6/contracts/token/ERC20/IERC20.sol";
// Import OpenZeppelin contracts
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interface for UniswapV2Router02
interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

// Interface for UniswapV2Factory
interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address);
}

// Token contract implementing IERC20, Ownable, and AccessControl
contract TestToken is IERC20, Ownable, AccessControl {
    // Events
    event Reflect(uint256 amountReflected, uint256 newTotalReflectionBalance);

    // Constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 ether;

    // State variables
    IUniswapV2Router02 public uniswapV2Router;
    address public immutable uniswapV2Pair;

    uint8 public reflectionFee = 2;
    uint8 public burnFee = 2;
    uint8 public totalFee = 4;

    string private _name = "TestToken";
    string private _symbol = "TEST";

    uint256 private _totalSupply = INITIAL_SUPPLY;
    uint256 public maxTxAmount = (INITIAL_SUPPLY * 2) / 100;

    mapping(address => uint256) private _reflectionOwned;
    uint256 private _totalReflectionBalance = INITIAL_SUPPLY;

    mapping(address => mapping(address => uint256)) private _allowances;

    bool public limitsEnabled = true;
    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public isExcludedFromTxLimit;
    mapping(address => bool) public blacklists;

    bool private _burning;

    // Modifiers
    modifier burningNow() {
        _burning = true;
        _;
        _burning = false;
    }

    // Constructor
    constructor(address router, address adminAddress) {
        uniswapV2Router = IUniswapV2Router02(router);
        address uniswapPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = uniswapPair;

        _allowances[address(this)][address(uniswapV2Router)] = type(uint256).max;
        _allowances[address(this)][msg.sender] = type(uint256).max;

        isExcludedFromTxLimit[address(this)] = true;
        isExcludedFromTxLimit[address(uniswapV2Router)] = true;
        isExcludedFromTxLimit[uniswapPair] = true;
        isExcludedFromTxLimit[msg.sender] = true;
        isExcludedFromTxLimit[adminAddress] = true;
        isFeeExempt[msg.sender] = true;
        isFeeExempt[adminAddress] = true;

        _reflectionOwned[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);

        // Set up roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, adminAddress);
    }

    receive() external payable {}

    // Role management
    function addAdmin(address account) external onlyOwner {
        grantRole(ADMIN_ROLE, account);
    }

    function removeAdmin(address account) external onlyOwner {
        revokeRole(ADMIN_ROLE, account);
    }

    // ERC20 functions
    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            require(_allowances[sender][msg.sender] >= amount, "ERC20: insufficient allowance");
            _allowances[sender][msg.sender] -= amount;
        }
        return _transferFrom(sender, recipient, amount);
    }

    // View functions
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _tokensFromReflection(_reflectionOwned[account]);
    }

    function allowance(address holder, address spender) external view override returns (uint256) {
        return _allowances[holder][spender];
    }

    function circulatingSupply() public view returns (uint256) {
        return _totalSupply - balanceOf(DEAD);
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyRole(ADMIN_ROLE) {
        isFeeExempt[holder] = exempt;
    }

    function setIsExcludedFromTxLimit(address holder, bool exempt) external onlyRole(ADMIN_ROLE) {
        isExcludedFromTxLimit[holder] = exempt;
    }

    function setMaxTxBasisPoint(uint256 basisPoint) external onlyRole(ADMIN_ROLE) {
        maxTxAmount = (_totalSupply * basisPoint) / 10000;
    }

    function setLimitsEnabled(bool enabled) external onlyRole(ADMIN_ROLE) {
        limitsEnabled = enabled;
    }

    function blacklist(address addr, bool isBlacklisted) external onlyRole(ADMIN_ROLE) {
        blacklists[addr] = isBlacklisted;
    }

    // Private functions
    function _transferFrom(address sender, address recipient, uint256 amount) private returns (bool) {
        require(!blacklists[sender] && !blacklists[recipient], "Address is blacklisted");

        if (_burning) {
            return _basicTransfer(sender, recipient, amount);
        }

        if (limitsEnabled && !isExcludedFromTxLimit[sender] && !isExcludedFromTxLimit[recipient]) {
            require(amount <= maxTxAmount, "Transfer amount exceeds the maxTxAmount");
        }

        uint256 reflectionAmount = _tokensToReflection(amount);
        require(_reflectionOwned[sender] >= reflectionAmount, "Insufficient balance");
        _reflectionOwned[sender] -= reflectionAmount;

        uint256 reflectionReceived = _shouldTakeFee(sender, recipient)
            ? _takeFee(sender, reflectionAmount)
            : reflectionAmount;
        _reflectionOwned[recipient] += reflectionReceived;

        if (_shouldBurn()) {
            _burnTokens(amount * burnFee / 100);
        }

        emit Transfer(sender, recipient, _tokensFromReflection(reflectionReceived));
        return true;
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) private returns (bool) {
        uint256 reflectionAmount = _tokensToReflection(amount);
        require(_reflectionOwned[sender] >= reflectionAmount, "Insufficient balance");
        _reflectionOwned[sender] -= reflectionAmount;
        _reflectionOwned[recipient] += reflectionAmount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function _takeFee(address sender, uint256 reflectionAmount) private returns (uint256) {
        uint256 reflectionFeeAmount = (reflectionAmount * totalFee) / 100;

        uint256 reflectionReflected = (reflectionFeeAmount * reflectionFee) / totalFee;
        _totalReflectionBalance -= reflectionReflected;

        uint256 reflectionToContract = reflectionFeeAmount - reflectionReflected;
        if (reflectionToContract > 0) {
            _reflectionOwned[address(this)] += reflectionToContract;
            emit Transfer(sender, address(this), _tokensFromReflection(reflectionToContract));
        }

        emit Reflect(reflectionReflected, _totalReflectionBalance);
        return reflectionAmount - reflectionFeeAmount;
    }

    function _shouldBurn() private view returns (bool) {
        return !_burning && balanceOf(address(this)) > 0;
    }

    function _burnTokens(uint256 amountToBurn) private burningNow {
        if (amountToBurn <= balanceOf(address(this))) {
            _transferFrom(address(this), DEAD, amountToBurn);
        }
    }

    function _shouldTakeFee(address sender, address recipient) private view returns (bool) {
        return !isFeeExempt[sender] && !isFeeExempt[recipient];
    }

    function _tokensToReflection(uint256 tokens) private view returns (uint256) {
        return (tokens * _totalReflectionBalance) / _totalSupply;
    }

    function _tokensFromReflection(uint256 reflection) private view returns (uint256) {
        return (reflection * _totalSupply) / _totalReflectionBalance;
    }
}
