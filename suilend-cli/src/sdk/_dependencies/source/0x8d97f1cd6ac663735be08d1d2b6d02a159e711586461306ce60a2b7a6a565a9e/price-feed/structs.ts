import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { PriceIdentifier } from "../price-identifier/structs";
import { Price } from "../price/structs";
import { bcs } from "@mysten/bcs";

/* ============================== PriceFeed =============================== */

export function isPriceFeed(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price_feed::PriceFeed"
  );
}

export interface PriceFeedFields {
  priceIdentifier: PriceIdentifier;
  price: Price;
  emaPrice: Price;
}

export class PriceFeed {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::price_feed::PriceFeed";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("PriceFeed", {
      price_identifier: PriceIdentifier.bcs,
      price: Price.bcs,
      ema_price: Price.bcs,
    });
  }

  readonly priceIdentifier: PriceIdentifier;
  readonly price: Price;
  readonly emaPrice: Price;

  constructor(fields: PriceFeedFields) {
    this.priceIdentifier = fields.priceIdentifier;
    this.price = fields.price;
    this.emaPrice = fields.emaPrice;
  }

  static fromFields(fields: Record<string, any>): PriceFeed {
    return new PriceFeed({
      priceIdentifier: PriceIdentifier.fromFields(fields.price_identifier),
      price: Price.fromFields(fields.price),
      emaPrice: Price.fromFields(fields.ema_price),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): PriceFeed {
    if (!isPriceFeed(item.type)) {
      throw new Error("not a PriceFeed type");
    }
    return new PriceFeed({
      priceIdentifier: PriceIdentifier.fromFieldsWithTypes(
        item.fields.price_identifier
      ),
      price: Price.fromFieldsWithTypes(item.fields.price),
      emaPrice: Price.fromFieldsWithTypes(item.fields.ema_price),
    });
  }

  static fromBcs(data: Uint8Array): PriceFeed {
    return PriceFeed.fromFields(PriceFeed.bcs.parse(data));
  }
}
