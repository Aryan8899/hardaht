// Run: npx hardhat run scripts/botDeposit.js --network <your-network>
//
// .env needs only:
//   BOT_KEY=0x...    (private key of the bot address, must already be added as bot)
//   STAKER=0x...     (optional, wallet whose pendingReward you want to see)

require("dotenv").config();
const { ethers } = require("hardhat");

const POOL = "0xfFDd377F7F1E8cE78e990541A52B7F332819e379";
const NUSC = "0x14E35846856654693161d68Ea92caC952FF1b6f5";

// change profit amount here (18 decimals)
const PROFIT = ethers.parseUnits("100", 18);

const POOL_ABI = [
  "function isBot(address) view returns (bool)",
  "function depositProfit(uint256)",
  "function pendingReward(address) view returns (uint256)",
  "function totalRewardsLiability() view returns (uint256)",
];

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function allowance(address,address) view returns (uint256)",
];

async function main() {
  const bot = new ethers.Wallet(process.env.BOT_KEY, ethers.provider);
  const pool = new ethers.Contract(POOL, POOL_ABI, bot);
  const nusc = new ethers.Contract(NUSC, ERC20_ABI, bot);

  console.log("Bot:", bot.address);

  if (!(await pool.isBot(bot.address))) {
    throw new Error("This address is not a bot yet. Add it via proposeAddBot + approve first.");
  }

  const bal = await nusc.balanceOf(bot.address);
  console.log("Bot NUSC balance:", ethers.formatUnits(bal, 18));
  if (bal < PROFIT) throw new Error("Bot has not enough NUSC.");

  if ((await nusc.allowance(bot.address, POOL)) < PROFIT) {
    console.log("Approving...");
    await (await nusc.approve(POOL, PROFIT)).wait();
  }

  console.log("Depositing profit...");
  const tx = await pool.depositProfit(PROFIT);
  await tx.wait();
  console.log("Done:", tx.hash);

  console.log("totalRewardsLiability:", ethers.formatUnits(await pool.totalRewardsLiability(), 18));
  if (process.env.STAKER) {
    console.log("pendingReward(staker):", ethers.formatUnits(await pool.pendingReward(process.env.STAKER), 18));
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});