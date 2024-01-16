import { JsonRpcProvider } from "@mysten/sui.js";
import {
  Type,
} from "../../../../_framework/util";
import { UID } from "../object/structs";
import { bcs } from "@mysten/bcs";

/* ============================== Bag =============================== */

export interface BagFields {
  id: string;
  size: bigint;
}

export class Bag {
  static readonly $typeName = "0x2::bag::Bag";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("Bag", {
      id: UID.bcs,
      size: bcs.u64(),
    });
  }

  readonly id: string;
  readonly size: bigint;

  constructor(fields: BagFields) {
    this.id = fields.id;
    this.size = fields.size;
  }

  static fromFields(fields: Record<string, any>): Bag {
    return new Bag({
      id: UID.fromFields(fields.id).id,
      size: BigInt(fields.size),
    });
  }

  static fromBcs(data: Uint8Array): Bag {
    return Bag.fromFields(Bag.bcs.parse(data));
  }
}
