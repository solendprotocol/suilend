import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { PriceInfo } from "../price-info/structs";
import { bcs } from "@mysten/bcs";

/* ============================== BatchPriceAttestation =============================== */

export function isBatchPriceAttestation(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::batch_price_attestation::BatchPriceAttestation"
  );
}

export interface BatchPriceAttestationFields {
  header: Header;
  attestationSize: bigint;
  attestationCount: bigint;
  priceInfos: Array<PriceInfo>;
}

export class BatchPriceAttestation {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::batch_price_attestation::BatchPriceAttestation";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("BatchPriceAttestation", {
      header: Header.bcs,
      attestation_size: bcs.u64(),
      attestation_count: bcs.u64(),
      price_infos: bcs.vector(PriceInfo.bcs),
    });
  }

  readonly header: Header;
  readonly attestationSize: bigint;
  readonly attestationCount: bigint;
  readonly priceInfos: Array<PriceInfo>;

  constructor(fields: BatchPriceAttestationFields) {
    this.header = fields.header;
    this.attestationSize = fields.attestationSize;
    this.attestationCount = fields.attestationCount;
    this.priceInfos = fields.priceInfos;
  }

  static fromFields(fields: Record<string, any>): BatchPriceAttestation {
    return new BatchPriceAttestation({
      header: Header.fromFields(fields.header),
      attestationSize: BigInt(fields.attestation_size),
      attestationCount: BigInt(fields.attestation_count),
      priceInfos: fields.price_infos.map((item: any) =>
        PriceInfo.fromFields(item)
      ),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): BatchPriceAttestation {
    if (!isBatchPriceAttestation(item.type)) {
      throw new Error("not a BatchPriceAttestation type");
    }
    return new BatchPriceAttestation({
      header: Header.fromFieldsWithTypes(item.fields.header),
      attestationSize: BigInt(item.fields.attestation_size),
      attestationCount: BigInt(item.fields.attestation_count),
      priceInfos: item.fields.price_infos.map((item: any) =>
        PriceInfo.fromFieldsWithTypes(item)
      ),
    });
  }

  static fromBcs(data: Uint8Array): BatchPriceAttestation {
    return BatchPriceAttestation.fromFields(
      BatchPriceAttestation.bcs.parse(data)
    );
  }
}

/* ============================== Header =============================== */

export function isHeader(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::batch_price_attestation::Header"
  );
}

export interface HeaderFields {
  magic: bigint;
  versionMajor: bigint;
  versionMinor: bigint;
  headerSize: bigint;
  payloadId: number;
}

export class Header {
  static readonly $typeName =
    "0x8d97f1cd6ac663735be08d1d2b6d02a159e711586461306ce60a2b7a6a565a9e::batch_price_attestation::Header";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("Header", {
      magic: bcs.u64(),
      version_major: bcs.u64(),
      version_minor: bcs.u64(),
      header_size: bcs.u64(),
      payload_id: bcs.u8(),
    });
  }

  readonly magic: bigint;
  readonly versionMajor: bigint;
  readonly versionMinor: bigint;
  readonly headerSize: bigint;
  readonly payloadId: number;

  constructor(fields: HeaderFields) {
    this.magic = fields.magic;
    this.versionMajor = fields.versionMajor;
    this.versionMinor = fields.versionMinor;
    this.headerSize = fields.headerSize;
    this.payloadId = fields.payloadId;
  }

  static fromFields(fields: Record<string, any>): Header {
    return new Header({
      magic: BigInt(fields.magic),
      versionMajor: BigInt(fields.version_major),
      versionMinor: BigInt(fields.version_minor),
      headerSize: BigInt(fields.header_size),
      payloadId: fields.payload_id,
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): Header {
    if (!isHeader(item.type)) {
      throw new Error("not a Header type");
    }
    return new Header({
      magic: BigInt(item.fields.magic),
      versionMajor: BigInt(item.fields.version_major),
      versionMinor: BigInt(item.fields.version_minor),
      headerSize: BigInt(item.fields.header_size),
      payloadId: item.fields.payload_id,
    });
  }

  static fromBcs(data: Uint8Array): Header {
    return Header.fromFields(Header.bcs.parse(data));
  }
}
