import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { upgrades } from "hardhat";

const {ethers} = require("hardhat");

describe("Token contract", function () {

  async function deployTokenFixture() {

    const signers = await ethers.getSigners();

    const lib = await ethers.getContractFactory("IterableMapping", {signer: signers[0]});
    const libInstance = await lib.deploy();
    await libInstance.waitForDeployment();
    const libAddress = await libInstance.getAddress();

    console.log(`IterableMapping deployed to ${libAddress}`)

    //Baby Contract
    console.log("Deployment of BABYTOKENDividendTracker")
    const BABYTOKENDividendTracker = await ethers.getContractFactory("BABYTOKENDividendTracker", {
      signer: signers[0],
      libraries: {IterableMapping: libAddress}
    })
    const babyTokenDividendTracker = await upgrades.deployProxy(BABYTOKENDividendTracker, [], {
      initializer: false,
      unsafeAllow: ["external-library-linking"]
    });
    const dividendAddress = await babyTokenDividendTracker.getAddress();

    await babyTokenDividendTracker.waitForDeployment()
    console.log(`BABYTOKENDividendTracker deployed to ${dividendAddress}`)

    // Specify constructor parameters
    const name = "YourBabyToken";
    const symbol = "BABY";
    const totalSupply = ethers.parseEther("10"); // Adjust the total supply as needed
    const rewardAddress = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd"; //Joe
    const routerAddress = "0xEC3452f87CBa05c5a8c3529b6c961779EB77f257"; //Joe router Uniswap v2
    const marketingWalletAddress = "0xcc1C656D25456556335E1a947133A8755556F923";
    const dividendTrackerAddress = dividendAddress;
    const feeSettings = [2, 1, 1]; // rewards, liquidity, marketing. Max : 25%
    const minimumTokenBalanceForDividends = ethers.parseEther("1"); // Adjust as needed
    const serviceFeeReceiver = "0xcc1C656D25456556335E1a947133A8755556F923";
    const serviceFee = ethers.parseEther("0"); // Adjust service fee as needed

    // Deploy the BABYTOKEN contract
    const BABYTOKEN = await ethers.getContractFactory("BABYTOKEN");
    const babyToken = await BABYTOKEN.deploy(
      name,
      symbol,
      totalSupply,
      [rewardAddress, routerAddress, marketingWalletAddress, dividendTrackerAddress],
      feeSettings,
      minimumTokenBalanceForDividends,
      serviceFeeReceiver,
      serviceFee,
    );
    await babyToken.waitForDeployment();
    const babyTokenAddress = await babyToken.getAddress();
    console.log("BABYTOKEN deployed to:", babyTokenAddress);

    const [owner, addr1] = await ethers.getSigners()

    return {babyToken, owner, addr1, babyTokenDividendTracker}
  }

  describe("MintManager", () => {
    it("Test tx", async function () {
      const {
        babyToken,
        owner,
        addr1,
        babyTokenDividendTracker
      } = await loadFixture(deployTokenFixture);

      // Now you can access the values using array indexing
      //console.log(ret);
      await babyToken.withdrawableDividendOf(addr1);
      //await babyToken.transfer(addr1, 5);
    });
  });
});
