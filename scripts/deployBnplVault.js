
require("dotenv").config();
const hre = require("hardhat");

async function main() {
    const { ethers } = hre;

    const POCL_ADDRESS = "0x0B3c574131963F52cD6E525aF57841D36390eEeB";
    const BNPL_ADDRESS = "0xA40bf55657153aaAdDeEE1f746299c770dca2EB6";

    if (!ethers.isAddress(POCL_ADDRESS) || !ethers.isAddress(BNPL_ADDRESS)) {
        throw new Error("Invalid POCL_ADDRESS or BNPL_ADDRESS in .env");
    }

    const [deployer] = await ethers.getSigners();

    console.log("====================================");
    console.log("Deploying BNPL Vault");
    console.log("====================================");
    console.log("Network:", hre.network.name);
    console.log("Deployer:", await deployer.getAddress());
    console.log("POCL:", POCL_ADDRESS);
    console.log("BNPL:", BNPL_ADDRESS);

    // Deploy contract
    const BnplVault = await ethers.getContractFactory("BnplVault");

    const vault = await BnplVault.deploy(
        POCL_ADDRESS,
        BNPL_ADDRESS
    );

    await vault.waitForDeployment();

    const vaultAddress = await vault.getAddress();

    console.log("\nBNPL Vault deployed:", vaultAddress);

    const deploymentTx = vault.deploymentTransaction();

    if (deploymentTx) {
        console.log("Transaction:", deploymentTx.hash);

        console.log("\nWaiting for 5 confirmations...");
        await deploymentTx.wait(5);
    }

    // Verify contract
    if (
        hre.network.name !== "hardhat" &&
        hre.network.name !== "localhost"
    ) {
        console.log("\nVerifying contract on explorer...");

        try {
            await hre.run("verify:verify", {
                address: vaultAddress,
                constructorArguments: [
                    POCL_ADDRESS,
                    BNPL_ADDRESS
                ]
            });

            console.log("Contract verified successfully!");
        } catch (error) {
            console.log("Verification issue:", error.message);
            console.log("Deployment was successful.");
        }
    } else {
        console.log("Skipping verification on local network.");
    }

    console.log("\n====================================");
    console.log("DEPLOYMENT SUMMARY");
    console.log("====================================");
    console.log("Contract:", vaultAddress);
    console.log("POCL:", await vault.pocl());
    console.log("BNPL:", await vault.bnpl());
    console.log("Owner:", await vault.owner());
    console.log("Token:", await vault.token());
    console.log("====================================");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
