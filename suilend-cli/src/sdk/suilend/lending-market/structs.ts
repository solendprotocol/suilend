import { JsonRpcProvider } from "@mysten/sui.js";
import { Bag } from "../../_dependencies/source/0x2/bag/structs";
import { ObjectBag } from "../../_dependencies/source/0x2/object-bag/structs";
import { ID, UID } from "../../_dependencies/source/0x2/object/structs";
import {
  Type,
} from "../../_framework/util";
import { Reserve } from "../reserve/structs";
import { bcs } from "@mysten/bcs";

/* ============================== Name =============================== */

export interface NameFields {
  dummyField: boolean;
}

export class Name {
  static readonly $typeName = "0x0::lending_market::Name";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("Name", {
      dummy_field: bcs.bool(),
    });
  }

  readonly $typeArg: Type;

  readonly dummyField: boolean;

  constructor(typeArg: Type, dummyField: boolean) {
    this.$typeArg = typeArg;

    this.dummyField = dummyField;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): Name {
    return new Name(typeArg, fields.dummy_field);
  }

  static fromBcs(typeArg: Type, data: Uint8Array): Name {
    return Name.fromFields(typeArg, Name.bcs.parse(data));
  }
}

/* ============================== LendingMarket =============================== */

export interface LendingMarketFields {
  id: string;
  reserves: Array<Reserve>;
  reserveTreasuries: Bag;
  obligations: ObjectBag;
}

export class LendingMarket {
  static readonly $typeName = "0x0::lending_market::LendingMarket";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("LendingMarket", {
      id: UID.bcs,
      reserves: bcs.vector(Reserve.bcs),
      reserve_treasuries: Bag.bcs,
      obligations: ObjectBag.bcs,
    });
  }

  readonly $typeArg: Type;

  readonly id: string;
  readonly reserves: Array<Reserve>;
  readonly reserveTreasuries: Bag;
  readonly obligations: ObjectBag;

  constructor(typeArg: Type, fields: LendingMarketFields) {
    this.$typeArg = typeArg;

    this.id = fields.id;
    this.reserves = fields.reserves;
    this.reserveTreasuries = fields.reserveTreasuries;
    this.obligations = fields.obligations;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): LendingMarket {
    return new LendingMarket(typeArg, {
      id: UID.fromFields(fields.id).id,
      reserves: fields.reserves.map((item: any) =>
        Reserve.fromFields(`${typeArg}`, item)
      ),
      reserveTreasuries: Bag.fromFields(fields.reserve_treasuries),
      obligations: ObjectBag.fromFields(fields.obligations),
    });
  }

  static fromBcs(typeArg: Type, data: Uint8Array): LendingMarket {
    return LendingMarket.fromFields(typeArg, LendingMarket.bcs.parse(data));
  }
}

/* ============================== LendingMarketOwnerCap =============================== */

export interface LendingMarketOwnerCapFields {
  id: string;
}

export class LendingMarketOwnerCap {
  static readonly $typeName = "0x0::lending_market::LendingMarketOwnerCap";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("LendingMarketOwnerCap", {
      id: UID.bcs,
    });
  }

  readonly $typeArg: Type;

  readonly id: string;

  constructor(typeArg: Type, id: string) {
    this.$typeArg = typeArg;

    this.id = id;
  }

  static fromFields(
    typeArg: Type,
    fields: Record<string, any>
  ): LendingMarketOwnerCap {
    return new LendingMarketOwnerCap(typeArg, UID.fromFields(fields.id).id);
  }

  static fromBcs(typeArg: Type, data: Uint8Array): LendingMarketOwnerCap {
    return LendingMarketOwnerCap.fromFields(
      typeArg,
      LendingMarketOwnerCap.bcs.parse(data)
    );
  }
}

/* ============================== ObligationOwnerCap =============================== */

export interface ObligationOwnerCapFields {
  id: string;
  obligationId: string;
}

export class ObligationOwnerCap {
  static readonly $typeName = "0x0::lending_market::ObligationOwnerCap";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("ObligationOwnerCap", {
      id: UID.bcs,
      obligation_id: ID.bcs,
    });
  }

  readonly $typeArg: Type;

  readonly id: string;
  readonly obligationId: string;

  constructor(typeArg: Type, fields: ObligationOwnerCapFields) {
    this.$typeArg = typeArg;

    this.id = fields.id;
    this.obligationId = fields.obligationId;
  }

  static fromFields(
    typeArg: Type,
    fields: Record<string, any>
  ): ObligationOwnerCap {
    return new ObligationOwnerCap(typeArg, {
      id: UID.fromFields(fields.id).id,
      obligationId: ID.fromFields(fields.obligation_id).bytes,
    });
  }

  static fromBcs(typeArg: Type, data: Uint8Array): ObligationOwnerCap {
    return ObligationOwnerCap.fromFields(
      typeArg,
      ObligationOwnerCap.bcs.parse(data)
    );
  }
}
