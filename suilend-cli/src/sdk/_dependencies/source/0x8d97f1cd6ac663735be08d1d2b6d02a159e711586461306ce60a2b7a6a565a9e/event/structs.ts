import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { PriceFeed } from "../price-feed/structs";
import { bcs } from "@mysten/bcs";

/* ============================== PriceFeedUpdateEvent =============================== */

export function isPriceFeedUpdateEvent(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::event::PriceFeedUpdateEvent"
  );
}

export interface PriceFeedUpdateEventFields {
  priceFeed: PriceFeed;
  timestamp: bigint;
}

export class PriceFeedUpdateEvent {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::event::PriceFeedUpdateEvent";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("PriceFeedUpdateEvent", {
      price_feed: PriceFeed.bcs,
      timestamp: bcs.u64(),
    });
  }

  readonly priceFeed: PriceFeed;
  readonly timestamp: bigint;

  constructor(fields: PriceFeedUpdateEventFields) {
    this.priceFeed = fields.priceFeed;
    this.timestamp = fields.timestamp;
  }

  static fromFields(fields: Record<string, any>): PriceFeedUpdateEvent {
    return new PriceFeedUpdateEvent({
      priceFeed: PriceFeed.fromFields(fields.price_feed),
      timestamp: BigInt(fields.timestamp),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): PriceFeedUpdateEvent {
    if (!isPriceFeedUpdateEvent(item.type)) {
      throw new Error("not a PriceFeedUpdateEvent type");
    }
    return new PriceFeedUpdateEvent({
      priceFeed: PriceFeed.fromFieldsWithTypes(item.fields.price_feed),
      timestamp: BigInt(item.fields.timestamp),
    });
  }

  static fromBcs(data: Uint8Array): PriceFeedUpdateEvent {
    return PriceFeedUpdateEvent.fromFields(
      PriceFeedUpdateEvent.bcs.parse(data)
    );
  }
}

/* ============================== PythInitializationEvent =============================== */

export function isPythInitializationEvent(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::event::PythInitializationEvent"
  );
}

export interface PythInitializationEventFields {
  dummyField: boolean;
}

export class PythInitializationEvent {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::event::PythInitializationEvent";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("PythInitializationEvent", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): PythInitializationEvent {
    return new PythInitializationEvent(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): PythInitializationEvent {
    if (!isPythInitializationEvent(item.type)) {
      throw new Error("not a PythInitializationEvent type");
    }
    return new PythInitializationEvent(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): PythInitializationEvent {
    return PythInitializationEvent.fromFields(
      PythInitializationEvent.bcs.parse(data)
    );
  }
}
