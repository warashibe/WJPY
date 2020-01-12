pragma solidity ^0.5.0;

import "./Token.sol";
import "../openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../contracts-vyper/contracts/UniswapExchangeInterface.sol";
import "../chainlink/evm/v0.5/contracts/ChainlinkClient.sol";

contract WJPY is ChainlinkClient {
  
  Token public stable_token;
  uint public last_update;
  uint256 public rate;
  address public deposit_token;
  uint public max_rate;
  uint public total_volume;
  address public exchange_address;
  address public link_address;
  address public _oracle;
  bytes32 public _jobId;
  uint256 public _payment;
  
  struct Thread
  {
    uint next;
    uint amount;
  }
  
  mapping(uint => Thread) public txs;
  
  constructor(address token, address exchange, address link, address _link, address oracle_address, bytes32 jobId,uint256 payment) public {
    _oracle = oracle_address;
    _jobId = jobId;
    _payment = payment;
    deposit_token = token;
    exchange_address = exchange;
    link_address = link;
    stable_token = new Token();
    if (_link == address(0)) {
      setPublicChainlinkToken();
    } else {
      setChainlinkToken(_link);
    }
  }
  
  function getTokenAddress() public view returns(address _address) {
    _address = address(stable_token);
  }
  
  function getThreads() public view returns(uint[] memory rates, uint[] memory amounts) {
    uint len = 0;
    if(max_rate != 0){
      len += 1;
      uint current_rate = max_rate;
      while(txs[current_rate].next != 0){
	len += 1;
	current_rate = txs[current_rate].next;
      }
      current_rate = max_rate;
      rates = new uint[](len);
      amounts = new uint[](len);
      amounts[0] = txs[current_rate].amount;
      rates[0] = current_rate;
      len = 0;
      while(txs[current_rate].next != 0 && len > 9){
	len += 1;
	current_rate = txs[current_rate].next;
	rates[len] = current_rate;
	amounts[len] = txs[current_rate].amount;
      }
    }
  }
  
  function getTotalSupply() public view returns(uint _supply) {
    _supply = stable_token.totalSupply();
  }
  
  function getDepositToken(uint amount) public view returns(uint deposit) {
    if(max_rate != 0){
      uint current_rate = max_rate;
      while(amount > 0){
	uint full = (txs[current_rate].amount * current_rate) / 10 ** 18;
	if(full > amount){
	  uint partial_amount = amount * 10 ** 18 / current_rate;
	  deposit += partial_amount;
	  amount = 0;
	}else{
	  amount -= full;
	  deposit += txs[current_rate].amount;
	}
      }
    }
  }

  function burn(uint amount) public returns(bool success) {
    require(max_rate != 0, "max_rate cannot be 0");
    require(IERC20(stable_token).allowance(msg.sender, address(this)) >= amount, "allowance must be greater or equal to amount");
    stable_token.transferFrom(msg.sender, address(this), amount);
    stable_token.burn(amount);
    total_volume += amount;
    uint deposit = 0;
      
    uint current_rate = max_rate;
    while(amount > 0){
      uint full = (txs[current_rate].amount * current_rate) / 10 ** 18;
      if(full > amount){
	uint partial_amount = amount * 10 ** 18 / current_rate;
	txs[current_rate].amount -= partial_amount;
	deposit += partial_amount;
	amount = 0;
      }else{
	amount -= full;
	deposit += txs[current_rate].amount;
	txs[current_rate].amount = 0;
	max_rate = txs[current_rate].next;
      }
      if(txs[current_rate].next != 0){
	current_rate = txs[current_rate].next;
      }
    }
    if(deposit != 0){
      IERC20(deposit_token).approve(address(this), deposit);
      IERC20(deposit_token).transferFrom(address(this), msg.sender,deposit);
    }
    success = true;
  }
  
  function mint(uint amount) public returns(bool success) {
    require(rate != 0, "rate cannot be 0");
    require(IERC20(deposit_token).allowance(msg.sender, address(this)) >= amount, "allowance must be greater or equal to amount");
    uint fee = amount / 100;
    uint rest = amount - fee;
    IERC20(deposit_token).transferFrom(msg.sender, address(this), amount);
    _mint(rest);
    success = _swap(fee);
  }
  
  function _mint(uint rest) private returns(bool success) {
    if(txs[rate].amount == 0 && max_rate != 0){
      uint current_rate = max_rate;
      uint prev_rate = 0;
      while(current_rate >= rate){
	prev_rate = current_rate;
	if(txs[current_rate].next != 0){
	  current_rate = txs[current_rate].next;
	}else{
	  current_rate = 0;
	}
      }
      if(current_rate != rate){
	if(prev_rate == 0){
	  txs[rate].next = max_rate;
	  max_rate = rate;
	}else{
	  txs[prev_rate].next = rate;
	  txs[rate].next = current_rate;
	}
      }
    }
    if(max_rate < rate){
      max_rate = rate;
    }
    txs[rate].amount += rest;
    total_volume += (rest * rate) / 10 ** 18;
    stable_token.mint(address(msg.sender), (rest * rate) / 10 ** 18);
    success = true;
  }
  
  function _swap(uint fee) private returns(bool success) {
    uint deadline = now + 1000 * 60 * 60;
    IERC20(deposit_token).approve(exchange_address, fee);
    UniswapExchangeInterface(exchange_address).tokenToTokenSwapInput(fee, 1, 1, deadline, link_address);
    success = true;
  }
  
  function updateRate() public returns (bytes32 requestId) {
    uint link_balance = IERC20(link_address).balanceOf(address(this));
    require(link_balance >= _payment, "Contract must have enough LINK for oracle");
    uint reward = link_balance - _payment;
    if(reward != 0){
      IERC20(link_address).approve(address(this), reward);
      IERC20(link_address).transferFrom(address(this), msg.sender, reward);
    }
    Chainlink.Request memory req = buildChainlinkRequest(_jobId, address(this), this.fulfill.selector);
    req.add("sym", "DAI");
    req.add("convert", "JPY");
    string[] memory path = new string[](5);
    path[0] = "data";
    path[1] = "DAI";
    path[2] = "quote";
    path[3] = "JPY";
    path[4] = "price";
    req.addStringArray("copyPath", path);
    req.addInt("times", 10**18);
    requestId = sendChainlinkRequestTo(_oracle, req, _payment);
  }
  
  function fulfill(bytes32 _requestId, uint256 _data) public recordChainlinkFulfillment(_requestId) {
    last_update = block.timestamp;
    rate = _data;
  }
}
