import { getFullnodeUrl, SuiClient, CoinBalance } from '@mysten/sui.js/client';
import { getFaucetHost, requestSuiFromFaucetV0 } from '@mysten/sui.js/faucet';
import { MIST_PER_SUI } from '@mysten/sui.js/utils';
import { TransactionBlock, TransactionResult } from '@mysten/sui.js/transactions';
import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519';
import { fromHEX, fromB64 } from '@mysten/sui.js/utils';
import * as fs from 'fs';
 
// replace <YOUR_SUI_ADDRESS> with your actual address, which is in the form 0x123...
const MY_ADDRESS = '0x4f3446baf9ca583b920e81924b94883b64addc2a2671963b546aaef77f79a28b';
const SUILEND_CONTRACT_ADDRESS = '0x3e0f71de00c069581c78b1ce8262a101760320759a2a7299dc5032dbad5e9d99';
 
class SuilendClient {
  lendingMarketId: string;
  lendingMarketType: string | null;
  client: SuiClient;

  constructor(lendingMarketId: string, client: SuiClient) {
    this.lendingMarketId = lendingMarketId;
    this.lendingMarketType = null;
    this.client = client;
  }

  async initialize() {
    let lendingMarket = await this.client.getObject({ id: this.lendingMarketId, options: { showContent: true }});
    if (lendingMarket.data?.content?.dataType === "moveObject") {
      const outerType = lendingMarket.data?.content?.type;
      this.lendingMarketType = outerType.substring(outerType.indexOf("<") + 1, outerType.indexOf(">"));
      console.log(`Lending market type: ${this.lendingMarketType}`);
    }
    else {
      throw new Error("Error: lending market type not found");
    }

  }

  createObligation(
    txb: TransactionBlock,
  ): TransactionResult {
    if (this.lendingMarketType == null) {
      throw new Error("Error: client not initialized");
    }

    return txb.moveCall({
      target: `${SUILEND_CONTRACT_ADDRESS}::lending_market::create_obligation`,
      arguments: [
        txb.object(this.lendingMarketId),
      ],
      typeArguments: [
        this.lendingMarketType
      ]
    });
  }



}

async function main() {
  // create a new SuiClient object pointing to the network you want to use
  const client = new SuiClient({ url: getFullnodeUrl('mainnet') });
  const lendingMarketId = "0x00a98a36386c16c5d26ebf80f07139318a8608a0d505641c009625eb86517cd3";
  const sui_metadata = await client.getCoinMetadata({ coinType: '0x2::sui::SUI' })!;
  const suilendClient = new SuilendClient(lendingMarketId, client);
  await suilendClient.initialize();
  // console.log(sui_metadata);


  const keypair = Ed25519Keypair.fromSecretKey(fromHEX(process.env.SUI_SECRET_KEY!));

  const txb = new TransactionBlock();
  const [obligationOwnerCap] = suilendClient.createObligation(txb);
  txb.transferObjects([obligationOwnerCap], MY_ADDRESS);
  // let [config] = txb.moveCall({
  //   target: "0x3e0f71de00c069581c78b1ce8262a101760320759a2a7299dc5032dbad5e9d99::reserve::create_reserve_config",
  //   arguments: [
  //     // open ltv pct
  //     txb.pure(50),
  //     // close ltv pct
  //     txb.pure(60),
  //     // borrow weight bps
  //     txb.pure(10000),
  //     // deposit limit
  //     txb.pure(1000000000000000000),
  //     // borrow limit
  //     txb.pure(1000000000000000000),
  //     // borrow fee bps
  //     txb.pure(0),
  //     // spread fee bps
  //     txb.pure(0),
  //     // liquidation fee bps
  //     txb.pure(0),
  //     // interest rate utils
  //     // txb.pure(0),
  //     txb.pure([0]),
  //     // interest rate aprs
  //     txb.pure([0]),
  //     // txb.pure(0),
  //     // txb.pure(new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0])),
  //   ]
  // });
  // /*
  //     public fun add_reserve<P, T>(
  //       _: &LendingMarketOwnerCap<P>, 
  //       lending_market: &mut LendingMarket<P>, 
  //       // scaled by 10^18
  //       price: u256,
  //       config: ReserveConfig,
  //       coin_metadata: &CoinMetadata<T>,
  //       clock: &Clock,
  //       _ctx: &mut TxContext
  //   ) {
  // */
  // txb.moveCall({
  //   target: "0x3e0f71de00c069581c78b1ce8262a101760320759a2a7299dc5032dbad5e9d99::lending_market::add_reserve",
  //   arguments: [
  //     // owner cap
  //     txb.object("0x3df4b11548f9189e8c0d0a29287e9c42fd81948bd42e37a0152b60bd9c6e8277"),
  //     // lending market
  //     txb.object("0x00a98a36386c16c5d26ebf80f07139318a8608a0d505641c009625eb86517cd3"),
  //     // price
  //     txb.pure(1),
  //     // config
  //     config,
  //     // coin metadata
  //     txb.object(sui_metadata?.id || "asdf"),

  //     // clock
  //     txb.object("0x0000000000000000000000000000000000000000000000000000000000000006")
  //   ],
  //   typeArguments: [
  //     "0x3e0f71de00c069581c78b1ce8262a101760320759a2a7299dc5032dbad5e9d99::launch::LAUNCH",
  //     "0x2::sui::SUI"
  //   ]
  // });
  // txb.setGasBudget(100000000);

  const res = await client.signAndExecuteTransactionBlock({ signer: keypair, transactionBlock: txb });
  console.log(res);

  // const { bytes, signature } = await txb.sign({ client: suiClient, signer: keypair })
  // suiClient.executeTransactionBlock({
  //   tra

  // })

  // Convert MIST to Sui
}

main();