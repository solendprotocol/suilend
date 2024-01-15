import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { UID } from "../../0x2/object/structs";
import { PriceFeed } from "../price-feed/structs";
import { bcs } from "@mysten/bcs";
import { SuiClient, SuiParsedData } from "@mysten/sui.js/client";

/* ============================== PriceInfo =============================== */

export function isPriceInfo(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price_info::PriceInfo"
  );
}

export interface PriceInfoFields {
  attestationTime: bigint;
  arrivalTime: bigint;
  priceFeed: PriceFeed;
}

export class PriceInfo {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price_info::PriceInfo";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("PriceInfo", {
      attestation_time: bcs.u64(),
      arrival_time: bcs.u64(),
      price_feed: PriceFeed.bcs,
    });
  }

  readonly attestationTime: bigint;
  readonly arrivalTime: bigint;
  readonly priceFeed: PriceFeed;

  constructor(fields: PriceInfoFields) {
    this.attestationTime = fields.attestationTime;
    this.arrivalTime = fields.arrivalTime;
    this.priceFeed = fields.priceFeed;
  }

  static fromFields(fields: Record<string, any>): PriceInfo {
    return new PriceInfo({
      attestationTime: BigInt(fields.attestation_time),
      arrivalTime: BigInt(fields.arrival_time),
      priceFeed: PriceFeed.fromFields(fields.price_feed),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): PriceInfo {
    if (!isPriceInfo(item.type)) {
      throw new Error("not a PriceInfo type");
    }
    return new PriceInfo({
      attestationTime: BigInt(item.fields.attestation_time),
      arrivalTime: BigInt(item.fields.arrival_time),
      priceFeed: PriceFeed.fromFieldsWithTypes(item.fields.price_feed),
    });
  }

  static fromBcs(data: Uint8Array): PriceInfo {
    return PriceInfo.fromFields(PriceInfo.bcs.parse(data));
  }
}

/* ============================== PriceInfoObject =============================== */

export function isPriceInfoObject(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price_info::PriceInfoObject"
  );
}

export interface PriceInfoObjectFields {
  id: string;
  priceInfo: PriceInfo;
}

export class PriceInfoObject {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price_info::PriceInfoObject";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("PriceInfoObject", {
      id: UID.bcs,
      price_info: PriceInfo.bcs,
    });
  }

  readonly id: string;
  readonly priceInfo: PriceInfo;

  constructor(fields: PriceInfoObjectFields) {
    this.id = fields.id;
    this.priceInfo = fields.priceInfo;
  }

  static fromFields(fields: Record<string, any>): PriceInfoObject {
    return new PriceInfoObject({
      id: UID.fromFields(fields.id).id,
      priceInfo: PriceInfo.fromFields(fields.price_info),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): PriceInfoObject {
    if (!isPriceInfoObject(item.type)) {
      throw new Error("not a PriceInfoObject type");
    }
    return new PriceInfoObject({
      id: item.fields.id.id,
      priceInfo: PriceInfo.fromFieldsWithTypes(item.fields.price_info),
    });
  }

  static fromBcs(data: Uint8Array): PriceInfoObject {
    return PriceInfoObject.fromFields(PriceInfoObject.bcs.parse(data));
  }

  static fromSuiParsedData(content: SuiParsedData) {
    if (content.dataType !== "moveObject") {
      throw new Error("not an object");
    }
    if (!isPriceInfoObject(content.type)) {
      throw new Error(
        `object at ${
          (content.fields as any).id
        } is not a PriceInfoObject object`
      );
    }
    return PriceInfoObject.fromFieldsWithTypes(content);
  }

  static async fetch(client: SuiClient, id: string): Promise<PriceInfoObject> {
    const res = await client.getObject({ id, options: { showContent: true } });
    if (res.error) {
      throw new Error(
        `error fetching PriceInfoObject object at id ${id}: ${res.error.code}`
      );
    }
    if (
      res.data?.content?.dataType !== "moveObject" ||
      !isPriceInfoObject(res.data.content.type)
    ) {
      throw new Error(`object at id ${id} is not a PriceInfoObject object`);
    }
    return PriceInfoObject.fromFieldsWithTypes(res.data.content);
  }
}
