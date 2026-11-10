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
            <span className="block text-xl font-bold">(Speedrun Ethereum Oracles extension)</span>
          </h1>
          <div className="flex justify-center items-center space-x-2 flex-col">
            <p className="my-2 font-medium">Connected Address:</p>
            <Address address={connectedAddress} chain={targetNetwork} />
          </div>

          <div className="flex items-center flex-col flex-grow mt-4">
            <div className="px-5 w-[90%]">
              <h1 className="text-center mb-6">
                <span className="block text-4xl font-bold">Oracles</span>
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
                  <p className="text-center text-lg mt-8">
                    🔮 Build your own decentralized oracle network! In this challenge, you&apos;ll explore different
                    oracle architectures and implementations. You&apos;ll dive deep into concepts like staking
                    mechanisms, consensus algorithms, slashing conditions, and dispute resolution – all crucial
                    components of a robust oracle system.
                  </p>
                  <p className="text-center text-lg">
                    🌟 The final deliverable is a comprehensive understanding of oracle architectures through hands-on
                    implementation. You&apos;ll explore two existing oracle systems (Whitelist and Staking) to
                    understand their mechanics, then implement the Optimistic Oracle from scratch. Deploy your
                    optimistic oracle to a testnet and demonstrate how it handles assertions, proposals, disputes, and
                    settlements. Then build and upload your app to a public web server. Submit the url on{" "}
                    <a href="https://speedrunethereum.com/" target="_blank" rel="noreferrer" className="underline">
                      SpeedrunEthereum.com
                    </a>{" "}
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
