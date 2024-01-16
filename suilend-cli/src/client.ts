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
import { BcsType, toHEX } from "@mysten/bcs";
import {
  LendingMarket,
  ObligationOwnerCap,
} from "./sdk/suilend/lending-market/structs";
import { Obligation } from "./sdk/suilend/obligation/structs";

const WORMHOLE_STATE_ID =
  "0xaeab97f96cf9877fee2883315d459552b2b921edc16d7ceac6eab944dd88919c";
const PYTH_STATE_ID =
  "0x1f9310238ee9298fb703c3419030b35b22bb1cc37113e3bb5007c99aec79e5b8";

const SUILEND_CONTRACT_ADDRESS =
  "0xeb3ea608693a9b4a3585491fa121508bad34048d4675ef7bb17ac81bee9039b4";

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
  lendingMarket: LendingMarket;

  client: JsonRpcProvider;
  pythClient: SuiPythClient;
  pythConnection: SuiPriceServiceConnection;

  obligation: Obligation | null;
  obligationOwnerCap: ObligationOwnerCap | null;

  private constructor(
    lendingMarket: LendingMarket,
    lendingMarketId: string,
    client: JsonRpcProvider
  ) {
    this.lendingMarket = lendingMarket;
    this.client = client;
    this.pythClient = new SuiPythClient(
      client,
      PYTH_STATE_ID,
      WORMHOLE_STATE_ID
    );
    this.pythConnection = new SuiPriceServiceConnection(
      "https://hermes.pyth.network"
    );

    this.obligation = null;
    this.obligationOwnerCap = null;
  }

  static async initialize(lendingMarketId: string, client: JsonRpcProvider) {
    let lendingMarketData = await client.getObject({
      id: lendingMarketId,
      options: { showBcs: true },
    });
    console.log(lendingMarketData);

    if (lendingMarketData.data?.bcs?.dataType !== "moveObject") {
      throw new Error("Error: invalid data type");
    }
    if (lendingMarketData.data?.bcs?.type == null) {
      throw new Error("Error: lending market type not found");
    }

    const outerType = lendingMarketData.data?.bcs?.type;
    let lendingMarketType = outerType.substring(
      outerType.indexOf("<") + 1,
      outerType.indexOf(">")
    );
    console.log(`Lending market type: ${lendingMarketType}`);

    let lendingMarket = LendingMarket.fromBcs(
      lendingMarketType,
      fromB64(lendingMarketData.data.bcs.bcsBytes)
    );

    return new SuilendClient(lendingMarket, lendingMarketId, client);
  }

  async createReserve(
    txb: TransactionBlock,
    ownerId: string,
    configArgs: ReserveConfigArgs,
    coinType: string,
    pythPriceId: string
  ) {
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
        StructType: `${SUILEND_CONTRACT_ADDRESS}::lending_market::LendingMarketOwnerCap<${this.lendingMarket.$typeArg}>`,
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
        txb.object(this.lendingMarket.id),
        // price
        txb.object(priceInfoObjectIds[0]),
        // config
        config,
        // coin metadata
        txb.object(sui_metadata.id!),
        // clock
        txb.object("0x6"),
      ],
      typeArguments: [this.lendingMarket.$typeArg, coinType],
    });
  }

  createObligation(txb: TransactionBlock) {
    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::create_obligation`,
      arguments: [txb.object(this.lendingMarket.id)],
      typeArguments: [this.lendingMarket.$typeArg],
    });
  }

  deposit(coinsId: string, coinType: string, txb: TransactionBlock) {
    if (this.obligationOwnerCap == null || this.obligation == null) {
      throw new Error("Error: client not initialized");
    }

    const [ctokens] = txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::deposit_liquidity_and_mint_ctokens`,
      arguments: [
        // lending market
        txb.object(this.lendingMarket.id),
        // clock
        txb.object(SUI_CLOCK_OBJECT_ID),
        txb.object(coinsId),
      ],
      typeArguments: [this.lendingMarket.$typeArg, coinType],
    });

    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::deposit_ctokens_into_obligation`,
      arguments: [
        // lending market
        txb.object(this.lendingMarket.id),
        // obligation owner cap
        txb.object(this.obligationOwnerCap.id),
        // ctokens
        ctokens,
      ],
      typeArguments: [this.lendingMarket.$typeArg, coinType],
    });
  }

  async setObligationOwnerCap(obligationOwnerCapId: string) {
    let obligationOwnerCapData = await this.client.getObject({
      id: obligationOwnerCapId,
      options: { showBcs: true },
    });

    if (obligationOwnerCapData.data?.bcs?.dataType !== "moveObject") {
      throw new Error("Error: invalid data type");
    }

    this.obligationOwnerCap = ObligationOwnerCap.fromBcs(
      this.lendingMarket.$typeArg,
      fromB64(obligationOwnerCapData.data.bcs.bcsBytes)
    );

    let obligationData = await this.client.getObject({
      id: this.obligationOwnerCap.obligationId,
      options: { showBcs: true },
    });

    if (obligationData.data?.bcs?.dataType !== "moveObject") {
      throw new Error("Error: invalid data type");
    }

    this.obligation = Obligation.fromBcs(
      this.lendingMarket.$typeArg,
      fromB64(obligationData.data.bcs.bcsBytes)
    );

    // console.log(this.obligationOwnerCap);
    // console.log(this.obligation);
  }

  async refresh_reserve_prices(
    txb: TransactionBlock,
    reserve_id: bigint,
    priceInfoObjectId: string
  ) {
    /*
    public fun refresh_reserve_price<P>(
        lending_market: &mut LendingMarket<P>, 
        reserve_id: u64,
        clock: &Clock,
        price_info: &PriceInfoObject,
        _ctx: &mut TxContext
    ) {
      */
    txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::refresh_reserve_price`,
      arguments: [
        txb.object(this.lendingMarket.id),
        txb.pure(reserve_id),
        txb.object(SUI_CLOCK_OBJECT_ID),
        txb.object(priceInfoObjectId),
      ],
      typeArguments: [this.lendingMarket.$typeArg],
    });
  }

  async refresh_all(txb: TransactionBlock, obligation: Obligation) {

    let reserveIdToPriceId = new Map<bigint, string>();
    obligation.deposits.forEach((deposit) => {
      let reserve =
        this.lendingMarket.reserves[deposit.reserveId as unknown as number];
      reserveIdToPriceId.set(
        deposit.reserveId,
        toHEX(new Uint8Array(reserve.priceIdentifier.bytes))
      );
    });

    obligation.borrows.forEach((borrow) => {
      let reserve =
        this.lendingMarket.reserves[borrow.reserveId as unknown as number];
      reserveIdToPriceId.set(
        borrow.reserveId,
        toHEX(new Uint8Array(reserve.priceIdentifier.bytes))
      );
    });

    // sort by reserveIdToPriceId by reserve id and create an array of tuples
    let tuples = Array.from(reserveIdToPriceId.entries()).sort();
    let priceIds = tuples.map((tuple) => tuple[1]);

    const priceUpdateData = await this.pythConnection.getPriceFeedsUpdateData(
      priceIds
    );
    const priceInfoObjectIds = await this.pythClient.updatePriceFeeds(
      txb,
      priceUpdateData,
      priceIds
    );

    for (let i = 0; i < tuples.length; i++) {
      this.refresh_reserve_prices(txb, tuples[i][0], priceInfoObjectIds[i]);
    }
  }

  async withdraw(coinType: string, amount: number, txb: TransactionBlock) {
    if (this.obligationOwnerCap == null || this.obligation == null) {
      throw new Error("Error: client not initialized");
    }

    await this.refresh_all(txb, this.obligation);

    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::withdraw`,
      arguments: [
        // lending market
        txb.object(this.lendingMarket.id),
        // obligation owner cap
        txb.object(this.obligationOwnerCap.id),
        // clock
        txb.object(SUI_CLOCK_OBJECT_ID),
        // ctokens
        txb.pure(amount),
      ],
      typeArguments: [this.lendingMarket.$typeArg, coinType],
    });
  }

  async borrow(coinType: string, amount: number, txb: TransactionBlock) {
    if (this.obligationOwnerCap == null || this.obligation == null) {
      throw new Error("Error: client not initialized");
    }

    await this.refresh_all(txb, this.obligation);

    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::borrow`,
      arguments: [
        // lending market
        txb.object(this.lendingMarket.id),
        // obligation owner cap
        txb.object(this.obligationOwnerCap.id),
        // clock
        txb.object(SUI_CLOCK_OBJECT_ID),
        // ctokens
        txb.pure(amount),
      ],
      typeArguments: [this.lendingMarket.$typeArg, coinType],
    });
  }

  repay(
    obligationId: string,
    coinType: string,
    coinId: string,
    txb: TransactionBlock
  ) {
    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::repay`,
      arguments: [
        // lending market
        txb.object(this.lendingMarket.id),
        // obligation
        txb.pure(obligationId),
        // clock
        txb.object(SUI_CLOCK_OBJECT_ID),
        // ctokens
        txb.object(coinId),
      ],
      typeArguments: [this.lendingMarket.$typeArg, coinType],
    });
  }

  async updateReserveConfig(
    ownerId: string,
    configArgs: ReserveConfigArgs,
    coinType: string,
    txb: TransactionBlock
  ) {
    let objs = await this.client.getOwnedObjects({
      owner: ownerId,
      filter: {
        StructType: `${SUILEND_CONTRACT_ADDRESS}::lending_market::LendingMarketOwnerCap<${this.lendingMarket.$typeArg}>`,
      },
    });

    if (objs.data.length == 0) {
      throw new Error("Error: no lending market owner cap found");
    }

    let ownerCapId = objs.data[0].data!.objectId;
    // public fun update_reserve_config<P, T>(
    //     _: &LendingMarketOwnerCap<P>,
    //     lending_market: &mut LendingMarket<P>,
    //     config: ReserveConfig,
    //     _ctx: &mut TxContext
    // ) {
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

    txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::update_reserve_config`,
      arguments: [
        txb.object(ownerCapId),
        txb.object(this.lendingMarket.id),
        config,
      ],
      typeArguments: [this.lendingMarket.$typeArg, coinType],
    });
  }

  async liquidate(
    txb: TransactionBlock,
    obligation: Obligation,
    repayCoinType: string,
    withdrawCoinType: string,
    repayCoinId: string
  ) {
    await this.refresh_all(txb, obligation);

    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::liquidate`,
      arguments: [
        // lending market
        txb.object(this.lendingMarket.id),
        // obligation id
        txb.pure(obligation.id),
        // clock
        txb.object(SUI_CLOCK_OBJECT_ID),
        // repay coin
        txb.object(repayCoinId),
      ],
      typeArguments: [this.lendingMarket.$typeArg, repayCoinType, withdrawCoinType],
    });
  }
}
