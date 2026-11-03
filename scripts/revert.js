const { ethers } = require("ethers");
const p = new ethers.JsonRpcProvider("https://tnode2.nowa.finance");

const bnpl = "0xe5527d354bfb52c638a336596a3bb3540430435f";
const user = "0xAab32A92b713eC02e46B50DA54FffF45ED26D12b";

const iface = new ethers.Interface([
  "function openPosition(address,uint256,uint256,uint8,uint256)",
  "error WalletNotRegistered()",
  "error InsufficientCreditline(uint256,uint256)",
  "error VaultUtilizationLimitReached(uint256,uint256)",
  "error InsufficientFunding()",
  "error Unauthorized()",
  "error WalletBlacklisted()",
  "error EnforcedPause()",
  "error InvalidAmount()",
  "error InvalidPrice()",
  "error InvalidOrderType()",
  "error InsufficientMarginForFee(uint256,uint256)",
  "error SafeERC20FailedOperation(address)",
  "error ZeroAddress()",
  "error ZeroAmount()",
  "error ReentrancyGuardReentrantCall()",
  "error ERC20InsufficientAllowance(address,uint256,uint256)",
  "error ERC20InsufficientBalance(address,uint256,uint256)"
]);

(async () => {
  const data = iface.encodeFunctionData("openPosition", [
    "0xD2b388c993e531AA2a470EFad20782Bcb0BB3e5A",
    "100000000000000000",
    "1000000000000000000",
    0,
    0
  ]);
  try {
    await p.call({ from: user, to: bnpl, data });
    console.log("call succeeded (no revert now)");
  } catch (e) {
    console.log("raw revert data:", e.data);
    console.log("message:", e.shortMessage || e.message);
    try { console.log("decoded:", iface.parseError(e.data)); } catch { console.log("selector not in my list"); }
  }
})();