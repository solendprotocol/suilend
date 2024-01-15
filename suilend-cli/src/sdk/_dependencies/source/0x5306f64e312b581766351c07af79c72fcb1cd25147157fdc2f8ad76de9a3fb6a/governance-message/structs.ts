import {
  FieldsWithTypes,
  Type,
  compressSuiType,
  parseTypeName,
} from "../../../../_framework/util";
import { Bytes32 } from "../bytes32/structs";
import { ExternalAddress } from "../external-address/structs";
import { bcs } from "@mysten/bcs";

/* ============================== DecreeReceipt =============================== */

export function isDecreeReceipt(type: Type): boolean {
  type = compressSuiType(type);
  return type.startsWith(
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::governance_message::DecreeReceipt<"
  );
}

export interface DecreeReceiptFields {
  payload: Array<number>;
  digest: Bytes32;
  sequence: bigint;
}

export class DecreeReceipt {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::governance_message::DecreeReceipt";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("DecreeReceipt", {
      payload: bcs.vector(bcs.u8()),
      digest: Bytes32.bcs,
      sequence: bcs.u64(),
    });
  }

  readonly $typeArg: Type;

  readonly payload: Array<number>;
  readonly digest: Bytes32;
  readonly sequence: bigint;

  constructor(typeArg: Type, fields: DecreeReceiptFields) {
    this.$typeArg = typeArg;

    this.payload = fields.payload;
    this.digest = fields.digest;
    this.sequence = fields.sequence;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): DecreeReceipt {
    return new DecreeReceipt(typeArg, {
      payload: fields.payload.map((item: any) => item),
      digest: Bytes32.fromFields(fields.digest),
      sequence: BigInt(fields.sequence),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): DecreeReceipt {
    if (!isDecreeReceipt(item.type)) {
      throw new Error("not a DecreeReceipt type");
    }
    const { typeArgs } = parseTypeName(item.type);

    return new DecreeReceipt(typeArgs[0], {
      payload: item.fields.payload.map((item: any) => item),
      digest: Bytes32.fromFieldsWithTypes(item.fields.digest),
      sequence: BigInt(item.fields.sequence),
    });
  }

  static fromBcs(typeArg: Type, data: Uint8Array): DecreeReceipt {
    return DecreeReceipt.fromFields(typeArg, DecreeReceipt.bcs.parse(data));
  }
}

/* ============================== DecreeTicket =============================== */

export function isDecreeTicket(type: Type): boolean {
  type = compressSuiType(type);
  return type.startsWith(
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::governance_message::DecreeTicket<"
  );
}

export interface DecreeTicketFields {
  governanceChain: number;
  governanceContract: ExternalAddress;
  moduleName: Bytes32;
  action: number;
  global: boolean;
}

export class DecreeTicket {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::governance_message::DecreeTicket";
  static readonly $numTypeParams = 1;

  static get bcs() {
    return bcs.struct("DecreeTicket", {
      governance_chain: bcs.u16(),
      governance_contract: ExternalAddress.bcs,
      module_name: Bytes32.bcs,
      action: bcs.u8(),
      global: bcs.bool(),
    });
  }

  readonly $typeArg: Type;

  readonly governanceChain: number;
  readonly governanceContract: ExternalAddress;
  readonly moduleName: Bytes32;
  readonly action: number;
  readonly global: boolean;

  constructor(typeArg: Type, fields: DecreeTicketFields) {
    this.$typeArg = typeArg;

    this.governanceChain = fields.governanceChain;
    this.governanceContract = fields.governanceContract;
    this.moduleName = fields.moduleName;
    this.action = fields.action;
    this.global = fields.global;
  }

  static fromFields(typeArg: Type, fields: Record<string, any>): DecreeTicket {
    return new DecreeTicket(typeArg, {
      governanceChain: fields.governance_chain,
      governanceContract: ExternalAddress.fromFields(
        fields.governance_contract
      ),
      moduleName: Bytes32.fromFields(fields.module_name),
      action: fields.action,
      global: fields.global,
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): DecreeTicket {
    if (!isDecreeTicket(item.type)) {
      throw new Error("not a DecreeTicket type");
    }
    const { typeArgs } = parseTypeName(item.type);

    return new DecreeTicket(typeArgs[0], {
      governanceChain: item.fields.governance_chain,
      governanceContract: ExternalAddress.fromFieldsWithTypes(
        item.fields.governance_contract
      ),
      moduleName: Bytes32.fromFieldsWithTypes(item.fields.module_name),
      action: item.fields.action,
      global: item.fields.global,
    });
  }

  static fromBcs(typeArg: Type, data: Uint8Array): DecreeTicket {
    return DecreeTicket.fromFields(typeArg, DecreeTicket.bcs.parse(data));
  }
}
