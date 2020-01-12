pragma solidity >=0.4.25 <0.6.0;

import "../openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../openzeppelin-contracts/contracts/token/ERC20/ERC20Burnable.sol";
import "../openzeppelin-contracts/contracts/token/ERC20/ERC20Mintable.sol";
import "../openzeppelin-contracts/contracts/token/ERC20/ERC20Detailed.sol";

contract Token is ERC20, ERC20Detailed, ERC20Mintable, ERC20Burnable {
  constructor () public ERC20Detailed("WJPY", "WJPY", 18) {
  }
}
