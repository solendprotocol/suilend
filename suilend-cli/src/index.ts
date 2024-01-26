import * as fs from "fs";
import { SuiPriceServiceConnection } from "@pythnetwork/pyth-sui-js";
import { SuiPythClient } from "@pythnetwork/pyth-sui-js";
import {
  Connection,
  Ed25519Keypair,
  JsonRpcProvider,
  MIST_PER_SUI,
  RawSigner,
  SUI_CLOCK_OBJECT_ID,
  TransactionBlock,
  fromB64,
} from "@mysten/sui.js";
import { SuilendClient } from "./client";
import { Obligation } from "./sdk/suilend/obligation/structs";

// replace <YOUR_SUI_ADDRESS> with your actual address, which is in the form 0x123...
const MY_ADDRESS =
  "0x4f3446baf9ca583b920e81924b94883b64addc2a2671963b546aaef77f79a28b";

async function main() {
  // create a new SuiClient object pointing to the network you want to use
  const lendingMarketId =
    "0x3757cd8f3eee3fc6aebb24dd23a56b3bc3643a5aaefda6b7033f63773995a836";
  // const sui_metadata = await client.getCoinMetadata({ coinType: '0x2::sui::SUI' })!;
  const client = new JsonRpcProvider(
    new Connection({ fullnode: "https://fullnode.mainnet.sui.io:443" })
  );
  let suilendClient = await SuilendClient.initialize(lendingMarketId, client);

  const keypair = Ed25519Keypair.fromSecretKey(
    fromB64(process.env.SUI_SECRET_KEY!)
  );
  const signer = new RawSigner(keypair, client);

  // await suilendClient.setObligationOwnerCap("0x99d458e0a85d348f762dbeae771652371571252a6a25b2345a9e16fb2769e4af");

  // console.log(JSON.stringify(
  //   suilendClient.lendingMarket,
  //   (key, value) => (typeof value === "bigint" ? value.toString() : value), // return everything else unchanged
  //   2
  // ));
  // console.log(suilendClient.lendingMarket);

  let txb = new TransactionBlock();

  // let obligationData = await client.getObject({
  //   id: "0xf6add6b93510077ace37a90328a39274e7b7a7a3b539e12547d2f1bde4557b51",
  //   options: { showBcs: true },
  // });

  // if (obligationData.data?.bcs?.dataType !== "moveObject") {
  //   throw new Error("Error: invalid data type");
  // }

  // let obligation = Obligation.fromBcs(
  //   suilendClient.lendingMarket.$typeArg,
  //   fromB64(obligationData.data.bcs.bcsBytes)
  // );

  // let [repay_coins, withdraw_coins] = await suilendClient.liquidate(
  //   txb,
  //   obligation,
  //   "0x2::sui::SUI",
  //   "0x2::sui::SUI",
  //   "0x1bfb480c2a25b6bcc2edd7d9739b842a8d66d361fb01f7f6c1f20df81f0bbbc0"
  // );

  // txb.transferObjects([repay_coins, withdraw_coins], txb.object(MY_ADDRESS));

  // await suilendClient.updateReserveConfig(
  //   MY_ADDRESS,
  //   {
  //     open_ltv_pct: 0,
  //     close_ltv_pct: 0,
  //     borrow_weight_bps: 10_000,
  //     deposit_limit: 1000000000,
  //     borrow_limit: 1000000000,
  //     borrow_fee_bps: 0,
  //     spread_fee_bps: 0,
  //     liquidation_fee_bps: 0,
  //     interest_rate_utils: [0],
  //     interest_rate_aprs: [0]
  //   },
  //   "0x2::sui::SUI",
  //   txb
  // );

  // await suilendClient.createReserve(
  //   txb,
  //   MY_ADDRESS,
  //   {
  //     open_ltv_pct: 100,
  //     close_ltv_pct: 150,
  //     borrow_weight_bps: 100,
  //     deposit_limit: 1000000000,
  //     borrow_limit: 1000000000,
  //     borrow_fee_bps: 0,
  //     spread_fee_bps: 0,
  //     liquidation_fee_bps: 0,
  //     interest_rate_utils: [0],
  //     interest_rate_aprs: [0]
  //   },
  //   "0x2::sui::SUI",
  //   "0x23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744"
  // );

  const [obligationOwnerCap] = suilendClient.createObligation(txb);
  txb.transferObjects([obligationOwnerCap], txb.pure(MY_ADDRESS));

  // suilendClient.deposit(
  //   "0x71407245f9d8dd1373320456f0f079cd53342e342d1121cd442e8da004793871",
  //   "0x2::sui::SUI",
  //   txb
  // );

  // let [coins] = await suilendClient.withdraw(
  //   "0x2::sui::SUI",
  //   1,
  //   txb
  // );

  // txb.setGasBudget(1000000000);
  // let [coins] = await suilendClient.borrow(
  //   "0x2::sui::SUI",
  //   1_000_000_000 / 200,
  //   txb
  // );
  // txb.transferObjects([coins], txb.object(MY_ADDRESS));

  // suilendClient.repay(
  //   "0xf6add6b93510077ace37a90328a39274e7b7a7a3b539e12547d2f1bde4557b51",
  //   "0x2::sui::SUI",
  //   "0x5f7d683e5e0c46b48b13d0b9341b970943ace766c5d219ddea0b0be39da5de59",
  //   txb
  // );

  const res = await signer.signAndExecuteTransactionBlock({
    transactionBlock: txb,
  });
  console.log(res);

  // const { bytes, signature } = await txb.sign({ client: suiClient, signer: keypair })
  // suiClient.executeTransactionBlock({
  //   tra

  // })

  // Convert MIST to Sui
}

main();
