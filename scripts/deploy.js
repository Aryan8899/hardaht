const { ethers, run } = require("hardhat");
const fs = require("fs");
require("dotenv").config();

async function main() {
    const TokenWhitelist    = "0xdd5A27d782D1001974FF43F1376e996ed103181C";
    const BNPL_Subscription = "0x72eA911ef311c9001eB6656AcEEfF05f69cAAF98";
    const stakeContract     = "0x21e1515d7B750fFd37B084B32dc3933593C0FbE9";
    const op                = "0x0EB81A8Da2f15A84A954c7b7525046AC9EB75cBc";
    const signerrole        = "0xBa2dF2424b6AC806C16Ebba254fc93b468102274";

    console.log("=".repeat(50));
    console.log("Deploying Vault...");
    console.log("=".repeat(50));

    const Vault = await ethers.getContractFactory("Bnpl");
    const vault = await Vault.deploy(
        BNPL_Subscription,
        TokenWhitelist,
        stakeContract,
        op,
        signerrole
    );

    await vault.waitForDeployment();

    const contractAddress = await vault.getAddress();

    console.log("✅ Vault deployed at:", contractAddress);

    let deployment = {};
    if (fs.existsSync("deployment.json")) {
        deployment = JSON.parse(fs.readFileSync("deployment.json"));
    }

    deployment.vault = contractAddress;

    fs.writeFileSync(
        "deployment.json",
        JSON.stringify(deployment, null, 2)
    );

    console.log("✅ Saved to deployment.json");

    // Wait for explorer to index contract
    console.log("\nWaiting 30 seconds before verification...");
    await new Promise((resolve) => setTimeout(resolve, 30000));

    try {
        await run("verify:verify", {
            address: contractAddress,
            constructorArguments: [
                BNPL_Subscription,
                TokenWhitelist,
                stakeContract,
                op,
                signerrole,
            ],
        });

        console.log("✅ Contract verified successfully!");
    } catch (error) {
        if (error.message.toLowerCase().includes("already verified")) {
            console.log("✅ Contract is already verified.");
        } else {
            console.error("❌ Verification failed:");
            console.error(error);
        }
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});