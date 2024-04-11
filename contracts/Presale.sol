// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/finance/VestingWallet.sol";
import { IUniswapV2Router02 } from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import './Token.sol';

import "hardhat/console.sol";

contract Presale is Context, Ownable  {
    using SafeERC20 for IERC20;

    address immutable public _token;
    address payable immutable _TEAM_ADDRESS;
    address payable immutable _TREASURY_ADDRESS;
    address payable immutable _LIQUIDITY_ADDRESS;

    bool public _presaleActive;
    mapping(address => uint256) private _presaleContributions;
    mapping(address => VestingWallet) private _presaleWallets;
    uint public _totalContributions;
    
    uint64 private _startTimestamp;
    
    // These are calculated in constructor.
    uint immutable _finalPresalerTokens;
    uint immutable _finalLiquidityTokens;
    uint immutable _finalTeamTokens;
    uint immutable _finalTreasuryTokens;

    uint64 constant _PRESALE_VESTING_PERIOD = 1 hours;
    uint constant _TOTAL_SUPPLY = 1e6 * 1e18; // 1 MILLION TOKENS
    uint constant _LIQUIDITY_PCT = 40;
    uint constant _PRESALERS_PCT = 50;
    uint constant _TEAM_PCT = 5;
    uint constant _TREASURY_PCT = 5;

    address internal _uniswapRouter; //0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;  // uni v2 on base addresses.

    constructor(
        address token, 
        address payable teamAddress, 
        address payable treasuryAddress, 
        address payable liquidityAddress,
        address uniswapRouter
    ) 
        Ownable(msg.sender) 
    {
        _token = token;
        _TEAM_ADDRESS = teamAddress;
        _TREASURY_ADDRESS = treasuryAddress;
        _LIQUIDITY_ADDRESS = liquidityAddress;
        _uniswapRouter = uniswapRouter;
        // start immediately.
        _presaleActive = true;
        // calc the things. 
        _finalPresalerTokens = (_TOTAL_SUPPLY * _PRESALERS_PCT / 100);
        _finalTreasuryTokens = (_TOTAL_SUPPLY * _TREASURY_PCT) / 100;
        _finalTeamTokens = (_TOTAL_SUPPLY * _TEAM_PCT) / 100;
        _finalLiquidityTokens = _TOTAL_SUPPLY - _finalPresalerTokens - _finalTeamTokens - _finalTreasuryTokens;
    }
    
    receive() external payable {
        require(_presaleActive, "Not active");
        _presaleContributions[msg.sender] += msg.value;  
        _totalContributions += msg.value;
        console.log("Contributed", msg.sender, msg.value);
    }

    function claimPresalerTokens() external {
        require(!_presaleActive, "Cannot claim now");
        require(_presaleContributions[_msgSender()] > 0, "Nothing to claim");
        
        uint tokens = contributionOfAsTokens(_msgSender());

        console.log("Contribution was, (fund, pct_bps)", _presaleContributions[_msgSender()], contributionOfAsPct(_msgSender()));
        
        // zero out balance so they cant claim again. 
        _presaleContributions[_msgSender()] = 0;
        
        // Create vesting wallet for user and send the tokens.
        VestingWallet userWallet = new VestingWallet(_msgSender(), _startTimestamp, _PRESALE_VESTING_PERIOD); 
        _presaleWallets[_msgSender()] = userWallet;
        ERC20(_token).transfer(address(userWallet), tokens);

        console.log("Sent to wallet:", tokens, address(userWallet));
        console.log("Remaining token balance", IERC20(_token).balanceOf(address(this)));
    }

    function manualFinishPresale() external onlyOwner {
        distributeLiquidity();
    }

    function contributionOf(address account) external view returns (uint256) {
        return _presaleContributions[account];
    }

    // Ratio we will add to the liquidity at, can be used to calc listing price.
    function currentLiquidityRatio() external view returns (uint256, uint256) {
        return (currentLiquidityFunding(), _finalLiquidityTokens);
    }

    function walletOf(address account) external view returns (VestingWallet) {
        return _presaleWallets[account];
    }

    function totalContributions() external view returns (uint256) {
        return _totalContributions;
    }

    // Returns the percent of the supply the contributions will get, as value from 0-1e18 representing 
    // 0-100%. 
    // The reason for using the very high multipler is to keep rounding errors to a minimum.
    // When using it to calc the value, we just divide by 1e18, instead of 100 (1e3).
    function contributionOfAsPct(address account) public view returns (uint256) {
        return ((_presaleContributions[account] * 1e18) / _totalContributions);
    }

    // Returns the amount of tokens the user will receive.
    // This is based of the _CURRENT_ value of _totalContributions
    function contributionOfAsTokens(address account) public view returns (uint256) {
        return contributionOfAsPct(account) * _finalPresalerTokens / 1e18;
    }

    // Returns the amount of liquidity currently on course to 
    // add, which can be used to find the price. 
    function currentLiquidityFunding() public view returns (uint256) {
        uint treasury_contributions = (_totalContributions * _TREASURY_PCT) / 100;
        uint team_contributions = (_totalContributions * _TEAM_PCT) / 100;
        uint liquidity_contributions = _totalContributions - team_contributions - treasury_contributions;
        return liquidity_contributions;
    }

    // Ratio presalers are getting tokens at, can be used to calc presale price.
    function currentPresaleRatio() public view returns (uint256, uint256) {
        return (_totalContributions, _finalPresalerTokens);
    }

    function distributeLiquidity() internal {
        require(_presaleActive);
        _presaleActive = false;

        // rounding errors can slip in here, depending on the values used for *_PCT and _TOTAL_SUPPLY. 
        // however, they shouldn't be an issue, as the remainders will just end up going into liquidity. 
        console.log("Presale ending");
        console.log("Funding balance", _totalContributions, address(this).balance);
        
        uint treasury_contributions = (_totalContributions * _TREASURY_PCT) / 100;
        uint team_contributions = (_totalContributions * _TEAM_PCT) / 100;
        uint liquidity_contributions = _totalContributions - team_contributions - treasury_contributions;

        _startTimestamp = uint64(block.timestamp);
        
        sendViaCall(_TREASURY_ADDRESS, treasury_contributions);
        sendViaCall(_TEAM_ADDRESS, team_contributions);

        console.log("Sent to team", team_contributions, _TEAM_ADDRESS);
        console.log("Sent to treasury", treasury_contributions, _TREASURY_ADDRESS);
        console.log("Funding balance remaining (prev, now)", _totalContributions, address(this).balance, liquidity_contributions);
        
        MyToken(_token).mint(_TEAM_ADDRESS, _finalTeamTokens);
        MyToken(_token).mint(_TREASURY_ADDRESS, _finalTreasuryTokens);
        MyToken(_token).mint(address(this), _finalPresalerTokens);
        MyToken(_token).mint(address(this), _finalLiquidityTokens);
        
        console.log("Tokens balance:", IERC20(_token).balanceOf(address(this)));
        
        addLiquidityToUni();
    }

    function addLiquidityToUni() internal {    
        // add liquidity
        IUniswapV2Router02 router = IUniswapV2Router02(_uniswapRouter);
        IERC20 token = ERC20(_token);
        
        token.approve(_uniswapRouter, type(uint256).max);
        uint _finalLiquidityFunding = currentLiquidityFunding();
        console.log("Final add of liquidity stage, funding amount:", _finalLiquidityFunding, address(this).balance);
        console.log("Final add of liquidity stage, token amount:", _finalLiquidityTokens);
        
        // add liquidity
        (uint256 tokenAmount, uint256 ethAmount, uint256 liquidity) = 
        router.addLiquidityETH{value: _finalLiquidityFunding} (
            address(token), // token
            _finalLiquidityTokens, // token desired
            _finalLiquidityTokens, // token min
            _finalLiquidityFunding, // eth min
            address(_LIQUIDITY_ADDRESS), // lp to
            block.timestamp + 1 days // deadline
        );
        console.log("Added liquidity", tokenAmount, ethAmount, liquidity);
    }

    // copied from https://solidity-by-example.org/sending-ether/ as the current recommened way. It
    // does have some caveats to avoid reentrancy bugs/exploits if we are ever sending ETH to a user controled
    // address. (we are not in this case)
    function sendViaCall(address payable _to, uint _amt) internal {
        // Call returns a boolean value indicating success or failure.
        // This is the current recommended method to use.
        (bool sent, bytes memory data) = _to.call{value: _amt}("");
        require(sent, "Failed to send Ether");
    }
}
