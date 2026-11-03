
const { ethers, run } = require("hardhat");

async function main() {
    // Contract addresses
    const NUSC_ADDRESS = "0x14E35846856654693161d68Ea92caC952FF1b6f5";
    const STATS_ADDRESS = "0x14E35846856654693161d68Ea92caC952FF1b6f5";
    const RESERVE_ADDRESS = "0x9Bb1F6371BF23b289dD1A196A8069Be192783bAd";
    const MMPOOL_ADDRESS = "0x82623AEe6fA9C465eC3C9AcD45d92d2cfA18616E";
    const BNPL_VAULT_ADDRESS = "0x4E35E54eADF95bFf45Fa94CB2bcDD4421434db3A";
    const ORACLE_ADDRESS = "0x1093F3CaFdd2636d3b192EA5E288191aacBB42d8";

    // Signer addresses
    const SIGNERS = [
        "0xBa2dF2424b6AC806C16Ebba254fc93b468102274",
        "0x0734B80bd4aecdb2685F5B9ADB998641C65BbAAA",
        "0xBde8fa22D38FA04a6De3dE0acF863709F78193b4",
        "0xC38FfC88dA71dF441778D23Ced1Cac7179321a4A"
    ];

    // Oracle configuration
    const MAX_ORACLE_AGE = 3600;
    const PRICE_SCALE = ethers.parseUnits("1", 18);
    const ORACLE_RETURNS_NOWA_PER_NUSC = false;

    const constructorArgs = [
        NUSC_ADDRESS,
        STATS_ADDRESS,
        RESERVE_ADDRESS,
        MMPOOL_ADDRESS,
        BNPL_VAULT_ADDRESS,
        ORACLE_ADDRESS,
        SIGNERS,
        MAX_ORACLE_AGE,
        PRICE_SCALE,
        ORACLE_RETURNS_NOWA_PER_NUSC
    ];

    // Deploy POCL
    const POCL = await ethers.getContractFactory("POCL");
    const pocl = await POCL.deploy(...constructorArgs);

    await pocl.waitForDeployment();

    const address = await pocl.getAddress();

    console.log("--------------------------------");
    console.log("POCL DEPLOYED SUCCESSFULLY");
    console.log("--------------------------------");
    console.log("POCL Address:", address);
    console.log("MM Pool:", await pocl.mmPool());
    console.log("Threshold:", (await pocl.threshold()).toString());
    console.log("--------------------------------");

    // Wait for deployment transaction to be indexed
    const deploymentTx = pocl.deploymentTransaction();
    if (deploymentTx) {
        await deploymentTx.wait(2);
    }

    // Verify POCL
    console.log("Starting POCL verification...");

    try {
        await run("verify:verify", {
            address: address,
            constructorArguments: constructorArgs
        });

        console.log("POCL VERIFIED SUCCESSFULLY");
    } catch (error) {
        console.error("Verification failed:", error.message);
        console.log("You can retry verification manually later.");
    }

    console.log("--------------------------------");
    console.log("Deployment and verification process completed.");
    console.log("--------------------------------");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
