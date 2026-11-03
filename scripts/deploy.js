const { ethers, run, network } = require("hardhat");


async function main() {
    const NUSC_ADDRESS = "0x14E35846856654693161d68Ea92caC952FF1b6f5";


    const POCL_ADDRESS = "0x0B3c574131963F52cD6E525aF57841D36390eEeB";


    const SIGNERS = [
        "0xBa2dF2424b6AC806C16Ebba254fc93b468102274",
        "0x0734B80bd4aecdb2685F5B9ADB998641C65BbAAA",
        "0xBde8fa22D38FA04a6De3dE0acF863709F78193b4"
    ];


    const MMPool = await ethers.getContractFactory("MMPool");


    const mmPool = await MMPool.deploy(
        NUSC_ADDRESS,
        POCL_ADDRESS,
        SIGNERS
    );


    await mmPool.waitForDeployment();


    const address = await mmPool.getAddress();
    const tx = mmPool.deploymentTransaction();


    await tx.wait();


    console.log("\nMMPool deployed successfully!");
    console.log("Network:", network.name);
    console.log("Contract:", address);
    console.log("Transaction:", tx.hash);


    console.log("\nWaiting for explorer indexing...");
    await new Promise(resolve => setTimeout(resolve, 10000));


    try {
        await run("verify:verify", {
            address: address,
            constructorArguments: [
                NUSC_ADDRESS,
                POCL_ADDRESS,
                SIGNERS
            ]
        });


        console.log("MMPool verified successfully!");
    } catch (error) {
        if (/already verified|already been verified/i.test(error.message)) {
            console.log("MMPool is already verified.");
        } else {
            console.log("Verification failed:", error.message);
        }
    }
}


main().catch(console.error);