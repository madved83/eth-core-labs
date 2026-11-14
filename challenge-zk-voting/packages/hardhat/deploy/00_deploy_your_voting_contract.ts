import { artifacts, deployScript } from "../rocketh/deploy.js";
export default deployScript(async ({ deploy, namedAccounts }) => {
  const { deployer } = namedAccounts;
  const v = await deploy("HonkVerifier", { account: deployer, artifact: artifacts.HonkVerifier, args: [] });
  const p = await deploy("PoseidonT3", { account: deployer, artifact: artifacts.PoseidonT3, args: [] });
  const l = await deploy("LeanIMT", { account: deployer, artifact: artifacts.LeanIMT, args: [] }, { libraries: { PoseidonT3: p.address } });
  await deploy("Voting", { account: deployer, artifact: artifacts.Voting, args: [deployer, v.address, "Should we build zk apps?"] }, { libraries: { LeanIMT: l.address } });
}, { tags: ["YourVotingContract"] });
