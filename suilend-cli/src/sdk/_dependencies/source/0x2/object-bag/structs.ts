import {
  Type,
} from "../../../../_framework/util";
import { UID } from "../object/structs";
import { bcs } from "@mysten/bcs";

/* ============================== ObjectBag =============================== */

export interface ObjectBagFields {
  id: string;
  size: bigint;
}

export class ObjectBag {
  static readonly $typeName = "0x2::object_bag::ObjectBag";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("ObjectBag", {
      id: UID.bcs,
      size: bcs.u64(),
    });
  }

  readonly id: string;
  readonly size: bigint;

  constructor(fields: ObjectBagFields) {
    this.id = fields.id;
    this.size = fields.size;
  }

  static fromFields(fields: Record<string, any>): ObjectBag {
    return new ObjectBag({
      id: UID.fromFields(fields.id).id,
      size: BigInt(fields.size),
    });
  }

  static fromBcs(data: Uint8Array): ObjectBag {
    return ObjectBag.fromFields(ObjectBag.bcs.parse(data));
  }
}
