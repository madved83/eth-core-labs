"use client";

import Image from "next/image";
import Link from "next/link";
import { Address } from "@scaffold-ui/components";
import type { NextPage } from "next";
import { useAccount } from "wagmi";
import { BugAntIcon, MagnifyingGlassIcon } from "@heroicons/react/24/outline";
import { useTargetNetwork } from "~~/hooks/scaffold-eth";

const Home: NextPage = () => {
  const { address: connectedAddress } = useAccount();
  const { targetNetwork } = useTargetNetwork();

  return (
    <>
      <div className="flex items-center flex-col grow pt-10">
        <div className="px-5">
          <h1 className="text-center">
            <span className="block text-2xl mb-2">Welcome to</span>
            <span className="block text-4xl font-bold">Scaffold-ETH 2</span>
            <span className="block text-xl font-bold">(Speedrun Ethereum Challenge: Dice game extension)</span>
          </h1>
          <div className="flex justify-center items-center space-x-2 flex-col">
            <p className="my-2 font-medium">Connected Address:</p>
            <Address address={connectedAddress} chain={targetNetwork} />
          </div>

          <div className="flex items-center flex-col flex-grow pt-10">
            <div className="px-5">
              <h1 className="text-center mb-6">
                <span className="block text-2xl mb-2">Speedrun Ethereum</span>
                <span className="block text-4xl font-bold">Challenge: 🎲 Dice Game</span>
              </h1>
              <div className="flex flex-col items-center justify-center">
                <Image
                  src="/hero.png"
                  width="727"
                  height="231"
                  alt="challenge banner"
                  className="border-4 border-primary"
                />
                <div className="max-w-3xl">
                  <p className="text-lg mt-10">
                    🎰 Randomness is tricky on a public deterministic blockchain. The block hash is an easy to use, but
                    very weak form of randomness. This challenge will give you an example of a contract using the block
                    hash to create random numbers. This randomness is exploitable. Other, stronger forms of randomness
                    include commit/reveal schemes, oracles, or VRF from Chainlink.
                  </p>
                  <p className="text-lg mt-2">
                    🧤 Every time a player rolls the dice, they are required to send .002 Eth. 40 percent of this value
                    is added to the current prize amount while the other 60 percent stays in the contract to fund future
                    prizes. Once a prize is won, the new prize amount is set to 10% of the total balance of the DiceGame
                    contract.
                  </p>
                  <p className="text-lg mt-2">
                    🧨 Your job is to attack the Dice Game contract! You will create a new contract that will predict
                    the randomness ahead of time and only roll the dice when you′re guaranteed to be a winner!
                  </p>
                  <p className="text-lg mt-2">
                    💬 Meet other builders working on this challenge and get help in the{" "}
                    <a href="https://t.me/+3StA0aBSArFjNjUx" target="_blank" rel="noreferrer" className="underline">
                      Telegram Group
                    </a>
                  </p>
                  <p className="text-center text-lg">
                    <a href="https://speedrunethereum.com/" target="_blank" rel="noreferrer" className="underline">
                      SpeedrunEthereum.com
                    </a>
                    !
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div className="grow bg-base-300 w-full mt-16 px-8 py-12">
          <div className="flex justify-center items-center gap-12 flex-col md:flex-row">
            <div className="flex flex-col bg-base-100 border border-base-300 px-10 py-10 text-center items-center max-w-xs">
              <BugAntIcon className="h-8 w-8" />
              <p>
                Tinker with your smart contract using the{" "}
                <Link href="/debug" passHref className="link">
                  Debug Contracts
                </Link>{" "}
                tab.
              </p>
            </div>
            <div className="flex flex-col bg-base-100 border border-base-300 px-10 py-10 text-center items-center max-w-xs">
              <MagnifyingGlassIcon className="h-8 w-8" />
              <p>
                Explore your local transactions with the{" "}
                <Link href="/blockexplorer" passHref className="link">
                  Block Explorer
                </Link>{" "}
                tab.
              </p>
            </div>
          </div>
        </div>
      </div>
    </>
  );
};

export default Home;
