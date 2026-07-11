# cooViewer v1.3.7 — Release Notes (draft)

> **Important: this is the final release with LhA/LZH (and other
> legacy-format) support.** Starting with v1.4.0, archive extraction
> is planned to migrate from XADMaster to libunarr, which supports
> ZIP/CBZ, RAR/CBR, 7z, and TAR only. If you rely on `.lzh`/`.lha`
> comic archives, keep v1.3.7 or convert your archives to ZIP.
>
> **重要: 本バージョンが LhA/LZH(およびその他レガシー形式)を
> サポートする最後のリリースです。** v1.4.0 でアーカイブ処理を
> XADMaster から libunarr(ZIP/CBZ・RAR/CBR・7z・TAR のみ対応)へ
> 移行する予定です。`.lzh`/`.lha` の書庫をお使いの場合は v1.3.7 を
> 保持するか、ZIP への変換をご検討ください。

## Fixed

- **Memory leak on every archive open**: a retain cycle between the
  archive wrapper and its items leaked the entire decompression
  object graph each time an archive was opened. Long reading
  sessions no longer grow memory unboundedly.

## Changed

- Resources consolidated into `Assets.xcassets` + `Resources/`
  (app icon migrated to an asset-catalog AppIcon; no visual change).
- Deprecated alert API (`NSRunAlertPanel`) replaced with `NSAlert` —
  confirmation dialogs now use the modern macOS appearance.

## Housekeeping

- Removed a stray localization working file (`ja.xliff`) that was
  shipped inside the app bundle.
- Removed dead files from the repository; fixed a case mismatch in
  the build settings (`info.plist` → `Info.plist`) that would break
  builds on case-sensitive file systems.

**Full Changelog**: https://github.com/kni927/cooViewer/compare/v1.3.6...v1.3.7
