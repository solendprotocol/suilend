// import { initLoaderIfNeeded } from "../../../../_framework/init-source";
// import { structClassLoaderSource } from "../../../../_framework/loader";
import {
  Type,
} from "../../../../_framework/util";
import { BcsType, bcs, fromHEX, toHEX } from "@mysten/bcs";

/* ============================== DynamicFields =============================== */

export interface DynamicFieldsFields<K> {
  names: Array<K>;
}

// export class DynamicFields<K> {
//   static readonly $typeName = "0x2::object::DynamicFields";
//   static readonly $numTypeParams = 1;

//   static get bcs() {
//     return <K extends BcsType<any>>(K: K) =>
//       bcs.struct(`DynamicFields<${K.name}>`, {
//         names: bcs.vector(K),
//       });
//   }

//   readonly $typeArg: Type;

//   readonly names: Array<K>;

//   constructor(typeArg: Type, names: Array<K>) {
//     this.$typeArg = typeArg;

//     this.names = names;
//   }

//   static fromFields<K>(
//     typeArg: Type,
//     fields: Record<string, any>
//   ): DynamicFields<K> {
//     // initLoaderIfNeeded();

//     return new DynamicFields(
//       typeArg,
//       fields.names.map((item: any) =>
//         structClassLoaderSource.fromFields(typeArg, item)
//       )
//     );
//   }

//   static fromBcs<K>(typeArg: Type, data: Uint8Array): DynamicFields<K> {
//     // initLoaderIfNeeded();

//     const typeArgs = [typeArg];

//     return DynamicFields.fromFields(
//       typeArg,
//       DynamicFields.bcs(structClassLoaderSource.getBcsType(typeArgs[0])).parse(
//         data
//       )
//     );
//   }

// }

/* ============================== ID =============================== */

export interface IDFields {
  bytes: string;
}

export class ID {
  static readonly $typeName = "0x2::object::ID";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("ID", {
      bytes: bcs
        .bytes(32)
        .transform({
          input: (val: string) => fromHEX(val),
          output: (val: Uint8Array) => toHEX(val),
        }),
    });
  }

  readonly bytes: string;

  constructor(bytes: string) {
    this.bytes = bytes;
  }

  static fromFields(fields: Record<string, any>): ID {
    return new ID(`0x${fields.bytes}`);
  }

  static fromBcs(data: Uint8Array): ID {
    return ID.fromFields(ID.bcs.parse(data));
  }
}

/* ============================== Ownership =============================== */

export interface OwnershipFields {
  owner: string;
  status: bigint;
}

export class Ownership {
  static readonly $typeName = "0x2::object::Ownership";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("Ownership", {
      owner: bcs
        .bytes(32)
        .transform({
          input: (val: string) => fromHEX(val),
          output: (val: Uint8Array) => toHEX(val),
        }),
      status: bcs.u64(),
    });
  }

  readonly owner: string;
  readonly status: bigint;

  constructor(fields: OwnershipFields) {
    this.owner = fields.owner;
    this.status = fields.status;
  }

  static fromFields(fields: Record<string, any>): Ownership {
    return new Ownership({
      owner: `0x${fields.owner}`,
      status: BigInt(fields.status),
    });
  }

  static fromBcs(data: Uint8Array): Ownership {
    return Ownership.fromFields(Ownership.bcs.parse(data));
  }

}

/* ============================== UID =============================== */

export interface UIDFields {
  id: string;
}

export class UID {
  static readonly $typeName = "0x2::object::UID";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("UID", {
      id: ID.bcs,
    });
  }

  readonly id: string;

  constructor(id: string) {
    this.id = id;
  }

  static fromFields(fields: Record<string, any>): UID {
    return new UID(ID.fromFields(fields.id).bytes);
  }

  static fromBcs(data: Uint8Array): UID {
    return UID.fromFields(UID.bcs.parse(data));
  }
}
