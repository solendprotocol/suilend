import {
  FieldsWithTypes,
  Type,
  compressSuiType,
} from "../../../../_framework/util";
import { ID } from "../../0x2/object/structs";
import { Bytes32 } from "../bytes32/structs";
import { bcs } from "@mysten/bcs";

/* ============================== CurrentPackage =============================== */

export function isCurrentPackage(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::package_utils::CurrentPackage"
  );
}

export interface CurrentPackageFields {
  dummyField: boolean;
}

export class CurrentPackage {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::package_utils::CurrentPackage";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("CurrentPackage", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): CurrentPackage {
    return new CurrentPackage(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): CurrentPackage {
    if (!isCurrentPackage(item.type)) {
      throw new Error("not a CurrentPackage type");
    }
    return new CurrentPackage(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): CurrentPackage {
    return CurrentPackage.fromFields(CurrentPackage.bcs.parse(data));
  }
}

/* ============================== CurrentVersion =============================== */

export function isCurrentVersion(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::package_utils::CurrentVersion"
  );
}

export interface CurrentVersionFields {
  dummyField: boolean;
}

export class CurrentVersion {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::package_utils::CurrentVersion";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("CurrentVersion", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): CurrentVersion {
    return new CurrentVersion(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): CurrentVersion {
    if (!isCurrentVersion(item.type)) {
      throw new Error("not a CurrentVersion type");
    }
    return new CurrentVersion(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): CurrentVersion {
    return CurrentVersion.fromFields(CurrentVersion.bcs.parse(data));
  }
}

/* ============================== PackageInfo =============================== */

export function isPackageInfo(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::package_utils::PackageInfo"
  );
}

export interface PackageInfoFields {
  package: string;
  digest: Bytes32;
}

export class PackageInfo {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::package_utils::PackageInfo";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("PackageInfo", {
      package: ID.bcs,
      digest: Bytes32.bcs,
    });
  }

  readonly package: string;
  readonly digest: Bytes32;

  constructor(fields: PackageInfoFields) {
    this.package = fields.package;
    this.digest = fields.digest;
  }

  static fromFields(fields: Record<string, any>): PackageInfo {
    return new PackageInfo({
      package: ID.fromFields(fields.package).bytes,
      digest: Bytes32.fromFields(fields.digest),
    });
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): PackageInfo {
    if (!isPackageInfo(item.type)) {
      throw new Error("not a PackageInfo type");
    }
    return new PackageInfo({
      package: item.fields.package,
      digest: Bytes32.fromFieldsWithTypes(item.fields.digest),
    });
  }

  static fromBcs(data: Uint8Array): PackageInfo {
    return PackageInfo.fromFields(PackageInfo.bcs.parse(data));
  }
}

/* ============================== PendingPackage =============================== */

export function isPendingPackage(type: Type): boolean {
  type = compressSuiType(type);
  return (
    type ===
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::package_utils::PendingPackage"
  );
}

export interface PendingPackageFields {
  dummyField: boolean;
}

export class PendingPackage {
  static readonly $typeName =
    "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a::package_utils::PendingPackage";
  static readonly $numTypeParams = 0;

  static get bcs() {
    return bcs.struct("PendingPackage", {
      dummy_field: bcs.bool(),
    });
  }

  readonly dummyField: boolean;

  constructor(dummyField: boolean) {
    this.dummyField = dummyField;
  }

  static fromFields(fields: Record<string, any>): PendingPackage {
    return new PendingPackage(fields.dummy_field);
  }

  static fromFieldsWithTypes(item: FieldsWithTypes): PendingPackage {
    if (!isPendingPackage(item.type)) {
      throw new Error("not a PendingPackage type");
    }
    return new PendingPackage(item.fields.dummy_field);
  }

  static fromBcs(data: Uint8Array): PendingPackage {
    return PendingPackage.fromFields(PendingPackage.bcs.parse(data));
  }
}
