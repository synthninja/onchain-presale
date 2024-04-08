// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { IUniswapV2Router02 } from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Factory } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/finance/VestingWallet.sol";
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
    uint _totalContributions;
    uint _finalPresalerTokens;
    uint _finalLiquidityTokens;
    uint _finalLiquidityFunding;
    uint64 private _startTimestamp;
    
    uint64 constant _PRESALE_VESTING_PERIOD = 1 hours;
    uint constant _TOTAL_SUPPLY = 1e9 * 1e18; // 1 MILLION TOKENS
    uint constant _LIQUIDITY_PCT = 40;
    uint constant _PRESALERS_PCT = 50;
    uint constant _TEAM_PCT = 5;
    uint constant _TREASURY_PCT = 5;

    // uni v2 on base addresses.
    address constant _uniswapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address constant _uniswapFactory = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;

    
    constructor(address token, address payable TEAM_ADDRESS, address payable TREASURY_ADDRESS, address payable LIQUIDITY_ADDRESS) Ownable(msg.sender) {
      _TEAM_ADDRESS = TEAM_ADDRESS;
      _TREASURY_ADDRESS = TREASURY_ADDRESS;
      _LIQUIDITY_ADDRESS = LIQUIDITY_ADDRESS;
      _token = token;
      // start immediately.
      _presaleActive = true;
    }
    
    receive() external payable {
      require(_presaleActive, "Not active");
      _presaleContributions[msg.sender] += msg.value;  
      _totalContributions += msg.value;
      console.log("Contributed", msg.sender, msg.value);
    }

    function contributionOf(address account) public view returns (uint256) {
        return _presaleContributions[account];
    }

    function walletOf(address account) public view returns (VestingWallet) {
        return _presaleWallets[account];
    }

    function totalContributions() public view returns (uint256) {
      return _totalContributions;
    }

    function manualFinishPresale() public onlyOwner {
      distributeLiquidity();
    }

    function distributeLiquidity() internal {
      require(_presaleActive);
      _presaleActive = false;

      uint constributions = _totalContributions;
      uint tokens = _TOTAL_SUPPLY;


      // rounding errors can slip in here, depending on the values used for *_PCT and _TOTAL_SUPPLY. 
      // however, they shouldn't be an issue, as the remainders will just end up going into liquidity. 
      console.log("Presale ending");
      console.log("Funding balance", _totalContributions, address(this).balance);

      uint presalers_tokens = (tokens * _PRESALERS_PCT) / 100;
      uint treasury_tokens = (tokens * _TREASURY_PCT) / 100;
      uint team_tokens = (tokens * _TEAM_PCT) / 100;
      uint treasury_contributions = (constributions * _TREASURY_PCT) / 100;
      uint team_contributions = (constributions * _TEAM_PCT) / 100;
      
      uint liquidity_tokens = tokens - presalers_tokens - team_tokens - treasury_tokens;
      uint liquidity_contributions = constributions - team_contributions - treasury_contributions;

      _finalPresalerTokens = presalers_tokens;
      _finalLiquidityTokens = liquidity_tokens;
      _finalLiquidityFunding = liquidity_contributions;

      _startTimestamp = uint64(block.timestamp);
      
      sendViaCall(_TREASURY_ADDRESS, treasury_contributions);
      sendViaCall(_TEAM_ADDRESS, team_contributions);

      console.log("Sent to team", team_contributions, _TEAM_ADDRESS);
      console.log("Sent to treasury", treasury_contributions, _TREASURY_ADDRESS);
      console.log("Funding balance remaining (prev, now)", _totalContributions, address(this).balance, liquidity_contributions);
      
      MyToken(_token).mint(_TEAM_ADDRESS, team_tokens);
      MyToken(_token).mint(_TREASURY_ADDRESS, treasury_tokens);
      MyToken(_token).mint(address(this), presalers_tokens);
      MyToken(_token).mint(address(this), liquidity_tokens);
      
      console.log("Tokens balance:", IERC20(_token).balanceOf(address(this)));
      
      addLiquidityToUni();
    }

    function addLiquidityToUni() internal {
      address _weth = IUniswapV2Router02(_uniswapRouter).WETH();
      address _pair = IUniswapV2Factory(_uniswapFactory).getPair(address(this), _weth);

      if (_pair == address(0)) {
        _pair = IUniswapV2Factory(_uniswapFactory).createPair(address(this), _weth);
      }
      _pair = IUniswapV2Factory(_uniswapFactory).getPair(address(this), _weth);
        
      // add liquidity
      IUniswapV2Router02 router = IUniswapV2Router02(_uniswapRouter);
      IERC20 token = ERC20(_token);
      
      token.approve(_uniswapRouter, type(uint256).max);
      
      console.log("Final add of liquidity stage, funding amount:", _finalLiquidityFunding, address(this).balance);
      console.log("Final add of liquidity stage, token amount:", _finalLiquidityTokens);
      
      _finalLiquidityFunding = address(this).balance; /// SHOULD ALWAYS MATCH EXACTLY. 
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

    function claimPresalerTokens() public {
      require(!_presaleActive, "Cannot claim now");
      uint contribution_as_funds = _presaleContributions[_msgSender()]; 
      // must have made some contribution.
      require(contribution_as_funds > 0, "Nothing to claim");

      // zero out balance 
      _presaleContributions[_msgSender()] = 0;
      
      // calc pct of tokens the user should get. 
      // we use a huge multiplier to minizime rounding errors, but there still will be 
      // very tiny rounding errors. since the rounding is always floored, this will just
      // mean people get a miniscule fraction less (0.0000000000000001 etc) and contract
      // will end up with a miniscule amount of tokens left over. 
      uint contribution_as_pct = (contribution_as_funds * 1e18) / _totalContributions;
      uint tokens = (_finalPresalerTokens * contribution_as_pct) / 1e18;

      console.log("Contribution was, (fund, pct_bps)", contribution_as_funds, contribution_as_pct / 1e14);
      
      // Create vesting wallet for user and send the tokens.
      VestingWallet userWallet = new VestingWallet(_msgSender(), _startTimestamp, _PRESALE_VESTING_PERIOD); 
      _presaleWallets[_msgSender()] = userWallet;
      ERC20(_token).transfer(_msgSender(), tokens);

      console.log("Sent to wallet:", tokens, address(userWallet));
      console.log("Remaining token balance", IERC20(_token).balanceOf(address(this)));
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
