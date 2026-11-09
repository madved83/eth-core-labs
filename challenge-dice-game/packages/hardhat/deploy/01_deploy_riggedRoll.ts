import { artifacts, deployScript } from "../rocketh/deploy.js";

export default deployScript(
  async env => {
    const { deployer } = env.namedAccounts;
    const diceGame = env.get("DiceGame");

    await env.deploy("RiggedRoll", {
      account: deployer,
      artifact: artifacts.RiggedRoll,
      args: [diceGame.address],
    });
  },
  { tags: ["RiggedRoll"], dependencies: ["DiceGame"] },
);
