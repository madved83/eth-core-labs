import { artifacts, deployScript } from "../rocketh/deploy.js";
export default deployScript(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;
    await deploy(
      "Voting",
      {
        account: deployer,
        artifact: artifacts.Voting,
        args: [deployer, "0x0b5b3a0f7d7bdf364f08b452e9f6e38313c75d9d", "Should we build zk apps?"],
      },
      { libraries: { LeanIMT: "0x090016d840fa250b50ab1ab425e86817fddce858" } },
    );
  },
  { tags: ["YourVotingContract"] },
);
