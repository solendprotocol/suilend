import {
  CoinBalance,
  RawSigner,
  JsonRpcProvider,
  Connection,
} from "@mysten/sui.js";
import { MIST_PER_SUI } from "@mysten/sui.js";
import { TransactionBlock } from "@mysten/sui.js";
import { Ed25519Keypair } from "@mysten/sui.js";
import { fromB64 } from "@mysten/sui.js";
import * as fs from "fs";
import { SuiPriceServiceConnection } from "@pythnetwork/pyth-sui-js";
import { SuiPythClient } from "@pythnetwork/pyth-sui-js";

// replace <YOUR_SUI_ADDRESS> with your actual address, which is in the form 0x123...
const MY_ADDRESS =
  "0x4f3446baf9ca583b920e81924b94883b64addc2a2671963b546aaef77f79a28b";
const SUILEND_CONTRACT_ADDRESS =
  "0xd4b22ab40c4e3ef2f90cef9432bde18bea223d06644a111921383821344cb340";
const WORMHOLE_STATE_ID =
  "0xaeab97f96cf9877fee2883315d459552b2b921edc16d7ceac6eab944dd88919c";
const PYTH_STATE_ID =
  "0x1f9310238ee9298fb703c3419030b35b22bb1cc37113e3bb5007c99aec79e5b8";

interface ReserveConfigArgs {
  open_ltv_pct: number;
  close_ltv_pct: number;
  borrow_weight_bps: number;
  deposit_limit: number;
  borrow_limit: number;
  borrow_fee_bps: number;
  spread_fee_bps: number;
  liquidation_fee_bps: number;
  interest_rate_utils: number[];
  interest_rate_aprs: number[];
}

class SuilendClient {
  lendingMarketId: string;
  lendingMarketType: string | null;
  client: JsonRpcProvider;
  pythClient: SuiPythClient;
  pythConnection: SuiPriceServiceConnection;

  constructor(lendingMarketId: string, client: JsonRpcProvider) {
    this.lendingMarketId = lendingMarketId;
    this.lendingMarketType = null;
    this.client = client;
    this.pythClient = new SuiPythClient(
      client,
      PYTH_STATE_ID,
      WORMHOLE_STATE_ID
    );
    this.pythConnection = new SuiPriceServiceConnection(
      "https://hermes.pyth.network"
    );
  }

  async initialize() {
    let lendingMarket = await this.client.getObject({
      id: this.lendingMarketId,
      options: { showContent: true },
    });
    if (lendingMarket.data?.content?.dataType === "moveObject") {
      const outerType = lendingMarket.data?.content?.type;
      this.lendingMarketType = outerType.substring(
        outerType.indexOf("<") + 1,
        outerType.indexOf(">")
      );
      console.log(`Lending market type: ${this.lendingMarketType}`);
    } else {
      throw new Error("Error: lending market type not found");
    }
  }

  async createReserve(
    txb: TransactionBlock,
    configArgs: ReserveConfigArgs,
    coinType: string,
    pythPriceId: string
  ) {
    if (this.lendingMarketType == null) {
      throw new Error("Error: client not initialized");
    }

    const priceUpdateData = await this.pythConnection.getPriceFeedsUpdateData([
      pythPriceId,
    ]);
    const priceInfoObjectIds = await this.pythClient.updatePriceFeeds(
      txb,
      priceUpdateData,
      [pythPriceId]
    );
    console.log(priceInfoObjectIds);

    // console.log(sui_metadata);

    const sui_metadata = await this.client.getCoinMetadata({
      coinType: coinType,
    });
    if (sui_metadata == null) {
      throw new Error("Error: coin metadata not found");
    }

    let [config] = txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::reserve::create_reserve_config`,
      arguments: [
        // open ltv pct
        txb.pure(configArgs.open_ltv_pct),
        // close ltv pct
        txb.pure(configArgs.close_ltv_pct),
        // borrow weight bps
        txb.pure(configArgs.borrow_weight_bps),
        // deposit limit
        txb.pure(configArgs.deposit_limit),
        // borrow limit
        txb.pure(configArgs.borrow_limit),
        // borrow fee bps
        txb.pure(configArgs.borrow_fee_bps),
        // spread fee bps
        txb.pure(configArgs.spread_fee_bps),
        // liquidation fee bps
        txb.pure(configArgs.liquidation_fee_bps),
        // interest rate utils
        txb.pure(configArgs.interest_rate_utils),
        // interest rate aprs
        txb.pure(configArgs.interest_rate_aprs),
      ],
    });
    /*
        public fun add_reserve<P, T>(
          _: &LendingMarketOwnerCap<P>, 
          lending_market: &mut LendingMarket<P>, 
          // scaled by 10^18
          price: u256,
          config: ReserveConfig,
          coin_metadata: &CoinMetadata<T>,
          clock: &Clock,
          _ctx: &mut TxContext
      ) {
    */
    let objs = await this.client.getOwnedObjects({
      owner: MY_ADDRESS,
      filter: {
        StructType: `${SUILEND_CONTRACT_ADDRESS}::lending_market::LendingMarketOwnerCap<${this.lendingMarketType}>`,
      }
    });
    console.log(objs);

    if (objs.data.length == 0) { 
      throw new Error("Error: no lending market owner cap found");
    }

    let ownerCapId = objs.data[0].data!.objectId;

    txb.moveCall({
      target:
        `${SUILEND_CONTRACT_ADDRESS}::lending_market::add_reserve`,
      arguments: [
        // owner cap
        txb.object(ownerCapId),
        // lending market
        txb.object(this.lendingMarketId),
        // price
        txb.object(priceInfoObjectIds[0]),
        // config
        config,
        // coin metadata
        txb.object(sui_metadata.id!),
        // clock
        txb.object("0x6"),
      ],
      typeArguments: [
        this.lendingMarketType,
        coinType
      ],
    });
  }

  createObligation(txb: TransactionBlock) {
    if (this.lendingMarketType == null) {
      throw new Error("Error: client not initialized");
    }

    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::create_obligation`,
      arguments: [txb.object(this.lendingMarketId)],
      typeArguments: [this.lendingMarketType],
    });
  }

  deposit(
    coinsId: string,
    coinType: string,
    obligationOwnerCapId: string,
    txb: TransactionBlock
  ) {
    if (this.lendingMarketType == null) {
      throw new Error("Error: client not initialized");
    }

    const [ctokens] = txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::deposit_liquidity_and_mint_ctokens`,
      arguments: [
        // lending market
        txb.object(this.lendingMarketId),
        // clock
        txb.object("0x6"),
        txb.object(coinsId),
      ],
      typeArguments: [this.lendingMarketType, coinType],
    });

    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::deposit_ctokens_into_obligation`,
      arguments: [
        // lending market
        txb.object(this.lendingMarketId),
        // obligation owner cap
        txb.object(obligationOwnerCapId),
        // ctokens
        ctokens,
      ],
      typeArguments: [this.lendingMarketType, coinType],
    });
  }

  withdraw(
    coinType: string,
    amount: number,
    obligationOwnerCapId: string,
    txb: TransactionBlock
  ) {
    if (this.lendingMarketType == null) {
      throw new Error("Error: client not initialized");
    }
  }
}

async function main() {
  // create a new SuiClient object pointing to the network you want to use
  const lendingMarketId = "0xa6d1603c50fd4fac1ae544744930b37f3c3467c6b10e60bc0db5673d764a1647";
  // const sui_metadata = await client.getCoinMetadata({ coinType: '0x2::sui::SUI' })!;
  const client = new JsonRpcProvider(
    new Connection({ fullnode: "https://fullnode.mainnet.sui.io:443" })
  );
  const suilendClient = new SuilendClient(lendingMarketId, client);
  await suilendClient.initialize();

  const obligationOwnerCap = "0xc0201eb13d4507cfb078d2f5bde94b9f02b1720a3883a8b8a7f0544029d8985d"

  const keypair = Ed25519Keypair.fromSecretKey(
    fromB64(process.env.SUI_SECRET_KEY!)
  );
  const signer = new RawSigner(keypair, client);

  let txb = new TransactionBlock();

  // await suilendClient.createReserve(
  //   txb,
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

  // const [obligationOwnerCap] = suilendClient.createObligation(txb);
  // txb.transferObjects([obligationOwnerCap], txb.pure(MY_ADDRESS));

  // suilendClient.deposit(
  //   "0x2e7aebd6459194bd4ab72b0d82981a6371369166f4256ab4c11cfd08e8ab52e2",
  //   "0x2::sui::SUI",
  //   obligationOwnerCap,
  //   txb
  // );

  const res = await signer.signAndExecuteTransactionBlock({
    transactionBlock: txb,
    options: {
      showBalanceChanges: true,
      showEffects: true,
      showInput: true,
      showObjectChanges: true,
    },
  });
  console.log(res);

  // const { bytes, signature } = await txb.sign({ client: suiClient, signer: keypair })
  // suiClient.executeTransactionBlock({
  //   tra

  // })

  // Convert MIST to Sui
}

main();
