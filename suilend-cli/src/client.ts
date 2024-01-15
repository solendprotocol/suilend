import * as fs from "fs";
import { SuiPriceServiceConnection } from "@pythnetwork/pyth-sui-js";
import { SuiPythClient } from "@pythnetwork/pyth-sui-js";
import {
  Connection,
  Ed25519Keypair,
  JsonRpcProvider,
  RawSigner,
  SUI_CLOCK_OBJECT_ID,
  TransactionBlock,
  fromB64,
} from "@mysten/sui.js";
import { load, ObligationOwnerCap, ObligationType, Reserve, LendingMarket } from "./types";
import { BcsType } from "@mysten/bcs";

const WORMHOLE_STATE_ID =
  "0xaeab97f96cf9877fee2883315d459552b2b921edc16d7ceac6eab944dd88919c";
const PYTH_STATE_ID =
  "0x1f9310238ee9298fb703c3419030b35b22bb1cc37113e3bb5007c99aec79e5b8";

const SUILEND_CONTRACT_ADDRESS =
  "0xd4b22ab40c4e3ef2f90cef9432bde18bea223d06644a111921383821344cb340";

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

export class SuilendClient {
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
    ownerId: string,
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

    let objs = await this.client.getOwnedObjects({
      owner: ownerId,
      filter: {
        StructType: `${SUILEND_CONTRACT_ADDRESS}::lending_market::LendingMarketOwnerCap<${this.lendingMarketType}>`,
      },
    });
    console.log(objs);

    if (objs.data.length == 0) {
      throw new Error("Error: no lending market owner cap found");
    }

    let ownerCapId = objs.data[0].data!.objectId;

    txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::add_reserve`,
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
      typeArguments: [this.lendingMarketType, coinType],
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
    obligationOwnerCapId: string,
    obligation: ObligationType,
    coinType: string,
    amount: number,
    txb: TransactionBlock
  ) {
    if (this.lendingMarketType == null) {
      throw new Error("Error: client not initialized");
    }

    let priceIds = new Set<string>();
    obligation.deposits

    // gotta refresh everything first

    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::withdraw`,
      arguments: [
        // lending market
        txb.object(this.lendingMarketId),
        // obligation owner cap
        txb.object(obligationOwnerCapId),
        // clock
        txb.object(SUI_CLOCK_OBJECT_ID),
        // ctokens
        txb.pure(amount),
      ],
      typeArguments: [this.lendingMarketType, coinType],
    });
  }

  borrow(
    obligationOwnerCapId: string,
    coinType: string,
    amount: number,
    txb: TransactionBlock
  ) {
    if (this.lendingMarketType == null) {
      throw new Error("Error: client not initialized");
    }

    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::borrow`,
      arguments: [
        // lending market
        txb.object(this.lendingMarketId),
        // obligation owner cap
        txb.object(obligationOwnerCapId),
        // clock
        txb.object(SUI_CLOCK_OBJECT_ID),
        // ctokens
        txb.pure(amount),
      ],
      typeArguments: [this.lendingMarketType, coinType],
    });
  }

  repay(
    obligationId: string,
    coinType: string,
    amount: number,
    txb: TransactionBlock
  ) {
    if (this.lendingMarketType == null) {
      throw new Error("Error: client not initialized");
    }

    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::borrow`,
      arguments: [
        // lending market
        txb.object(this.lendingMarketId),
        // obligation
        txb.object(obligationId),
        // clock
        txb.object(SUI_CLOCK_OBJECT_ID),
        // ctokens
        txb.pure(amount),
      ],
      typeArguments: [this.lendingMarketType, coinType],
    });
  }
}
