import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { ID } from "../../0x2/object/structs";
import { bcs } from "@mysten/bcs";

/* ============================== MessageTicket =============================== */

export function isMessageTicket(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::publish_message::MessageTicket"
  );
}

export interface MessageTicketFields {
  sender: string;
  sequence: bigint;
  nonce: number;
  payload: Array<number>;
}

export class MessageTicket {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::publish_message::MessageTicket";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("MessageTicket", {
      sender: ID.bcs,
      sequence: bcs.u64(),
      nonce: bcs.u32(),
      payload: bcs.vector(bcs.u8()),
    });
  }

  readonly sender: string;
  readonly sequence: bigint;
  readonly nonce: number;
  readonly payload: Array<number>;

  constructor(fields: MessageTicketFields) {
    this.sender = fields.sender;
    this.sequence = fields.sequence;
    this.nonce = fields.nonce;
    this.payload = fields.payload;
  }

  static fromFields(fields: Record<string, any>): MessageTicket {
    return new MessageTicket({
      sender: ID.fromFields(fields.sender).bytes,
      sequence: BigInt(fields.sequence),
      nonce: fields.nonce,
      payload: fields.payload.map((item: any) => item),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): MessageTicket {
    if (!isMessageTicket(item.type)) {
      throw new Error("not a MessageTicket type");
    }
    return new MessageTicket({
      sender: item.fields.sender,
      sequence: BigInt(item.fields.sequence),
      nonce: item.fields.nonce,
      payload: item.fields.payload.map((item: any) => item),
    });
  }

  static fromBcs(data: Uint8Array): MessageTicket {
    return MessageTicket.fromFields(MessageTicket.bcs.parse(data));
  }
}

/* ============================== WormholeMessage =============================== */

export function isWormholeMessage(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::publish_message::WormholeMessage"
  );
}

export interface WormholeMessageFields {
  sender: string;
  sequence: bigint;
  nonce: number;
  payload: Array<number>;
  consistencyLevel: number;
  timestamp: bigint;
}

export class WormholeMessage {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::publish_message::WormholeMessage";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("WormholeMessage", {
      sender: ID.bcs,
      sequence: bcs.u64(),
      nonce: bcs.u32(),
      payload: bcs.vector(bcs.u8()),
      consistency_level: bcs.u8(),
      timestamp: bcs.u64(),
    });
  }

  readonly sender: string;
  readonly sequence: bigint;
  readonly nonce: number;
  readonly payload: Array<number>;
  readonly consistencyLevel: number;
  readonly timestamp: bigint;

  constructor(fields: WormholeMessageFields) {
    this.sender = fields.sender;
    this.sequence = fields.sequence;
    this.nonce = fields.nonce;
    this.payload = fields.payload;
    this.consistencyLevel = fields.consistencyLevel;
    this.timestamp = fields.timestamp;
  }

  static fromFields(fields: Record<string, any>): WormholeMessage {
    return new WormholeMessage({
      sender: ID.fromFields(fields.sender).bytes,
      sequence: BigInt(fields.sequence),
      nonce: fields.nonce,
      payload: fields.payload.map((item: any) => item),
      consistencyLevel: fields.consistency_level,
      timestamp: BigInt(fields.timestamp),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): WormholeMessage {
    if (!isWormholeMessage(item.type)) {
      throw new Error("not a WormholeMessage type");
    }
    return new WormholeMessage({
      sender: item.fields.sender,
      sequence: BigInt(item.fields.sequence),
      nonce: item.fields.nonce,
      payload: item.fields.payload.map((item: any) => item),
      consistencyLevel: item.fields.consistency_level,
      timestamp: BigInt(item.fields.timestamp),
    });
  }

  static fromBcs(data: Uint8Array): WormholeMessage {
    return WormholeMessage.fromFields(WormholeMessage.bcs.parse(data));
  }
}
