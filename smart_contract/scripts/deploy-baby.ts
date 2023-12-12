// @ts-ignore
import { ethers, run, upgrades } from "hardhat"

async function main() {

    const signers = await ethers.getSigners();

    // Library deployment
    const lib = await ethers.getContractFactory("IterableMapping", { signer: signers[0] });
    const libInstance = await lib.deploy();
    await libInstance.waitForDeployment();
    const libAddress = await libInstance.getAddress();

    console.log(`IterableMapping deployed to ${ libAddress }`)

    const WAIT_BLOCK_CONFIRMATIONS = 6

    //Baby Contract
    console.log("Deployment of BABYTOKENDividendTracker")
    const BABYTOKENDividendTracker = await ethers.getContractFactory("BABYTOKENDividendTracker",  { signer: signers[0], libraries: { IterableMapping: libAddress } })
    const babyTokenDividendTracker = await upgrades.deployProxy(BABYTOKENDividendTracker, [],{initializer: false, unsafeAllow: ["external-library-linking"]});
    const dividendAddress = await babyTokenDividendTracker.getAddress();

    await babyTokenDividendTracker.waitForDeployment()
    console.log(`BABYTOKENDividendTracker deployed to ${ dividendAddress }`)

/*
    try {
        console.log(`Verifying contract on Etherscan...`)
        await run(`verify:verify`, {
            address: dividendAddress,
            constructorArguments: [],
        })
    } catch (err: any) {
        console.log(err.message)
    }
*/


    // Specify constructor parameters
    const name = "YourBabyToken";
    const symbol = "BABY";
    const totalSupply = ethers.parseEther("10000000"); // Adjust the total supply as needed
    const rewardAddress = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd";
    const routerAddress = "0xEC3452f87CBa05c5a8c3529b6c961779EB77f257";
    const marketingWalletAddress = "0xcc1C656D25456556335E1a947133A8755556F923";
    const dividendTrackerAddress =  await upgrades.erc1967.getImplementationAddress(dividendAddress);
    console.log(dividendTrackerAddress);
    const feeSettings = [2, 1, 1]; // rewards, liquidity, marketing. Max : 25%
    const minimumTokenBalanceForDividends = ethers.parseEther("100000"); // Adjust as needed
    const serviceFeeReceiver = "0xcc1C656D25456556335E1a947133A8755556F923";
    const serviceFee = ethers.parseEther("0"); // Adjust service fee as needed


    // Deploy the BABYTOKEN contract
    const BABYTOKEN = await ethers.getContractFactory("BABYTOKEN");
    const babyToken = await BABYTOKEN.deploy(
          name,
          symbol,
          totalSupply,
          [rewardAddress, routerAddress, marketingWalletAddress, dividendAddress],
          feeSettings,
          minimumTokenBalanceForDividends,
          serviceFeeReceiver,
          serviceFee);
    await babyToken.waitForDeployment();
    const babyTokenAddress = await babyToken.getAddress();
    console.log("BABYTOKEN deployed to:", babyTokenAddress);
    let claimWait = await babyTokenDividendTracker.claimWait();
    console.log(claimWait);

    await babyToken.getClaimWait();

    /*    try {
            console.log(`Verifying contract on Etherscan...`)
            await run(`verify:verify`, {
                address: babyTokenAddress,
                constructorArguments: [],
            })
        } catch (err: any) {
            console.log(err.message)
        }*/


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
