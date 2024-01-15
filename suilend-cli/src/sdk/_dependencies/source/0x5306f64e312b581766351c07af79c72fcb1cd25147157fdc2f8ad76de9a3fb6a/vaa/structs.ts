import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { Bytes32 } from "../bytes32/structs";
import { ExternalAddress } from "../external-address/structs";
import { bcs } from "@mysten/bcs";

/* ============================== VAA =============================== */

export function isVAA(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::vaa::VAA"
  );
}

export interface VAAFields {
  guardianSetIndex: number;
  timestamp: number;
  nonce: number;
  emitterChain: number;
  emitterAddress: ExternalAddress;
  sequence: bigint;
  consistencyLevel: number;
  payload: Array<number>;
  digest: Bytes32;
}

export class VAA {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::vaa::VAA";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("VAA", {
      guardian_set_index: bcs.u32(),
      timestamp: bcs.u32(),
      nonce: bcs.u32(),
      emitter_chain: bcs.u16(),
      emitter_address: ExternalAddress.bcs,
      sequence: bcs.u64(),
      consistency_level: bcs.u8(),
      payload: bcs.vector(bcs.u8()),
      digest: Bytes32.bcs,
    });
  }

  readonly guardianSetIndex: number;
  readonly timestamp: number;
  readonly nonce: number;
  readonly emitterChain: number;
  readonly emitterAddress: ExternalAddress;
  readonly sequence: bigint;
  readonly consistencyLevel: number;
  readonly payload: Array<number>;
  readonly digest: Bytes32;

  constructor(fields: VAAFields) {
    this.guardianSetIndex = fields.guardianSetIndex;
    this.timestamp = fields.timestamp;
    this.nonce = fields.nonce;
    this.emitterChain = fields.emitterChain;
    this.emitterAddress = fields.emitterAddress;
    this.sequence = fields.sequence;
    this.consistencyLevel = fields.consistencyLevel;
    this.payload = fields.payload;
    this.digest = fields.digest;
  }

  static fromFields(fields: Record<string, any>): VAA {
    return new VAA({
      guardianSetIndex: fields.guardian_set_index,
      timestamp: fields.timestamp,
      nonce: fields.nonce,
      emitterChain: fields.emitter_chain,
      emitterAddress: ExternalAddress.fromFields(fields.emitter_address),
      sequence: BigInt(fields.sequence),
      consistencyLevel: fields.consistency_level,
      payload: fields.payload.map((item: any) => item),
      digest: Bytes32.fromFields(fields.digest),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): VAA {
    if (!isVAA(item.type)) {
      throw new Error("not a VAA type");
    }
    return new VAA({
      guardianSetIndex: item.fields.guardian_set_index,
      timestamp: item.fields.timestamp,
      nonce: item.fields.nonce,
      emitterChain: item.fields.emitter_chain,
      emitterAddress: ExternalAddress.fromFieldsWithTypes(
        item.fields.emitter_address
      ),
      sequence: BigInt(item.fields.sequence),
      consistencyLevel: item.fields.consistency_level,
      payload: item.fields.payload.map((item: any) => item),
      digest: Bytes32.fromFieldsWithTypes(item.fields.digest),
    });
  }

  static fromBcs(data: Uint8Array): VAA {
    return VAA.fromFields(VAA.bcs.parse(data));
  }
}
